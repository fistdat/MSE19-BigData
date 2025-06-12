#!/bin/bash

# =============================================================================
# Nessie CDC Lakehouse - Master Control Script
# =============================================================================
# Production-ready control center for the entire CDC pipeline
# =============================================================================

set -euo pipefail

# Configuration
PROJECT_NAME="Nessie CDC Lakehouse"
VERSION="1.0.0"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Script paths
DEPLOYMENT_SCRIPT="$BASE_DIR/deployment/build-and-deploy.sh"
HEALTH_CHECK_SCRIPT="$BASE_DIR/monitoring/health-check.sh"
AUTO_RESTART_SCRIPT="$BASE_DIR/scripts/auto-restart.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

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

log_header() {
    echo -e "${CYAN}${BOLD}$1${NC}"
}

# Show banner
show_banner() {
    echo -e "${CYAN}${BOLD}"
    echo "=============================================="
    echo "    $PROJECT_NAME v$VERSION"
    echo "=============================================="
    echo "Production-ready CDC Pipeline Control Center"
    echo -e "${NC}"
}

# Show status dashboard
show_status() {
    log_header "=== SYSTEM STATUS DASHBOARD ==="
    
    # Check Flink cluster
    if curl -s http://localhost:8081/overview > /dev/null 2>&1; then
        local overview=$(curl -s http://localhost:8081/overview)
        local running_jobs=$(echo "$overview" | grep -o '"jobs-running":[0-9]*' | cut -d':' -f2)
        local taskmanagers=$(echo "$overview" | grep -o '"taskmanagers":[0-9]*' | cut -d':' -f2)
        
        echo -e "🟢 Flink Cluster: ${GREEN}ONLINE${NC} ($running_jobs jobs, $taskmanagers taskmanagers)"
    else
        echo -e "🔴 Flink Cluster: ${RED}OFFLINE${NC}"
    fi
    
    # Check Docker containers
    local containers=("postgres" "kafka" "nessie" "minioserver" "jobmanager" "taskmanager" "debezium")
    for container in "${containers[@]}"; do
        if docker ps --format "table {{.Names}}" | grep -q "$container"; then
            echo -e "🟢 $container: ${GREEN}RUNNING${NC}"
        else
            echo -e "🔴 $container: ${RED}STOPPED${NC}"
        fi
    done
    
    # Check CDC job specifically
    if curl -s http://localhost:8081/jobs 2>/dev/null | grep -q "nessie-cdc-lakehouse"; then
        echo -e "🟢 CDC Job: ${GREEN}RUNNING${NC}"
    else
        echo -e "🔴 CDC Job: ${RED}NOT RUNNING${NC}"
    fi
    
    echo ""
}

# Deploy the application
deploy() {
    log_header "=== DEPLOYING APPLICATION ==="
    
    if [[ -f "$DEPLOYMENT_SCRIPT" ]]; then
        bash "$DEPLOYMENT_SCRIPT"
    else
        log_error "Deployment script not found: $DEPLOYMENT_SCRIPT"
        exit 1
    fi
}

# Run health check
health_check() {
    log_header "=== RUNNING HEALTH CHECK ==="
    
    if [[ -f "$HEALTH_CHECK_SCRIPT" ]]; then
        bash "$HEALTH_CHECK_SCRIPT"
    else
        log_error "Health check script not found: $HEALTH_CHECK_SCRIPT"
        exit 1
    fi
}

# Start monitoring
start_monitoring() {
    log_header "=== STARTING MONITORING ==="
    
    if [[ -f "$AUTO_RESTART_SCRIPT" ]]; then
        log_info "Starting continuous monitoring in background..."
        nohup bash "$AUTO_RESTART_SCRIPT" --monitor > monitoring/auto-restart.log 2>&1 &
        echo $! > monitoring/auto-restart.pid
        log_success "Monitoring started (PID: $(cat monitoring/auto-restart.pid))"
        log_info "Monitor logs: monitoring/auto-restart.log"
    else
        log_error "Auto-restart script not found: $AUTO_RESTART_SCRIPT"
        exit 1
    fi
}

# Stop monitoring
stop_monitoring() {
    log_header "=== STOPPING MONITORING ==="
    
    if [[ -f "monitoring/auto-restart.pid" ]]; then
        local pid=$(cat monitoring/auto-restart.pid)
        if kill "$pid" 2>/dev/null; then
            log_success "Monitoring stopped (PID: $pid)"
        else
            log_warning "Could not stop monitoring process (PID: $pid)"
        fi
        rm -f monitoring/auto-restart.pid
    else
        log_warning "No monitoring process found"
    fi
}

# Restart the pipeline
restart() {
    log_header "=== RESTARTING PIPELINE ==="
    
    if [[ -f "$AUTO_RESTART_SCRIPT" ]]; then
        bash "$AUTO_RESTART_SCRIPT" --restart
    else
        log_error "Auto-restart script not found: $AUTO_RESTART_SCRIPT"
        exit 1
    fi
}

# Stop all jobs
stop() {
    log_header "=== STOPPING ALL JOBS ==="
    
    # Stop monitoring first
    stop_monitoring
    
    # Cancel Flink jobs
    local jobs=$(curl -s http://localhost:8081/jobs 2>/dev/null || echo '{"jobs":[]}')
    if echo "$jobs" | grep -q "nessie-cdc-lakehouse"; then
        local job_ids=$(echo "$jobs" | grep -A5 -B5 "nessie-cdc-lakehouse" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
        
        for job_id in $job_ids; do
            log_info "Canceling job: $job_id"
            curl -s -X POST "http://localhost:8081/jobs/$job_id/cancel" > /dev/null || true
        done
        
        log_success "All CDC jobs stopped"
    else
        log_info "No CDC jobs found to stop"
    fi
}

# Show logs
show_logs() {
    local log_type=${1:-"all"}
    
    log_header "=== SHOWING LOGS ==="
    
    case $log_type in
        "flink")
            log_info "Flink JobManager logs:"
            docker logs jobmanager --tail 50
            ;;
        "monitoring")
            if [[ -f "monitoring/auto-restart.log" ]]; then
                log_info "Monitoring logs:"
                tail -50 monitoring/auto-restart.log
            else
                log_warning "No monitoring logs found"
            fi
            ;;
        "health")
            log_info "Running health check..."
            health_check
            ;;
        "all"|*)
            log_info "Recent Flink logs:"
            docker logs jobmanager --tail 20
            echo ""
            if [[ -f "monitoring/auto-restart.log" ]]; then
                log_info "Recent monitoring logs:"
                tail -10 monitoring/auto-restart.log
            fi
            ;;
    esac
}

# Test data flow
test_data_flow() {
    log_header "=== TESTING DATA FLOW ==="
    
    log_info "Inserting test data into PostgreSQL..."
    local test_city="TestFlow_$(date +%s)"
    
    if docker exec postgres psql -U admin -d demographics -c \
        "INSERT INTO demographics (city, state, median_age, male_population, female_population, total_population, number_of_veterans, foreign_born, average_household_size, state_code, race, count) VALUES ('$test_city', 'TestState', 25.0, 100, 100, 200, 10, 5, 2.0, 'TF', 'Test', 200);" > /dev/null 2>&1; then
        
        log_success "Test data inserted: $test_city"
        
        log_info "Waiting 10 seconds for CDC processing..."
        sleep 10
        
        log_info "Checking Kafka for test data..."
        if docker exec kafka kafka-console-consumer \
            --bootstrap-server localhost:9092 \
            --topic demographics_server.public.demographics \
            --timeout-ms 5000 \
            --from-beginning 2>/dev/null | grep -q "$test_city"; then
            log_success "Test data found in Kafka - CDC is working!"
        else
            log_warning "Test data not found in Kafka - check CDC pipeline"
        fi
    else
        log_error "Failed to insert test data"
    fi
}

# Show usage
show_usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  status          Show system status dashboard"
    echo "  deploy          Deploy the CDC application"
    echo "  health          Run comprehensive health check"
    echo "  start           Start monitoring"
    echo "  stop            Stop all jobs and monitoring"
    echo "  restart         Restart the pipeline"
    echo "  logs [type]     Show logs (flink|monitoring|health|all)"
    echo "  test            Test end-to-end data flow"
    echo "  help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 status                    # Show system status"
    echo "  $0 deploy                    # Deploy application"
    echo "  $0 start                     # Start monitoring"
    echo "  $0 logs flink               # Show Flink logs"
    echo "  $0 test                     # Test data flow"
    echo ""
}

# Main function
main() {
    show_banner
    
    local command=${1:-"status"}
    
    case $command in
        "status")
            show_status
            ;;
        "deploy")
            deploy
            ;;
        "health")
            health_check
            ;;
        "start")
            start_monitoring
            ;;
        "stop")
            stop
            ;;
        "restart")
            restart
            ;;
        "logs")
            show_logs "${2:-all}"
            ;;
        "test")
            test_data_flow
            ;;
        "help"|"--help"|"-h")
            show_usage
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi