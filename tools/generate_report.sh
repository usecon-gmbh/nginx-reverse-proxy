#!/bin/bash

# Generate HTML report from siege test results
# Usage: ./generate_report.sh [siege_log_file]

set -e

# Set locale to avoid number formatting issues
export LC_NUMERIC=C

# Configuration
SIEGE_LOG="${1:-$(ls -t reports/siege_*.log 2>/dev/null | head -1)}"

# Try to find the most recent nginx access log (prefer HTTP-collected logs)
if [ -f "$(ls -t collected_logs/access_*.log 2>/dev/null | head -1)" ]; then
    NGINX_ACCESS_LOG="$(ls -t collected_logs/access_*.log 2>/dev/null | head -1)"
    echo "Using HTTP-collected log: $NGINX_ACCESS_LOG"
elif [ -f "data/logs/access.log" ]; then
    NGINX_ACCESS_LOG="data/logs/access.log"
else
    NGINX_ACCESS_LOG="data/logs/access.log"  # fallback
fi

REPORT_DIR="reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="${REPORT_DIR}/siege_report_${TIMESTAMP}.html"

# Colors for terminal output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if siege log exists
if [ ! -f "$SIEGE_LOG" ]; then
    echo -e "${RED}Error: No siege log file found${NC}"
    echo "Usage: $0 [siege_log_file]"
    exit 1
fi

echo -e "${GREEN}Generating HTML report from: $SIEGE_LOG${NC}"

# Create directories
mkdir -p "$REPORT_DIR" tmp

# Extract metrics from siege log
extract_metric() {
    grep -E "$1" "$SIEGE_LOG" | tail -1 | sed -E "s/.*$1[[:space:]]*([^[:space:]]+).*/\1/"
}

# Parse siege metrics with safe defaults
TRANSACTIONS=$(extract_metric "Transactions:" || echo "0")
AVAILABILITY=$(extract_metric "Availability:" || echo "0.00%")
ELAPSED_TIME=$(extract_metric "Elapsed time:" || echo "0 secs")
DATA_TRANSFERRED=$(extract_metric "Data transferred:" || echo "0 MB")
RESPONSE_TIME=$(extract_metric "Response time:" || echo "0.00")
TRANSACTION_RATE=$(extract_metric "Transaction rate:" || echo "0.00")
THROUGHPUT=$(extract_metric "Throughput:" || echo "0.00")
CONCURRENCY=$(extract_metric "Concurrency:" || echo "0.00")
SUCCESSFUL=$(extract_metric "Successful transactions:" || echo "0")
FAILED=$(extract_metric "Failed transactions:" || echo "0")

# Clean up metrics - extract just numbers and remove whitespace
TRANSACTIONS=$(echo "$TRANSACTIONS" | tr -d '\n\r\t ' | grep -oE '[0-9]+' | head -1 || echo "0")
SUCCESSFUL=$(echo "$SUCCESSFUL" | tr -d '\n\r\t ' | grep -oE '[0-9]+' | head -1 || echo "0")
FAILED=$(echo "$FAILED" | tr -d '\n\r\t ' | grep -oE '[0-9]+' | head -1 || echo "0")
RESPONSE_TIME=$(echo "$RESPONSE_TIME" | tr -d '\n\r\t ' | grep -oE '[0-9.]+' | head -1 || echo "0.00")
TRANSACTION_RATE=$(echo "$TRANSACTION_RATE" | tr -d '\n\r\t ' | grep -oE '[0-9.]+' | head -1 || echo "0.00")
THROUGHPUT=$(echo "$THROUGHPUT" | tr -d '\n\r\t ' | grep -oE '[0-9.]+' | head -1 || echo "0.00")
CONCURRENCY=$(echo "$CONCURRENCY" | tr -d '\n\r\t ' | grep -oE '[0-9.]+' | head -1 || echo "0.00")

# Ensure all numeric values are valid
TRANSACTIONS=${TRANSACTIONS:-0}
SUCCESSFUL=${SUCCESSFUL:-0}
FAILED=${FAILED:-0}
RESPONSE_TIME=${RESPONSE_TIME:-0.00}
TRANSACTION_RATE=${TRANSACTION_RATE:-0.00}
THROUGHPUT=${THROUGHPUT:-0.00}
CONCURRENCY=${CONCURRENCY:-0.00}

