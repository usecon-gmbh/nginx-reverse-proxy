#!/bin/bash

# Cache performance test script
# Tests cache hit rates by repeatedly requesting the same images

set -e

# Configuration
BASE_URL="${1:-http://localhost:8081}"
TEST_DURATION="${2:-30s}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Cache Performance Test${NC}"
echo "======================"
echo "Base URL: $BASE_URL"
echo "Duration: $TEST_DURATION"
echo ""

# Clear nginx access log markers
echo "--- CACHE TEST START $(date) ---" >> data/logs/access.log

# Define a small set of test URLs
TEST_URLS=(
    "${BASE_URL}/uzgdblnadf/rs:fill:592:334:1/gravity:sm/format:webp/plain/https://www.wko.at/oe/abfertigung/buchhaltung-adobestock-andrey-popov-514536368.jpeg"
    "${BASE_URL}/uzgdblnadf/rs:fill:624:352:1/gravity:ce/format:webp/plain/https://www.wko.at/oe/foerderungen/pedikuere-adobestock-tomasz-papuga-50106145.jpeg"
    "${BASE_URL}/uzgdblnadf/rs:fill:592:334:1/gravity:sm/format:webp/plain/https://www.wko.at/oe/lehre/personen-fitnesstudio-training-adobestock-vadim-296640-1.jpeg"
)

# Step 1: Prime the cache (first request will be MISS)
echo -e "${YELLOW}Step 1: Priming cache...${NC}"
for url in "${TEST_URLS[@]}"; do
    echo -n "Priming: $(echo $url | grep -oE 'rs:fill:[^/]+' | head -1)... "
    response_time=$(curl -s -o /dev/null -w "%{time_total}" "$url")
    echo "done (${response_time}s)"
done

echo ""
sleep 2

# Step 2: Test cache hits with concurrent requests
echo -e "${YELLOW}Step 2: Testing cache performance...${NC}"

# Create a temporary URLs file with repeated requests
CACHE_TEST_URLS="tmp/cache_test_urls.txt"
mkdir -p tmp
> "$CACHE_TEST_URLS"

# Each URL repeated 100 times
for url in "${TEST_URLS[@]}"; do
    for i in {1..100}; do
        echo "$url" >> "$CACHE_TEST_URLS"
    done
done

# Shuffle URLs for more realistic pattern
if command -v shuf &> /dev/null; then
    shuf "$CACHE_TEST_URLS" -o "$CACHE_TEST_URLS"
elif command -v gshuf &> /dev/null; then
    gshuf "$CACHE_TEST_URLS" -o "$CACHE_TEST_URLS"
fi

# Run siege with high concurrency on cached URLs
echo "Running siege on cached URLs..."
siege -f "$CACHE_TEST_URLS" -c 50 -t "$TEST_DURATION" -i --quiet 2>&1 | tee tmp/cache_test_result.log

# Step 3: Analyze results
echo ""
echo -e "${GREEN}Cache Performance Analysis${NC}"
echo "=========================="

# Extract cache statistics from access log
MARKER_LINE=$(grep -n "CACHE TEST START" data/logs/access.log | tail -1 | cut -d: -f1)
if [ ! -z "$MARKER_LINE" ]; then
    tail -n +$MARKER_LINE data/logs/access.log > tmp/temp_cache_log.txt
    
    CACHE_HITS=$(grep -c "cs=HIT" tmp/temp_cache_log.txt 2>/dev/null || echo "0")
    CACHE_MISSES=$(grep -c "cs=MISS" tmp/temp_cache_log.txt 2>/dev/null || echo "0")
    CACHE_EXPIRED=$(grep -c "cs=EXPIRED" tmp/temp_cache_log.txt 2>/dev/null || echo "0")
    CACHE_UPDATING=$(grep -c "cs=UPDATING" tmp/temp_cache_log.txt 2>/dev/null || echo "0")
    
    # Ensure we have clean integers
    CACHE_HITS=${CACHE_HITS//[^0-9]/}
    CACHE_MISSES=${CACHE_MISSES//[^0-9]/}
    CACHE_EXPIRED=${CACHE_EXPIRED//[^0-9]/}
    CACHE_UPDATING=${CACHE_UPDATING//[^0-9]/}
    
    # Default to 0 if empty
    CACHE_HITS=${CACHE_HITS:-0}
    CACHE_MISSES=${CACHE_MISSES:-0}
    CACHE_EXPIRED=${CACHE_EXPIRED:-0}
    CACHE_UPDATING=${CACHE_UPDATING:-0}
    
    TOTAL_REQUESTS=$((CACHE_HITS + CACHE_MISSES + CACHE_EXPIRED + CACHE_UPDATING))
    
    if [ $TOTAL_REQUESTS -gt 0 ]; then
        # Use awk instead of bc to avoid syntax errors
        CACHE_HIT_RATE=$(awk -v hits="$CACHE_HITS" -v total="$TOTAL_REQUESTS" 'BEGIN {printf "%.2f", hits * 100 / total}')
        
        echo "Total Requests: $TOTAL_REQUESTS"
        echo "Cache Hits: $CACHE_HITS"
        echo "Cache Misses: $CACHE_MISSES"
        echo "Cache Hit Rate: ${CACHE_HIT_RATE}%"
        echo ""
        
        # Response time analysis
        echo "Response Time Analysis:"
        echo "----------------------"
        
        # Average response time for HITs
        HIT_AVG=$(grep "cs=HIT" tmp/temp_cache_log.txt | awk -F'urt=' '{print $2}' | awk '{sum+=$1; count++} END {if(count>0) printf "%.3f", sum/count; else print "0"}')
        echo "Average response time (HIT): ${HIT_AVG}s"
        
        # Average response time for MISSes
        MISS_AVG=$(grep "cs=MISS" tmp/temp_cache_log.txt | awk -F'urt=' '{print $2}' | awk '{sum+=$1; count++} END {if(count>0) printf "%.3f", sum/count; else print "0"}')
        echo "Average response time (MISS): ${MISS_AVG}s"
        
        # Speed improvement
        if [ "$MISS_AVG" != "0" ] && [ "$HIT_AVG" != "0" ]; then
            SPEEDUP=$(awk -v miss="$MISS_AVG" -v hit="$HIT_AVG" 'BEGIN {printf "%.2f", miss / hit}')
            echo ""
            echo -e "${GREEN}Cache provides ${SPEEDUP}x speedup!${NC}"
        fi
    else
        echo -e "${RED}No cache data found in logs${NC}"
    fi
    
    rm -f tmp/temp_cache_log.txt
fi

# Cleanup
rm -f "$CACHE_TEST_URLS"

echo ""
echo "Full siege results saved to: tmp/cache_test_result.log"
echo ""
echo -e "${YELLOW}Tips for better cache performance:${NC}"
echo "- Ensure nginx cache is properly configured"
echo "- Check proxy_cache_min_uses setting (currently set to 1)"
echo "- Verify cache directory has sufficient space"
echo "- Monitor: tail -f data/logs/access.log | grep --color 'cs='"