#!/bin/bash

# Collect nginx logs via HTTP endpoint
# Usage: ./collect_logs_http.sh [base_url] [output_dir]
# Example: ./collect_logs_http.sh http://localhost:8081 collected_logs

set -e

# Configuration
BASE_URL="${1:-http://localhost:8081}"
OUTPUT_DIR="${2:-collected_logs}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}HTTP Log Collection Tool${NC}"
echo "=========================="
echo "Base URL: $BASE_URL"
echo "Output: $OUTPUT_DIR"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Test if endpoints are accessible
echo -e "${YELLOW}Testing log endpoint accessibility...${NC}"

# Test health endpoint first
if curl -s -f "$BASE_URL/health" > /dev/null; then
    echo "✓ Health endpoint accessible"
else
    echo -e "${RED}✗ Health endpoint not accessible${NC}"
    echo "Make sure nginx is running and accessible at $BASE_URL"
    exit 1
fi

# Test access log endpoint
echo "Testing access log endpoint..."
if curl -s -f "$BASE_URL/access-log" -I > /dev/null 2>&1; then
    echo "✓ Access log endpoint accessible"
    
    # Download access log
    echo "Downloading access log..."
    curl -s -f "$BASE_URL/access-log" -o "$OUTPUT_DIR/access_${TIMESTAMP}.log"
    
    # Check if file was downloaded and has content
    if [ -s "$OUTPUT_DIR/access_${TIMESTAMP}.log" ]; then
        ACCESS_SIZE=$(wc -l < "$OUTPUT_DIR/access_${TIMESTAMP}.log")
        echo "✓ Access log downloaded: $ACCESS_SIZE lines"
    else
        echo -e "${YELLOW}⚠ Access log is empty${NC}"
    fi
else
    echo -e "${RED}✗ Access log endpoint not accessible${NC}"
    echo "This could be due to:"
    echo "- IP restriction (check nginx allow/deny rules)"
    echo "- Endpoint not configured"
    echo "- Different port/URL"
fi

# Test error log endpoint
echo "Testing error log endpoint..."
if curl -s -f "$BASE_URL/error-log" -I > /dev/null 2>&1; then
    echo "✓ Error log endpoint accessible"
    
    # Download error log
    echo "Downloading error log..."
    curl -s -f "$BASE_URL/error-log" -o "$OUTPUT_DIR/error_${TIMESTAMP}.log"
    
    # Check if file was downloaded and has content
    if [ -s "$OUTPUT_DIR/error_${TIMESTAMP}.log" ]; then
        ERROR_SIZE=$(wc -l < "$OUTPUT_DIR/error_${TIMESTAMP}.log")
        echo "✓ Error log downloaded: $ERROR_SIZE lines"
    else
        echo -e "${YELLOW}⚠ Error log is empty${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Error log endpoint not accessible${NC}"
fi

echo ""
echo -e "${GREEN}Log collection complete!${NC}"

# Summary of collected files
echo "Files collected:"
ls -la "$OUTPUT_DIR/"*"$TIMESTAMP"* 2>/dev/null | while read -r line; do
    echo "  $line"
done

# Show recent entries from access log if available
if [ -s "$OUTPUT_DIR/access_${TIMESTAMP}.log" ]; then
    echo ""
    echo -e "${YELLOW}Recent access log entries (last 5):${NC}"
    tail -5 "$OUTPUT_DIR/access_${TIMESTAMP}.log" | while read -r line; do
        echo "  $line"
    done
fi

echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Copy to data/logs: cp $OUTPUT_DIR/access_${TIMESTAMP}.log data/logs/access.log"
echo "2. Run siege test: ./tools/siege_image_test.sh $BASE_URL"
echo "3. Collect post-test logs: ./tools/collect_logs_http.sh $BASE_URL"
echo "4. Generate report: ./tools/generate_report.sh"

echo ""
echo -e "${RED}Security reminder:${NC}"
echo "Don't forget to remove the log endpoints from nginx config in production!"