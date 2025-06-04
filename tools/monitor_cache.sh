#!/bin/bash

# Real-time cache monitoring script
echo "Monitoring nginx cache performance..."
echo "Press Ctrl+C to stop"
echo ""

while true; do
    # Count cache statuses from last 100 lines
    HITS=$(tail -100 data/logs/access.log | grep -c "cs=HIT" || echo 0)
    MISSES=$(tail -100 data/logs/access.log | grep -c "cs=MISS" || echo 0)
    EXPIRED=$(tail -100 data/logs/access.log | grep -c "cs=EXPIRED" || echo 0)
    UPDATING=$(tail -100 data/logs/access.log | grep -c "cs=UPDATING" || echo 0)
    
    TOTAL=$((HITS + MISSES + EXPIRED + UPDATING))
    
    if [ $TOTAL -gt 0 ]; then
        HIT_RATE=$(awk -v h=$HITS -v t=$TOTAL 'BEGIN {printf "%.1f", h*100/t}')
    else
        HIT_RATE="0.0"
    fi
    
    # Clear line and print stats
    printf "\rHIT: %3d  MISS: %3d  EXPIRED: %3d  UPDATING: %3d  | Hit Rate: %5s%% | Total: %3d" \
        "$HITS" "$MISSES" "$EXPIRED" "$UPDATING" "$HIT_RATE" "$TOTAL"
    
    sleep 1
done