#!/bin/bash

# Siege load test for image generation
# Fetches image URLs from JSON endpoint and performs realistic load testing
# Usage: ./siege_image_test.sh [base_url] [concurrent_users] [duration]
# Example: ./siege_image_test.sh http://localhost:8081 50 2M
# Example: ./siege_image_test.sh https://cdn.example.com 200 5M

set -e

# Configuration
BASE_URL="${1:-http://localhost:8081}"  # Default to localhost:8081 (nginx proxy port)
CONCURRENT_USERS="${2:-50}"  # Default concurrent users
TEST_DURATION="${3:-2M}"     # Default test duration
JSON_URL="https://wko-architektur-main-jdotwb.laravel.cloud/storage/image_test_page.json"
SIEGE_URLS_FILE="tmp/siege_urls.txt"
RESULTS_DIR="reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_FILE="${RESULTS_DIR}/siege_${TIMESTAMP}.log"

echo "Using base URL: $BASE_URL"

# Siege configuration
TIMEOUT="3s"  # Timeout for image generation

# Provide recommendations based on environment
echo -e "${YELLOW}Concurrency Recommendations:${NC}"
echo "- Local testing: 50-100 concurrent users"
echo "- Staging: 100-200 concurrent users"
echo "- Production: 200-500 concurrent users (start low, increase gradually)"
echo "- Stress test: 500-1000 concurrent users"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Siege Image Load Test${NC}"
echo "=============================="
echo "Usage: $0 [base_url] [concurrent_users] [duration]"
echo ""
echo "Current configuration:"
echo "  Base URL: $BASE_URL"
echo "  Concurrent users: $CONCURRENT_USERS"
echo "  Test duration: $TEST_DURATION"
echo ""

# Create directories if they don't exist
mkdir -p "$RESULTS_DIR" tmp

# Check if required tools are installed
if ! command -v curl &> /dev/null; then
    echo -e "${RED}Error: curl is not installed${NC}"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed${NC}"
    exit 1
fi

if ! command -v siege &> /dev/null; then
    echo -e "${RED}Error: siege is not installed${NC}"
    echo "Install with: brew install siege (macOS) or apt-get install siege (Linux)"
    exit 1
fi

# Fetch JSON data
echo -e "${YELLOW}Fetching image URLs from: $JSON_URL${NC}"
curl -sSL --fail "$JSON_URL" -o tmp/temp_images.json 2>tmp/curl_error.log

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to fetch JSON data${NC}"
    echo "Curl error output:"
    cat tmp/curl_error.log
    rm -f tmp/curl_error.log
    exit 1
fi

if [ ! -s tmp/temp_images.json ]; then
    echo -e "${RED}Error: JSON file is empty${NC}"
    exit 1
fi

# Debug: Show first few lines of JSON
echo "JSON content preview:"
head -n 5 tmp/temp_images.json

# Extract image URLs and create siege URLs file
echo -e "${YELLOW}Processing image URLs...${NC}"

# Clear previous URLs file
> "$SIEGE_URLS_FILE"

# Extract images and generate CDN URLs
echo "Parsing JSON array..."

# The JSON is a simple array of CDN URLs
image_count=$(jq -r '. | length' tmp/temp_images.json 2>/dev/null)
echo "Found $image_count image URLs"

# Process each URL
jq -r '.[]' tmp/temp_images.json | while read -r cdn_url; do
    # Extract the original image URL from the CDN URL
    # Pattern: https://cdn.qss.wko.at/uzgdblnadf/rs:fill:XXX:YYY:1/gravity:XX/format:XXXX/plain/ORIGINAL_URL
    original_url=$(echo "$cdn_url" | sed 's|.*/plain/||')
    
    # Unescape the URL (convert \/ to /)
    original_url=$(echo "$original_url" | sed 's|\\\/|/|g')
    
    # Use a smaller set of variations to increase cache hits
    # For production testing, we want to test cache performance
    sizes=("592:334:1" "624:352:1")  # Just 2 common sizes
    gravities=("sm" "ce")  # Just 2 gravity options
    formats=("webp")  # Just webp for consistency
    
    # Generate URLs with repetition for cache testing
    for size in "${sizes[@]}"; do
        for gravity in "${gravities[@]}"; do
            for format in "${formats[@]}"; do
                # Add each URL multiple times to ensure cache hits
                for repeat in {1..5}; do
                    echo "${BASE_URL}/uzgdblnadf/rs:fill:${size}/gravity:${gravity}/format:${format}/plain/${original_url}" >> "$SIEGE_URLS_FILE"
                done
            done
        done
    done
done

# Check if we have URLs to test
url_count=$(wc -l < "$SIEGE_URLS_FILE")
if [ "$url_count" -eq 0 ]; then
    echo -e "${RED}Error: No URLs generated for testing${NC}"
    rm -f temp_images.json
    exit 1
fi

echo -e "${GREEN}Generated $url_count test URLs${NC}"
echo "Sample URLs:"
head -n 3 "$SIEGE_URLS_FILE"
echo "..."

# Warm up cache if requested
echo -e "${YELLOW}Cache Warm-up Phase${NC}"
echo "Running initial requests to populate cache..."

# Use curl to warm up cache with unique URLs
# Only need one request since proxy_cache_min_uses=1
echo "Note: nginx caches after 1 request (proxy_cache_min_uses=1)"
sort -u "$SIEGE_URLS_FILE" | head -50 | while read -r url; do
    # Single request to populate cache
    curl -s -o /dev/null "$url" &
    # Limit parallel warm-up requests
    if [[ $(jobs -r -p | wc -l) -ge 10 ]]; then
        wait
    fi
done
wait

echo "Cache warm-up complete. Waiting 2 seconds..."
sleep 2

# Configure siege
echo -e "${YELLOW}Configuring siege...${NC}"
cat > tmp/.siegerc << EOF
verbose = false
quiet = false
show-logfile = true
logging = true
protocol = HTTP/1.1
chunked = true
cache = false
connection = keep-alive
concurrent = $CONCURRENT_USERS
time = $TEST_DURATION
timeout = $TIMEOUT
benchmark = false
spinner = true
EOF

# Run siege test
echo -e "${GREEN}Starting siege test with:${NC}"
echo "  - Concurrent users: $CONCURRENT_USERS"
echo "  - Duration: $TEST_DURATION"
echo "  - Timeout: $TIMEOUT"
echo "  - Total URLs: $url_count"
echo ""
echo -e "${YELLOW}Running siege...${NC}"

# Run siege and capture output
SIEGERC=tmp/.siegerc siege -f "$SIEGE_URLS_FILE" -c "$CONCURRENT_USERS" -t "$TEST_DURATION" -i 2>&1 | tee "$RESULT_FILE"

# Parse and display results
echo ""
echo -e "${GREEN}Test Complete!${NC}"
echo "=============================="

# Extract key metrics from siege output
if grep -q "Transactions:" "$RESULT_FILE"; then
    echo -e "${GREEN}Key Metrics:${NC}"
    grep -E "(Transactions:|Availability:|Elapsed time:|Data transferred:|Response time:|Transaction rate:|Throughput:|Concurrency:|Successful transactions:|Failed transactions:)" "$RESULT_FILE"
fi

# Calculate average response time for image generation
echo ""
echo -e "${GREEN}Performance Summary:${NC}"
avg_response=$(grep "Response time:" "$RESULT_FILE" | awk '{print $3}')
if [ ! -z "$avg_response" ]; then
    echo "Average image generation time: ${avg_response} seconds"
fi

# Check for failures
failed=$(grep "Failed transactions:" "$RESULT_FILE" | awk '{print $3}')
if [ "$failed" != "0" ] && [ ! -z "$failed" ]; then
    echo -e "${RED}Warning: $failed failed transactions detected${NC}"
fi

# Cleanup
rm -f tmp/temp_images.json tmp/.siegerc tmp/curl_error.log

echo ""
echo "Full results saved to: $RESULT_FILE"
echo "URL list saved to: $SIEGE_URLS_FILE"

# Generate HTML report
echo ""
echo -e "${GREEN}Generating HTML report...${NC}"
if [ -x ./tools/generate_report.sh ]; then
    ./tools/generate_report.sh "$RESULT_FILE"
else
    echo -e "${YELLOW}Run ./tools/generate_report.sh to create an HTML report${NC}"
fi

# Provide recommendations based on results
echo ""
echo -e "${YELLOW}Performance Tips:${NC}"
echo "- If response times > 1s, consider increasing cache time or server resources"
echo "- If availability < 99%, check server logs for errors"
echo "- Monitor nginx cache hit ratio with: tail -f data/logs/access.log | grep 'cs='"