# Parse cache statistics and response time data from nginx logs
if [ -f "$NGINX_ACCESS_LOG" ]; then
    # Get the test start time from siege log
    TEST_START_TIME=$(grep "Preparing.*concurrent users" "$SIEGE_LOG" | head -1 || echo "")
    
    # Get cache statistics from the last test period
    CACHE_HITS=$(grep -c "cs=HIT" "$NGINX_ACCESS_LOG" 2>/dev/null || echo "0")
    CACHE_MISSES=$(grep -c "cs=MISS" "$NGINX_ACCESS_LOG" 2>/dev/null || echo "0")
    CACHE_EXPIRED=$(grep -c "cs=EXPIRED" "$NGINX_ACCESS_LOG" 2>/dev/null || echo "0")
    CACHE_UPDATING=$(grep -c "cs=UPDATING" "$NGINX_ACCESS_LOG" 2>/dev/null || echo "0")
    CACHE_STALE=$(grep -c "cs=STALE" "$NGINX_ACCESS_LOG" 2>/dev/null || echo "0")
    
    # Ensure all variables are numeric and clean
    CACHE_HITS=$(echo "$CACHE_HITS" | tr -d '\n\r\t ' | grep -oE '[0-9]+' | head -1 || echo "0")
    CACHE_MISSES=$(echo "$CACHE_MISSES" | tr -d '\n\r\t ' | grep -oE '[0-9]+' | head -1 || echo "0")
    CACHE_EXPIRED=$(echo "$CACHE_EXPIRED" | tr -d '\n\r\t ' | grep -oE '[0-9]+' | head -1 || echo "0")
    CACHE_UPDATING=$(echo "$CACHE_UPDATING" | tr -d '\n\r\t ' | grep -oE '[0-9]+' | head -1 || echo "0")
    CACHE_STALE=$(echo "$CACHE_STALE" | tr -d '\n\r\t ' | grep -oE '[0-9]+' | head -1 || echo "0")
    
    # Calculate totals safely
    TOTAL_CACHE_REQUESTS=$(awk "BEGIN {print $CACHE_HITS + $CACHE_MISSES + $CACHE_EXPIRED + $CACHE_UPDATING + $CACHE_STALE}")
    if awk "BEGIN {exit !($TOTAL_CACHE_REQUESTS > 0)}" 2>/dev/null; then
        CACHE_HIT_RATE=$(awk "BEGIN {printf \"%.2f\", $CACHE_HITS * 100 / $TOTAL_CACHE_REQUESTS}" 2>/dev/null || echo "0")
    else
        CACHE_HIT_RATE="0"
    fi
    
    # Get response time statistics
    AVG_RESPONSE_TIME=$(awk -F'urt=' '{if(NF>1) print $2}' "$NGINX_ACCESS_LOG" | awk '{if($1+0>0) {sum+=$1; count++}} END {if(count>0) printf "%.3f", sum/count; else print "0"}' 2>/dev/null || echo "0")
    
    # Extract response time data for time series (last 50 requests spread across X-axis)
    echo "Extracting response time data for visualization..."
    
    # Get response times and create evenly spaced data points across 0-100
    RESPONSE_TIME_DATA=$(tail -30 "$NGINX_ACCESS_LOG" | grep -oE 'urt="[0-9.]+"' | sed 's/urt="//g; s/"//g' | awk 'BEGIN{count=0} {data[count]=$1; count++} END {
        if (count > 0) {
            for (i = 0; i < count; i++) {
                if (count > 1) {
                    x_value = i * 100 / (count - 1)
                } else {
                    x_value = 50
                }
                printf "{x:%d,y:%s}", int(x_value), data[i]
                if (i < count - 1) printf ","
            }
        }
    }')
    
    # Create time-based buckets using simpler approach
    echo "Creating time-based response time buckets..."
    
    # Group recent requests into buckets for trend analysis
    TIME_BUCKET_DATA=$(tail -50 "$NGINX_ACCESS_LOG" | grep -oE 'urt="[0-9.]+"' | sed 's/urt="//g; s/"//g' | awk '{
        bucket = int((NR - 1) / 5)  # Group every 5 requests
        sum[bucket] += $1
        count[bucket]++
        if (bucket > max_bucket) max_bucket = bucket
    } END {
        bucket_count = 0
        for (i = 0; i <= max_bucket; i++) {
            if (count[i] > 0) {
                avg_data[bucket_count] = sum[i] / count[i]
                bucket_count++
            }
        }
        # Output evenly spaced buckets
        for (i = 0; i < bucket_count; i++) {
            if (bucket_count > 1) {
                x_pos = i * 100 / (bucket_count - 1)
            } else {
                x_pos = 50
            }
            printf "{x:%d,y:%.3f}", int(x_pos), avg_data[i]
            if (i < bucket_count - 1) printf ","
        }
    }')
    
    # Get last 200 entries for detailed cache analysis
    echo "Processing cache statistics..."
    CACHE_TIME_DATA=""
    hit_count=0
    total_count=0
    counter=0
    
    tail -200 "$NGINX_ACCESS_LOG" | while read line; do
        cache_status=$(echo "$line" | grep -oE 'cs=[A-Z]+' | cut -d= -f2)
        if [ -n "$cache_status" ]; then
            if [ "$cache_status" = "HIT" ]; then
                hit_count=$((hit_count + 1))
            fi
            total_count=$((total_count + 1))
            counter=$((counter + 1))
            
            # Calculate hit rate every 10 requests
            if [ $((counter % 10)) -eq 0 ] && [ $total_count -gt 0 ]; then
                hit_rate=$(awk "BEGIN {printf \"%.1f\", $hit_count * 100 / $total_count}")
                echo "$counter,$hit_rate" >> tmp/cache_time_data.txt
            fi
        fi
    done
    
    # Read the cache time data
    if [ -f tmp/cache_time_data.txt ]; then
        CACHE_TIME_DATA=$(cat tmp/cache_time_data.txt | awk -F, '{printf "{x:%s,y:%s},", $1, $2}' | sed 's/,$//')
        rm -f tmp/cache_time_data.txt
    fi
    
    # Calculate response time distribution buckets
    BUCKET_FAST=$(tail -500 "$NGINX_ACCESS_LOG" | grep -oE 'urt="[0-9.]+"' | sed 's/urt="//g; s/"//g' | awk '$1 < 0.5 {count++} END {print count+0}')
    BUCKET_MEDIUM=$(tail -500 "$NGINX_ACCESS_LOG" | grep -oE 'urt="[0-9.]+"' | sed 's/urt="//g; s/"//g' | awk '$1 >= 0.5 && $1 < 1 {count++} END {print count+0}')
    BUCKET_SLOW=$(tail -500 "$NGINX_ACCESS_LOG" | grep -oE 'urt="[0-9.]+"' | sed 's/urt="//g; s/"//g' | awk '$1 >= 1 && $1 < 2 {count++} END {print count+0}')
    BUCKET_SLOWER=$(tail -500 "$NGINX_ACCESS_LOG" | grep -oE 'urt="[0-9.]+"' | sed 's/urt="//g; s/"//g' | awk '$1 >= 2 && $1 < 5 {count++} END {print count+0}')
    BUCKET_SLOWEST=$(tail -500 "$NGINX_ACCESS_LOG" | grep -oE 'urt="[0-9.]+"' | sed 's/urt="//g; s/"//g' | awk '$1 >= 5 {count++} END {print count+0}')
