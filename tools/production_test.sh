#!/bin/bash

# Production load testing with HTTP log collection
# Usage: ./production_test.sh [base_url] [concurrent_users] [duration]
# Example: ./production_test.sh https://cdn.example.com 50 2M

set -e

# Configuration
BASE_URL="${1:-https://cdn.example.com}"
CONCURRENT_USERS="${2:-50}"
TEST_DURATION="${3:-2M}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Production Load Testing Suite${NC}"
echo "===================================="
echo "Target URL: $BASE_URL"
echo "Concurrent Users: $CONCURRENT_USERS" 
echo "Duration: $TEST_DURATION"
echo "Log Collection: HTTP endpoints"
echo ""

# Pre-test log collection
echo -e "${YELLOW}Step 1: Collecting pre-test logs...${NC}"
./tools/collect_logs_http.sh "$BASE_URL"

# Backup current logs
if [ -d "collected_logs" ]; then
    mkdir -p "data/logs/backup"
    cp collected_logs/*_*.log data/logs/backup/ 2>/dev/null || true
    
    # Use most recent access log for baseline
    LATEST_ACCESS_LOG=$(ls -t collected_logs/access_*.log 2>/dev/null | head -1)
    if [ -n "$LATEST_ACCESS_LOG" ]; then
        cp "$LATEST_ACCESS_LOG" data/logs/access.log
        echo "Using collected access log: $LATEST_ACCESS_LOG"
    fi
fi

echo ""
echo -e "${YELLOW}Step 2: Running load test...${NC}"

# Run the siege test
./tools/siege_image_test.sh "$BASE_URL" "$CONCURRENT_USERS" "$TEST_DURATION"

echo ""
echo -e "${YELLOW}Step 3: Collecting post-test logs...${NC}"

# Post-test log collection
sleep 5  # Wait for logs to be written
./tools/collect_logs_http.sh "$BASE_URL"

# Update logs with post-test data
if [ -d "collected_logs" ]; then
    LATEST_ACCESS_LOG=$(ls -t collected_logs/access_*.log 2>/dev/null | head -1)
    if [ -n "$LATEST_ACCESS_LOG" ]; then
        cp "$LATEST_ACCESS_LOG" data/logs/access.log
        echo "Updated with post-test access log: $LATEST_ACCESS_LOG"
    fi
fi

echo ""
echo -e "${YELLOW}Step 4: Generating comprehensive report...${NC}"

# Generate the final report
./tools/generate_report.sh

echo ""
echo -e "${GREEN}Production Test Complete!${NC}"
echo "================================"

# Summary
echo "Test Summary:"
echo "- Logs collected from: HTTP endpoints ($BASE_URL)"
echo "- Load test executed: $CONCURRENT_USERS users for $TEST_DURATION"  
echo "- Reports generated in: reports/"
echo "- Logs archived in: collected_logs/"

echo ""
echo -e "${YELLOW}Files generated:${NC}"
echo "├── reports/siege_*.log (siege test results)"
echo "├── reports/siege_report_*.html (comprehensive report)"
echo "├── collected_logs/access_*.log (nginx access logs)"
echo "├── collected_logs/error_*.log (nginx error logs)"
echo "└── data/logs/backup/ (log backups)"

echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "1. Review the HTML report for performance insights"
echo "2. Check error logs for any issues during the test"
echo "3. Compare pre/post test metrics"
echo "4. Archive test results for historical comparison"

# Open report if on macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
    LATEST_REPORT=$(ls -t reports/siege_report_*.html 2>/dev/null | head -1)
    if [ -n "$LATEST_REPORT" ]; then
        echo ""
        echo "Opening report: $LATEST_REPORT"
        open "$LATEST_REPORT"
    fi
fi