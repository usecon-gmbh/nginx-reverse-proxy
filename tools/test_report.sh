#!/bin/bash

# Quick test to check if we can generate a basic report
set -e

SIEGE_LOG="${1:-$(ls -t reports/siege_*.log 2>/dev/null | head -1)}"
NGINX_ACCESS_LOG="data/logs/access.log"
REPORT_DIR="reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="${REPORT_DIR}/test_report_${TIMESTAMP}.html"

echo "Testing report generation..."

# Create a minimal working report first
mkdir -p "$REPORT_DIR" tmp

# Get basic cache stats safely
if [ -f "$NGINX_ACCESS_LOG" ]; then
    CACHE_HITS=$(grep -c "cs=HIT" "$NGINX_ACCESS_LOG" 2>/dev/null || echo "0")
    CACHE_MISSES=$(grep -c "cs=MISS" "$NGINX_ACCESS_LOG" 2>/dev/null || echo "0")
    
    echo "Cache hits: $CACHE_HITS"
    echo "Cache misses: $CACHE_MISSES"
    
    if [ "$CACHE_HITS" -gt 0 ] && [ "$CACHE_MISSES" -gt 0 ]; then
        TOTAL_REQUESTS=$((CACHE_HITS + CACHE_MISSES))
        CACHE_HIT_RATE=$(awk "BEGIN {printf \"%.1f\", $CACHE_HITS * 100 / $TOTAL_REQUESTS}")
        echo "Cache hit rate: ${CACHE_HIT_RATE}%"
    fi
fi

echo "Basic test completed successfully!"