fi

# Generate HTML report
cat > "$REPORT_FILE" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Siege Performance Report - ${TIMESTAMP}</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns/dist/chartjs-adapter-date-fns.bundle.min.js"></script>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            background-color: #f5f5f5;
            color: #333;
            line-height: 1.6;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        
        header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px 0;
            text-align: center;
            margin-bottom: 40px;
            border-radius: 10px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
        }
        
        h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        
        .subtitle {
            font-size: 1.2em;
            opacity: 0.9;
        }
        
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }
        
        .metric-card {
            background: white;
            border-radius: 10px;
            padding: 25px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.08);
            transition: transform 0.3s ease, box-shadow 0.3s ease;
        }
        
        .metric-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 10px 25px rgba(0,0,0,0.15);
        }
        
        .metric-label {
            font-size: 0.9em;
            color: #666;
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 10px;
        }
        
        .metric-value {
            font-size: 2.2em;
            font-weight: bold;
            color: #333;
        }
        
        .metric-card.success {
            border-left: 4px solid #4caf50;
        }
        
        .metric-card.warning {
            border-left: 4px solid #ff9800;
        }
        
        .metric-card.error {
            border-left: 4px solid #f44336;
        }
        
        .metric-card.info {
            border-left: 4px solid #2196f3;
        }
        
        .chart-container {
            background: white;
            border-radius: 10px;
            padding: 30px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.08);
            margin-bottom: 40px;
        }
        
        .chart-row {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 20px;
            margin-bottom: 40px;
        }
        
        @media (max-width: 768px) {
            .chart-row {
                grid-template-columns: 1fr;
            }
        }
        
        .chart-title {
            font-size: 1.5em;
            margin-bottom: 20px;
            color: #333;
        }
        
        canvas {
            max-height: 400px;
        }
        
        .time-series-chart {
            height: 500px;
        }
        
        .small-chart {
            height: 300px;
        }
        
        .summary {
            background: white;
            border-radius: 10px;
            padding: 30px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.08);
            margin-bottom: 40px;
        }
        
        .summary h2 {
            font-size: 1.8em;
            margin-bottom: 20px;
            color: #333;
        }
        
        .summary-item {
            display: flex;
            justify-content: space-between;
            padding: 15px 0;
            border-bottom: 1px solid #eee;
        }
        
        .summary-item:last-child {
            border-bottom: none;
        }
        
        .summary-label {
            color: #666;
        }
        
        .summary-value {
            font-weight: bold;
            color: #333;
        }
        
        .status-badge {
            display: inline-block;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 0.9em;
            font-weight: bold;
            color: white;
        }
        
        .status-excellent {
            background-color: #4caf50;
        }
        
        .status-good {
            background-color: #8bc34a;
        }
        
        .status-warning {
            background-color: #ff9800;
        }
        
        .status-poor {
            background-color: #f44336;
        }
        
        footer {
            text-align: center;
            padding: 40px 0;
            color: #666;
        }
        
        .performance-score {
            text-align: center;
            margin: 40px 0;
        }
        
        .score-circle {
            display: inline-block;
            width: 200px;
            height: 200px;
            border-radius: 50%;
            position: relative;
            background: conic-gradient(#4caf50 0deg, #4caf50 var(--availability-deg, 0deg), #f5f5f5 var(--availability-deg, 0deg));
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
        }
        
        .score-circle.no-data {
            background: linear-gradient(135deg, #e0e0e0 0%, #f5f5f5 100%);
        }
        
        .score-inner {
            position: absolute;
            top: 20px;
            left: 20px;
            right: 20px;
            bottom: 20px;
            background: white;
            border-radius: 50%;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
        }
        
        .score-value {
            font-size: 3em;
            font-weight: bold;
            color: #333;
        }
        
        .score-label {
            font-size: 1em;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>Siege Performance Report</h1>
            <div class="subtitle">Generated on $(date '+%Y-%m-%d %H:%M:%S')</div>
        </header>
        
        <div class="performance-score">
            <div class="score-circle" id="availabilityCircle">
                <div class="score-inner">
                    <div class="score-value" id="availabilityValue">${AVAILABILITY:-"N/A"}</div>
                    <div class="score-label">System Availability</div>
                </div>
            </div>
            <p style="margin-top: 20px; color: #666; text-align: center; max-width: 400px; margin-left: auto; margin-right: auto;">
                <strong>System Availability</strong> measures the percentage of successful requests during the load test. 
                A complete siege test is needed to calculate this metric.
            </p>
        </div>
        
        <div class="metrics-grid">
            <div class="metric-card success">
                <div class="metric-label">Successful Transactions</div>
                <div class="metric-value">${SUCCESSFUL:-0}</div>
            </div>
            
            <div class="metric-card error">
                <div class="metric-label">Failed Transactions</div>
                <div class="metric-value">${FAILED:-0}</div>
            </div>
            
            <div class="metric-card info">
                <div class="metric-label">Transaction Rate</div>
                <div class="metric-value">${TRANSACTION_RATE:-0}</div>
            </div>
            
            <div class="metric-card info">
                <div class="metric-label">Response Time</div>
                <div class="metric-value">${RESPONSE_TIME:-0}</div>
            </div>
            
            <div class="metric-card info">
                <div class="metric-label">Throughput</div>
                <div class="metric-value">${THROUGHPUT:-0}</div>
            </div>
            
            <div class="metric-card info">
                <div class="metric-label">Concurrency</div>
                <div class="metric-value">${CONCURRENCY:-0}</div>
            </div>
        </div>
        
        <div class="chart-container time-series-chart">
            <h2 class="chart-title">Response Time Over Time</h2>
            <canvas id="responseTimeChart"></canvas>
        </div>
        
        <div class="chart-row">
            <div class="chart-container small-chart">
                <h2 class="chart-title">Transaction Distribution</h2>
                <canvas id="transactionChart"></canvas>
            </div>
            
            <div class="chart-container small-chart">
                <h2 class="chart-title">Response Time Distribution</h2>
                <canvas id="responseDistChart"></canvas>
            </div>
        </div>
        
EOF

# Add cache statistics if available
if [ -f "$NGINX_ACCESS_LOG" ]; then
    cat >> "$REPORT_FILE" << EOF
        <div class="chart-row">
            <div class="chart-container small-chart">
                <h2 class="chart-title">Cache Performance</h2>
                <canvas id="cacheChart"></canvas>
            </div>
            
            <div class="chart-container small-chart">
                <h2 class="chart-title">Cache Hit Rate Over Time</h2>
                <canvas id="cacheTimeChart"></canvas>
            </div>
        </div>
        
        <div class="summary">
            <h2>Cache Statistics</h2>
            <div class="summary-item">
                <span class="summary-label">Cache Hit Rate</span>
                <span class="summary-value">${CACHE_HIT_RATE}%</span>
            </div>
            <div class="summary-item">
                <span class="summary-label">Total Cache Hits</span>
                <span class="summary-value">${CACHE_HITS}</span>
            </div>
            <div class="summary-item">
                <span class="summary-label">Total Cache Misses</span>
                <span class="summary-value">${CACHE_MISSES}</span>
            </div>
            <div class="summary-item">
                <span class="summary-label">Average Response Time (nginx)</span>
                <span class="summary-value">${AVG_RESPONSE_TIME}s</span>
            </div>
        </div>
EOF
fi

# Complete the HTML
cat >> "$REPORT_FILE" << EOF
        <div class="summary">
            <h2>Test Summary</h2>
            <div class="summary-item">
                <span class="summary-label">Test Duration</span>
                <span class="summary-value">${ELAPSED_TIME:-0}</span>
            </div>
            <div class="summary-item">
                <span class="summary-label">Data Transferred</span>
                <span class="summary-value">${DATA_TRANSFERRED:-0}</span>
            </div>
            <div class="summary-item">
                <span class="summary-label">Total Transactions</span>
                <span class="summary-value">${TRANSACTIONS:-0}</span>
            </div>
            <div class="summary-item">
                <span class="summary-label">Performance Status</span>
                <span class="summary-value">
EOF

# Determine performance status
AVAILABILITY_NUM=${AVAILABILITY%\%}
if [ -n "$AVAILABILITY_NUM" ] && [ "$AVAILABILITY_NUM" != "" ]; then
    if awk "BEGIN {exit !($AVAILABILITY_NUM >= 99.5)}" 2>/dev/null; then
        echo '<span class="status-badge status-excellent">Excellent</span>' >> "$REPORT_FILE"
    elif awk "BEGIN {exit !($AVAILABILITY_NUM >= 99)}" 2>/dev/null; then
        echo '<span class="status-badge status-good">Good</span>' >> "$REPORT_FILE"
    elif awk "BEGIN {exit !($AVAILABILITY_NUM >= 95)}" 2>/dev/null; then
        echo '<span class="status-badge status-warning">Warning</span>' >> "$REPORT_FILE"
    else
        echo '<span class="status-badge status-poor">Poor</span>' >> "$REPORT_FILE"
    fi
else
    echo '<span class="status-badge status-warning">Unknown</span>' >> "$REPORT_FILE"
fi

cat >> "$REPORT_FILE" << EOF
                </span>
            </div>
        </div>
        
        <footer>
            <p>Report generated from: ${SIEGE_LOG}</p>
        </footer>
    </div>
    
    <script>
        // Initialize Availability Circle
        function initAvailabilityCircle() {
            const availabilityText = '${AVAILABILITY:-"0.00%"}';
            const circle = document.getElementById('availabilityCircle');
            const valueElement = document.getElementById('availabilityValue');
            
            if (availabilityText === 'N/A' || availabilityText === '0.00%' || availabilityText === '') {
                circle.classList.add('no-data');
                valueElement.textContent = 'N/A';
                return;
            }
            
            // Extract percentage value
            const percentage = parseFloat(availabilityText.replace('%', ''));
            
            if (!isNaN(percentage)) {
                // Calculate degrees for the conic gradient (360 degrees = 100%)
                const degrees = (percentage / 100) * 360;
                circle.style.setProperty('--availability-deg', degrees + 'deg');
                
                // Set color based on performance
                let color = '#f44336'; // Red for poor
                if (percentage >= 99.5) color = '#4caf50'; // Green for excellent
                else if (percentage >= 99) color = '#8bc34a'; // Light green for good
                else if (percentage >= 95) color = '#ff9800'; // Orange for warning
                
                circle.style.background = 'conic-gradient(' + color + ' 0deg, ' + color + ' ' + degrees + 'deg, #f5f5f5 ' + degrees + 'deg)';
                valueElement.textContent = percentage.toFixed(1) + '%';
            }
        }
        
        // Initialize on page load
        initAvailabilityCircle();
        
        // Response Time Over Time Chart
        const responseTimeCtx = document.getElementById('responseTimeChart').getContext('2d');
        
        // Embedded response time data
        const responseData = [${RESPONSE_TIME_DATA:-}];
        const timeBucketData = [${TIME_BUCKET_DATA:-}];
        
        // Use time bucket data if available, otherwise use individual response data
        const dataToUse = timeBucketData.length > 0 ? timeBucketData : responseData;
        const labelText = timeBucketData.length > 0 ? 'Request Groups (5 requests each)' : 'Individual Requests (Recent 30)';
        
        if (dataToUse.length > 0) {
            new Chart(responseTimeCtx, {
                type: 'line',
                data: {
                    datasets: [{
                        label: 'Response Time (seconds)',
                        data: dataToUse,
                        borderColor: '#2196f3',
                        backgroundColor: 'rgba(33, 150, 243, 0.1)',
                        fill: true,
                        tension: 0.3,
                        pointRadius: 3,
                        pointHoverRadius: 6,
                        pointBackgroundColor: '#2196f3',
                        pointBorderColor: '#1976d2',
                        pointBorderWidth: 2
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    scales: {
                        x: {
                            type: 'linear',
                            position: 'bottom',
                            min: 0,
                            max: 100,
                            title: {
                                display: true,
                                text: labelText
                            },
                            grid: {
                                display: true,
                                color: 'rgba(0,0,0,0.1)'
                            },
                            ticks: {
                                stepSize: 20
                            }
                        },
                        y: {
                            title: {
                                display: true,
                                text: 'Response Time (seconds)'
                            },
                            beginAtZero: true,
                            grid: {
                                display: true,
                                color: 'rgba(0,0,0,0.1)'
                            }
                        }
                    },
                    plugins: {
                        legend: {
                            display: false
                        },
                        tooltip: {
                            callbacks: {
                                title: function(context) {
                                    return timeBucketData.length > 0 ? 
                                        'Request group: ' + (context[0].parsed.x + 1) + '-' + (context[0].parsed.x + 10) :
                                        'Request #' + (context[0].parsed.x / 2 + 1);
                                },
                                label: function(context) {
                                    return 'Response time: ' + context.parsed.y.toFixed(3) + 's';
                                }
                            }
                        }
                    },
                    elements: {
                        point: {
                            hoverRadius: 8
                        }
                    }
                }
            });
        } else {
            responseTimeCtx.canvas.parentNode.innerHTML = '<div style="text-align: center; padding: 40px; color: #666;"><p>No response time data available</p><small>Run a load test to see response time trends</small></div>';
        }
        
        // Transaction Chart
        const transactionCtx = document.getElementById('transactionChart').getContext('2d');
        new Chart(transactionCtx, {
            type: 'doughnut',
            data: {
                labels: ['Successful', 'Failed'],
                datasets: [{
                    data: [${SUCCESSFUL:-0}, ${FAILED:-0}],
                    backgroundColor: ['#4caf50', '#f44336'],
                    borderWidth: 0
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        position: 'bottom',
                        labels: {
                            padding: 20,
                            font: {
                                size: 12
                            }
                        }
                    }
                }
            }
        });
        
        // Response Time Distribution Chart
        const responseDistCtx = document.getElementById('responseDistChart').getContext('2d');
        
        // Embedded distribution data
        const buckets = {
            '< 0.5s': ${BUCKET_FAST:-0},
            '0.5-1s': ${BUCKET_MEDIUM:-0},
            '1-2s': ${BUCKET_SLOW:-0},
            '2-5s': ${BUCKET_SLOWER:-0},
            '> 5s': ${BUCKET_SLOWEST:-0}
        };
        
        new Chart(responseDistCtx, {
            type: 'bar',
            data: {
                labels: Object.keys(buckets),
                datasets: [{
                    label: 'Request Count',
                    data: Object.values(buckets),
                    backgroundColor: [
                        '#4caf50',
                        '#8bc34a',
                        '#ffc107',
                        '#ff9800',
                        '#f44336'
                    ],
                    borderWidth: 0
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: {
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: 'Request Count'
                        }
                    },
                    x: {
                        title: {
                            display: true,
                            text: 'Response Time Range'
                        }
                    }
                },
                plugins: {
                    legend: {
                        display: false
                    }
                }
            }
        });
EOF

# Add cache chart if available
if [ -f "$NGINX_ACCESS_LOG" ]; then
    cat >> "$REPORT_FILE" << EOF
        
        // Cache Chart
        const cacheCtx = document.getElementById('cacheChart').getContext('2d');
        new Chart(cacheCtx, {
            type: 'doughnut',
            data: {
                labels: ['HIT', 'MISS', 'EXPIRED', 'UPDATING', 'STALE'],
                datasets: [{
                    label: 'Cache Status Count',
                    data: [${CACHE_HITS}, ${CACHE_MISSES}, ${CACHE_EXPIRED}, ${CACHE_UPDATING}, ${CACHE_STALE}],
                    backgroundColor: [
                        '#4caf50',
                        '#f44336',
                        '#ff9800',
                        '#2196f3',
                        '#9e9e9e'
                    ],
                    borderWidth: 0
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        position: 'bottom',
                        labels: {
                            padding: 10,
                            font: {
                                size: 12
                            }
                        }
                    },
                    tooltip: {
                        callbacks: {
                            label: function(context) {
                                const total = context.dataset.data.reduce((a, b) => a + b, 0);
                                const percentage = ((context.parsed / total) * 100).toFixed(1);
                                return context.label + ': ' + context.parsed + ' (' + percentage + '%)';
                            }
                        }
                    }
                }
            }
        });
        
        // Cache Hit Rate Over Time Chart
        const cacheTimeCtx = document.getElementById('cacheTimeChart').getContext('2d');
        
        // Embedded cache time data
        const cacheTimeData = [${CACHE_TIME_DATA:-}];
        
        if (cacheTimeData.length > 0) {
            new Chart(cacheTimeCtx, {
                type: 'line',
                data: {
                    datasets: [{
                        label: 'Cache Hit Rate (%)',
                        data: cacheTimeData,
                        borderColor: '#4caf50',
                        backgroundColor: 'rgba(76, 175, 80, 0.1)',
                        fill: true,
                        tension: 0.4,
                        pointRadius: 2,
                        pointHoverRadius: 4
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    scales: {
                        x: {
                            type: 'linear',
                            position: 'bottom',
                            min: 0,
                            max: 100,
                            title: {
                                display: true,
                                text: 'Request Sequence (every 5 requests)'
                            },
                            ticks: {
                                stepSize: 20
                            }
                        },
                        y: {
                            title: {
                                display: true,
                                text: 'Hit Rate (%)'
                            },
                            beginAtZero: true,
                            max: 100
                        }
                    },
                    plugins: {
                        legend: {
                            display: false
                        },
                        tooltip: {
                            callbacks: {
                                label: function(context) {
                                    return context.parsed.y.toFixed(1) + '%';
                                }
                            }
                        }
                    }
                }
            });
        } else {
            cacheTimeCtx.canvas.parentNode.innerHTML = '<p>Cache time series data not available</p>';
        }
EOF
fi

cat >> "$REPORT_FILE" << EOF
    </script>
</body>
</html>
EOF

echo -e "${GREEN}HTML report generated: $REPORT_FILE${NC}"

# Open the report in the default browser if on macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
    open "$REPORT_FILE"
fi