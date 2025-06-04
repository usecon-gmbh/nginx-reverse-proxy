#!/bin/bash

# Siege load test for image generation
# Fetches image URLs from JSON endpoint and performs realistic load testing

set -e

# Configuration
JSON_URL="https://wko-architektur-main-jdotwb.larave    l.cloud/storage/image_test_page.json"
SIEGE_URLS_FILE="siege_urls.txt"
RESULTS_DIR="siege_results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_FILE="${RESULTS_DIR}/siege_${TIMESTAMP}.log"

# Siege configuration
# Realistic parameters for image CDN testing:
# - 50 concurrent users (simulating moderate traffic)
# - 2 minute test duration
# - No delay between requests (stress test)
# - 3 second timeout for image generation
CONCURRENT_USERS=50
TEST_DURATION="2M"
TIMEOUT="3s"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Siege Image Load Test${NC}"
echo "=============================="

# Create results directory if it doesn't exist
mkdir -p "$RESULTS_DIR"

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
curl -s "$JSON_URL" > temp_images.json

if [ ! -s temp_images.json ]; then
    echo -e "${RED}Error: Failed to fetch JSON data${NC}"
    exit 1
fi

# Extract image URLs and create siege URLs file
echo -e "${YELLOW}Processing image URLs...${NC}"

# Clear previous URLs file
> "$SIEGE_URLS_FILE"

# Extract images and generate CDN URLs
# Assuming the JSON structure contains image URLs that need to be transformed to CDN format
jq -r '.images[]' temp_images.json 2>/dev/null | while read -r image_url; do
    # Extract just the path/filename from the URL
    image_path=$(echo "$image_url" | sed 's|.*storage/||')
    
    # Generate CDN URLs with different sizes and formats
    # Using the flexible gravity and format parameters
    
    # Test different image sizes (from nginx config)
    sizes=("312:176:1" "458:258:1" "592:334:1" "624:352:1" "702:396:1")
    gravities=("sm" "ce" "no" "so" "ea" "we")
    formats=("webp" "jpg" "png")
    
    # Generate a mix of different parameters for realistic testing
    for size in "${sizes[@]}"; do
        # Randomly select gravity and format
        gravity=${gravities[$RANDOM % ${#gravities[@]}]}
        format=${formats[$RANDOM % ${#formats[@]}]}
        
        echo "http://localhost:8080/uzgdblnadf/rs:fill:${size}/gravity:${gravity}/format:${format}/plain/${image_path}" >> "$SIEGE_URLS_FILE"
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

# Configure siege
echo -e "${YELLOW}Configuring siege...${NC}"
cat > .siegerc << EOF
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
siege -f "$SIEGE_URLS_FILE" -c "$CONCURRENT_USERS" -t "$TEST_DURATION" -i 2>&1 | tee "$RESULT_FILE"

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
rm -f temp_images.json .siegerc

echo ""
echo "Full results saved to: $RESULT_FILE"
echo "URL list saved to: $SIEGE_URLS_FILE"

# Provide recommendations based on results
echo ""
echo -e "${YELLOW}Performance Tips:${NC}"
echo "- If response times > 1s, consider increasing cache time or server resources"
echo "- If availability < 99%, check server logs for errors"
echo "- Monitor nginx cache hit ratio with: tail -f logs/access.log | grep 'cs='"