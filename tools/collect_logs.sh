#!/bin/bash

# Collect nginx logs from production environments
# Usage: ./collect_logs.sh [method] [source] [duration]
# Methods: docker, ssh, k8s, local
# Examples:
#   ./collect_logs.sh docker nginx-container 5m
#   ./collect_logs.sh ssh user@prod-server 10m
#   ./collect_logs.sh k8s nginx-pod-name 5m
#   ./collect_logs.sh local /var/log/nginx 5m

set -e

# Configuration
METHOD="${1:-docker}"
SOURCE="${2:-nginx}"
DURATION="${3:-5m}"
OUTPUT_DIR="collected_logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Nginx Log Collection Tool${NC}"
echo "================================"
echo "Method: $METHOD"
echo "Source: $SOURCE"
echo "Duration: $DURATION"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

collect_docker_logs() {
    local container=$1
    local duration=$2
    
    echo -e "${YELLOW}Collecting logs from Docker container: $container${NC}"
    
    # Check if container exists
    if ! docker ps -a --format "table {{.Names}}" | grep -q "^$container$"; then
        echo -e "${RED}Error: Container '$container' not found${NC}"
        echo "Available containers:"
        docker ps --format "table {{.Names}}\t{{.Status}}"
        exit 1
    fi
    
    # Copy access log
    if docker exec "$container" test -f /var/log/nginx/access.log; then
        echo "Copying access.log..."
        docker cp "$container:/var/log/nginx/access.log" "$OUTPUT_DIR/access_${TIMESTAMP}.log"
    else
        echo "Trying alternative access log path..."
        docker exec "$container" find /var/log -name "*access*" -type f 2>/dev/null | head -1 | while read logfile; do
            if [ -n "$logfile" ]; then
                docker cp "$container:$logfile" "$OUTPUT_DIR/access_${TIMESTAMP}.log"
            fi
        done
    fi
    
    # Copy error log
    if docker exec "$container" test -f /var/log/nginx/error.log; then
        echo "Copying error.log..."
        docker cp "$container:/var/log/nginx/error.log" "$OUTPUT_DIR/error_${TIMESTAMP}.log"
    fi
    
    # Get recent logs via docker logs command
    echo "Collecting container logs for the last $duration..."
    docker logs --since="$duration" "$container" > "$OUTPUT_DIR/container_${TIMESTAMP}.log" 2>&1 || true
}

collect_ssh_logs() {
    local ssh_target=$1
    local duration=$2
    
    echo -e "${YELLOW}Collecting logs via SSH from: $ssh_target${NC}"
    
    # Test SSH connection
    if ! ssh -o ConnectTimeout=10 "$ssh_target" "echo 'SSH connection successful'"; then
        echo -e "${RED}Error: Could not connect to $ssh_target${NC}"
        exit 1
    fi
    
    # Find nginx log files
    echo "Finding nginx log files..."
    ssh "$ssh_target" "find /var/log -name '*access*' -o -name '*error*' | grep nginx" > tmp/nginx_log_paths.txt 2>/dev/null || true
    
    # Copy access logs
    if ssh "$ssh_target" "test -f /var/log/nginx/access.log"; then
        echo "Copying access.log..."
        scp "$ssh_target:/var/log/nginx/access.log" "$OUTPUT_DIR/access_${TIMESTAMP}.log"
    elif [ -s tmp/nginx_log_paths.txt ]; then
        echo "Copying found log files..."
        while read -r logpath; do
            if [[ "$logpath" == *access* ]]; then
                scp "$ssh_target:$logpath" "$OUTPUT_DIR/access_${TIMESTAMP}.log"
            elif [[ "$logpath" == *error* ]]; then
                scp "$ssh_target:$logpath" "$OUTPUT_DIR/error_${TIMESTAMP}.log"
            fi
        done < tmp/nginx_log_paths.txt
    fi
    
    # Get recent entries using journalctl if available
    echo "Collecting recent nginx entries..."
    ssh "$ssh_target" "journalctl -u nginx --since='$duration ago' --no-pager" > "$OUTPUT_DIR/journalctl_${TIMESTAMP}.log" 2>/dev/null || true
}

collect_k8s_logs() {
    local pod_name=$1
    local duration=$2
    
    echo -e "${YELLOW}Collecting logs from Kubernetes pod: $pod_name${NC}"
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}Error: kubectl is not installed${NC}"
        exit 1
    fi
    
    # Check if pod exists
    if ! kubectl get pod "$pod_name" &> /dev/null; then
        echo -e "${RED}Error: Pod '$pod_name' not found${NC}"
        echo "Available pods:"
        kubectl get pods | grep nginx || echo "No nginx pods found"
        exit 1
    fi
    
    # Get pod logs
    echo "Collecting pod logs..."
    kubectl logs "$pod_name" --since="$duration" > "$OUTPUT_DIR/k8s_${TIMESTAMP}.log" 2>&1 || true
    
    # Copy log files from pod if accessible
    echo "Attempting to copy log files from pod..."
    kubectl exec "$pod_name" -- find /var/log -name "*access*" -o -name "*error*" 2>/dev/null | while read -r logfile; do
        filename=$(basename "$logfile")
        kubectl cp "$pod_name:$logfile" "$OUTPUT_DIR/${filename}_${TIMESTAMP}.log" 2>/dev/null || true
    done
}

collect_local_logs() {
    local log_dir=$1
    local duration=$2
    
    echo -e "${YELLOW}Collecting logs from local directory: $log_dir${NC}"
    
    if [ ! -d "$log_dir" ]; then
        echo -e "${RED}Error: Directory '$log_dir' not found${NC}"
        exit 1
    fi
    
    # Copy access log
    if [ -f "$log_dir/access.log" ]; then
        echo "Copying access.log..."
        cp "$log_dir/access.log" "$OUTPUT_DIR/access_${TIMESTAMP}.log"
    fi
    
    # Copy error log
    if [ -f "$log_dir/error.log" ]; then
        echo "Copying error.log..."
        cp "$log_dir/error.log" "$OUTPUT_DIR/error_${TIMESTAMP}.log"
    fi
    
    # Find and copy other nginx logs
    find "$log_dir" -name "*nginx*" -name "*.log" -type f | while read -r logfile; do
        filename=$(basename "$logfile")
        cp "$logfile" "$OUTPUT_DIR/${filename}_${TIMESTAMP}.log"
    done
}

# Main execution
case $METHOD in
    docker)
        collect_docker_logs "$SOURCE" "$DURATION"
        ;;
    ssh)
        collect_ssh_logs "$SOURCE" "$DURATION"
        ;;
    k8s|kubernetes)
        collect_k8s_logs "$SOURCE" "$DURATION"
        ;;
    local)
        collect_local_logs "$SOURCE" "$DURATION"
        ;;
    *)
        echo -e "${RED}Error: Unknown method '$METHOD'${NC}"
        echo "Supported methods: docker, ssh, k8s, local"
        exit 1
        ;;
esac

# Summary
echo ""
echo -e "${GREEN}Log collection complete!${NC}"
echo "Collected files:"
ls -la "$OUTPUT_DIR/"*"$TIMESTAMP"* 2>/dev/null || echo "No files collected"

echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Copy collected logs to data/logs/ directory"
echo "2. Run: cp $OUTPUT_DIR/*_${TIMESTAMP}.log data/logs/"
echo "3. Generate report: ./tools/generate_report.sh"

# Clean up
rm -f tmp/nginx_log_paths.txt 2>/dev/null || true