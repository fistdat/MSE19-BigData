#!/bin/bash

# =============================================================================
# Nessie CDC Lakehouse - Auto Restart Script
# =============================================================================
# Automatic restart mechanism for failed CDC pipeline components
# =============================================================================

set -euo pipefail

# Configuration
FLINK_REST_URL="http://localhost:8081"
PROJECT_NAME="nessie-cdc-lakehouse"
MAX_RESTART_ATTEMPTS=3
RESTART_DELAY=30
HEALTH_CHECK_SCRIPT="monitoring/health-check.sh"
DEPLOYMENT_SCRIPT="deployment/build-and-deploy.sh"

# State tracking
RESTART_ATTEMPTS=0
LAST_RESTART_TIME=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date): $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date): $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date): $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date): $1"
}

# Check if restart is needed
check_restart_needed() {
    log_info "Checking if restart is needed..."
    
    # Run health check
    if bash "$HEALTH_CHECK_SCRIPT" > /dev/null 2>&1; then
        log_info "Health check passed - no restart needed"
        return 1  # No restart needed
    else
        log_warning "Health check failed - restart may be needed"
        return 0  # Restart needed
    fi
}

# Check restart limits
check_restart_limits() {
    local current_time=$(date +%s)
    local time_since_last_restart=$((current_time - LAST_RESTART_TIME))
    
    # Reset counter if enough time has passed (1 hour)
    if [[ $time_since_last_restart -gt 3600 ]]; then
        RESTART_ATTEMPTS=0
        log_info "Restart attempt counter reset"
    fi
    
    if [[ $RESTART_ATTEMPTS -ge $MAX_RESTART_ATTEMPTS ]]; then
        log_error "Maximum restart attempts ($MAX_RESTART_ATTEMPTS) reached"
        send_critical_alert "Auto-restart failed" "Maximum restart attempts reached for $PROJECT_NAME"
        return 1
    fi
    
    return 0
}

# Stop existing jobs
stop_existing_jobs() {
    log_info "Stopping existing jobs..."
    
    local jobs=$(curl -s "$FLINK_REST_URL/jobs" || echo '{"jobs":[]}')
    
    # Find and cancel our jobs
    if echo "$jobs" | grep -q "$PROJECT_NAME"; then
        local job_ids=$(echo "$jobs" | grep -A5 -B5 "$PROJECT_NAME" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
        
        for job_id in $job_ids; do
            log_info "Canceling job: $job_id"
            curl -s -X POST "$FLINK_REST_URL/jobs/$job_id/cancel" > /dev/null || true
        done
        
        # Wait for jobs to stop
        sleep 10
    fi
}

# Restart the CDC pipeline
restart_pipeline() {
    log_info "Starting pipeline restart (attempt $((RESTART_ATTEMPTS + 1))/$MAX_RESTART_ATTEMPTS)..."
    
    RESTART_ATTEMPTS=$((RESTART_ATTEMPTS + 1))
    LAST_RESTART_TIME=$(date +%s)
    
    # Stop existing jobs
    stop_existing_jobs
    
    # Wait before restart
    log_info "Waiting ${RESTART_DELAY}s before restart..."
    sleep $RESTART_DELAY
    
    # Restart the pipeline
    log_info "Executing deployment script..."
    if bash "$DEPLOYMENT_SCRIPT"; then
        log_success "Pipeline restarted successfully"
        
        # Wait and verify
        sleep 30
        if bash "$HEALTH_CHECK_SCRIPT" > /dev/null 2>&1; then
            log_success "Restart verification passed"
            send_info_alert "Pipeline restarted" "$PROJECT_NAME restarted successfully after failure"
            return 0
        else
            log_error "Restart verification failed"
            return 1
        fi
    else
        log_error "Pipeline restart failed"
        return 1
    fi
}

# Send alerts
send_info_alert() {
    local title="$1"
    local message="$2"
    log_info "ALERT: $title - $message"
    
    # Here you could implement actual alerting:
    # - Webhook notifications
    # - Email alerts
    # - Slack messages
    # - PagerDuty incidents
}

send_warning_alert() {
    local title="$1"
    local message="$2"
    log_warning "ALERT: $title - $message"
}

send_critical_alert() {
    local title="$1"
    local message="$2"
    log_error "CRITICAL ALERT: $title - $message"
}

# Perform detailed diagnosis
perform_diagnosis() {
    log_info "Performing detailed diagnosis..."
    
    # Check individual components
    local issues=()
    
    # Check Flink cluster
    if ! curl -s "$FLINK_REST_URL/overview" > /dev/null; then
        issues+=("Flink cluster unreachable")
    fi
    
    # Check Docker containers
    local containers=("postgres" "kafka" "nessie" "minioserver" "jobmanager" "taskmanager")
    for container in "${containers[@]}"; do
        if ! docker ps | grep -q "$container"; then
            issues+=("Container $container not running")
        fi
    done
    
    # Report issues
    if [[ ${#issues[@]} -gt 0 ]]; then
        log_error "Diagnosis found issues:"
        for issue in "${issues[@]}"; do
            log_error "  - $issue"
        done
    else
        log_info "No obvious infrastructure issues found"
    fi
}

# Main restart logic
attempt_restart() {
    log_info "Auto-restart triggered for $PROJECT_NAME"
    
    # Check restart limits
    if ! check_restart_limits; then
        return 1
    fi
    
    # Perform diagnosis
    perform_diagnosis
    
    # Attempt restart
    if restart_pipeline; then
        log_success "Auto-restart completed successfully"
        return 0
    else
        log_error "Auto-restart failed"
        send_warning_alert "Restart failed" "Auto-restart attempt $RESTART_ATTEMPTS failed for $PROJECT_NAME"
        return 1
    fi
}

# Continuous monitoring mode
continuous_monitoring() {
    local check_interval=${1:-60}  # Default 60 seconds
    
    log_info "Starting continuous monitoring mode (interval: ${check_interval}s)"
    
    while true; do
        if check_restart_needed; then
            log_warning "Restart needed - attempting auto-restart..."
            
            if attempt_restart; then
                log_success "Auto-restart successful"
            else
                log_error "Auto-restart failed - will retry on next check"
            fi
        fi
        
        sleep $check_interval
    done
}

# Usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --check         Check if restart is needed (exit 0 if healthy, 1 if restart needed)"
    echo "  --restart       Perform one restart attempt"
    echo "  --monitor       Start continuous monitoring mode"
    echo "  --interval N    Set monitoring interval in seconds (default: 60)"
    echo "  --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --check                    # Check health status"
    echo "  $0 --restart                  # Perform one restart attempt"
    echo "  $0 --monitor                  # Start continuous monitoring"
    echo "  $0 --monitor --interval 30    # Monitor with 30s interval"
}

# Main function
main() {
    local mode="check"
    local interval=60
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --check)
                mode="check"
                shift
                ;;
            --restart)
                mode="restart"
                shift
                ;;
            --monitor)
                mode="monitor"
                shift
                ;;
            --interval)
                interval="$2"
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Execute based on mode
    case $mode in
        "check")
            if check_restart_needed; then
                log_warning "Restart is needed"
                exit 1
            else
                log_success "System is healthy"
                exit 0
            fi
            ;;
        "restart")
            if attempt_restart; then
                exit 0
            else
                exit 1
            fi
            ;;
        "monitor")
            continuous_monitoring $interval
            ;;
        *)
            log_error "Invalid mode: $mode"
            show_usage
            exit 1
            ;;
    esac
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi