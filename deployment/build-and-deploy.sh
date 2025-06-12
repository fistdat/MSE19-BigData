#!/bin/bash

# =============================================================================
# Nessie CDC Lakehouse - Build and Deploy Script
# =============================================================================
# Production-ready deployment script with error handling and monitoring
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
PROJECT_NAME="nessie-cdc-lakehouse"
APP_VERSION="1.0.0"
FLINK_APP_DIR="flink-cdc-app"
JAR_NAME="${PROJECT_NAME}-${APP_VERSION}.jar"
FLINK_REST_URL="http://localhost:8081"
DEPLOYMENT_TIMEOUT=300  # 5 minutes

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    log_error "Script failed at line $line_number with exit code $exit_code"
    cleanup_on_failure
    exit $exit_code
}

trap 'handle_error $LINENO' ERR

# Cleanup function
cleanup_on_failure() {
    log_warning "Performing cleanup due to failure..."
    # Add cleanup logic here if needed
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Maven is installed
    if ! command -v mvn &> /dev/null; then
        log_error "Maven is not installed. Please install Maven first."
        exit 1
    fi
    
    # Check if Docker is running
    if ! docker info &> /dev/null; then
        log_error "Docker is not running. Please start Docker first."
        exit 1
    fi
    
    # Check if Flink cluster is accessible
    if ! curl -s "$FLINK_REST_URL/overview" &> /dev/null; then
        log_error "Flink cluster is not accessible at $FLINK_REST_URL"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Build the application
build_application() {
    log_info "Building Flink application..."
    
    cd "$FLINK_APP_DIR"
    
    # Clean and compile
    mvn clean compile
    
    # Run tests (if any)
    log_info "Running tests..."
    mvn test
    
    # Package the application
    log_info "Packaging application..."
    mvn package -DskipTests
    
    # Verify JAR was created
    if [[ ! -f "target/$JAR_NAME" ]]; then
        log_error "JAR file not found: target/$JAR_NAME"
        exit 1
    fi
    
    log_success "Application built successfully: target/$JAR_NAME"
    cd ..
}

# Deploy to Flink cluster
deploy_to_flink() {
    log_info "Deploying to Flink cluster..."
    
    local jar_path="$FLINK_APP_DIR/target/$JAR_NAME"
    
    # Copy JAR to Flink container
    log_info "Copying JAR to Flink container..."
    docker cp "$jar_path" jobmanager:/opt/flink/lib/
    
    # Submit job via REST API
    log_info "Submitting job to Flink cluster..."
    
    # Create job submission payload
    local job_payload=$(cat <<EOF
{
    "entryClass": "com.bigdata.cdc.NessieCDCLakehouseApp",
    "programArgs": [],
    "parallelism": 2,
    "jobName": "$PROJECT_NAME",
    "allowNonRestoredState": false
}
EOF
)
    
    # Submit job
    local response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$job_payload" \
        "$FLINK_REST_URL/jars/$(basename $JAR_NAME)/run")
    
    # Extract job ID from response
    local job_id=$(echo "$response" | grep -o '"jobid":"[^"]*"' | cut -d'"' -f4)
    
    if [[ -z "$job_id" ]]; then
        log_error "Failed to submit job. Response: $response"
        exit 1
    fi
    
    log_success "Job submitted successfully. Job ID: $job_id"
    echo "$job_id" > .last_job_id
    
    # Wait for job to start
    wait_for_job_running "$job_id"
}

# Wait for job to reach RUNNING state
wait_for_job_running() {
    local job_id=$1
    local timeout=$DEPLOYMENT_TIMEOUT
    local elapsed=0
    local check_interval=5
    
    log_info "Waiting for job to start (timeout: ${timeout}s)..."
    
    while [[ $elapsed -lt $timeout ]]; do
        local status=$(curl -s "$FLINK_REST_URL/jobs/$job_id" | \
                      grep -o '"state":"[^"]*"' | cut -d'"' -f4)
        
        case "$status" in
            "RUNNING")
                log_success "Job is running successfully!"
                return 0
                ;;
            "FAILED"|"CANCELED")
                log_error "Job failed to start. Status: $status"
                show_job_exceptions "$job_id"
                exit 1
                ;;
            "CREATED"|"RESTARTING")
                log_info "Job status: $status (waiting...)"
                ;;
            *)
                log_warning "Unknown job status: $status"
                ;;
        esac
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    log_error "Timeout waiting for job to start"
    exit 1
}

# Show job exceptions for debugging
show_job_exceptions() {
    local job_id=$1
    log_info "Fetching job exceptions..."
    
    local exceptions=$(curl -s "$FLINK_REST_URL/jobs/$job_id/exceptions")
    echo "$exceptions" | head -20
}

# Start monitoring
start_monitoring() {
    log_info "Starting job monitoring..."
    
    # Create monitoring script
    cat > monitoring/monitor_job.sh << 'EOF'
#!/bin/bash

FLINK_REST_URL="http://localhost:8081"
JOB_NAME="nessie-cdc-lakehouse"
CHECK_INTERVAL=30

while true; do
    # Get job status
    jobs=$(curl -s "$FLINK_REST_URL/jobs")
    
    if echo "$jobs" | grep -q "RUNNING"; then
        echo "$(date): Job is running normally"
    else
        echo "$(date): WARNING - No running jobs found!"
        # Could trigger restart here
    fi
    
    sleep $CHECK_INTERVAL
done
EOF
    
    chmod +x monitoring/monitor_job.sh
    
    # Start monitoring in background
    nohup monitoring/monitor_job.sh > monitoring/monitor.log 2>&1 &
    echo $! > monitoring/monitor.pid
    
    log_success "Monitoring started (PID: $(cat monitoring/monitor.pid))"
}

# Health check
perform_health_check() {
    log_info "Performing health check..."
    
    # Check Flink cluster health
    local cluster_status=$(curl -s "$FLINK_REST_URL/overview")
    local running_jobs=$(echo "$cluster_status" | grep -o '"jobs-running":[0-9]*' | cut -d':' -f2)
    
    if [[ "$running_jobs" -gt 0 ]]; then
        log_success "Health check passed - $running_jobs job(s) running"
    else
        log_warning "Health check warning - No jobs running"
    fi
    
    # Check data flow (could add more sophisticated checks)
    log_info "Checking data flow..."
    
    # Insert test data to verify pipeline
    docker exec -i postgres psql -U admin -d demographics -c \
        "INSERT INTO demographics (city, state, median_age, male_population, female_population, total_population, number_of_veterans, foreign_born, average_household_size, state_code, race, count) VALUES ('HealthCheck', 'Test', 25.0, 100, 100, 200, 10, 5, 2.0, 'HC', 'Test', 200);" || true
    
    log_info "Test data inserted for health check"
}

# Main deployment function
main() {
    log_info "Starting deployment of $PROJECT_NAME v$APP_VERSION"
    
    # Check prerequisites
    check_prerequisites
    
    # Build application
    build_application
    
    # Deploy to Flink
    deploy_to_flink
    
    # Start monitoring
    start_monitoring
    
    # Perform health check
    sleep 10  # Wait a bit for job to stabilize
    perform_health_check
    
    log_success "Deployment completed successfully!"
    log_info "Job monitoring is running in background"
    log_info "Check logs: monitoring/monitor.log"
    log_info "Stop monitoring: kill \$(cat monitoring/monitor.pid)"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi