# Production Load Testing Guide for Image CDN

## Concurrency Recommendations

### Progressive Load Testing Strategy

For production testing, follow a progressive approach to avoid overwhelming the system:

1. **Baseline Test** (50 users, 2 minutes)
   ```bash
   ./siege_image_test.sh https://cdn.qss.wko.at 50 2M
   ```

2. **Normal Load** (200 users, 5 minutes)
   ```bash
   ./siege_image_test.sh https://cdn.qss.wko.at 200 5M
   ```

3. **Peak Load** (500 users, 5 minutes)
   ```bash
   ./siege_image_test.sh https://cdn.qss.wko.at 500 5M
   ```

4. **Stress Test** (1000 users, 2 minutes)
   ```bash
   ./siege_image_test.sh https://cdn.qss.wko.at 1000 2M
   ```

## Expected Metrics for Production

### Acceptable Performance Thresholds

- **Availability**: > 99.5% (minimal failures)
- **Response Time**: < 1s average for cached images
- **Transaction Rate**: > 500 trans/sec
- **Cache Hit Rate**: > 80% after warm-up

### Warning Signs

- Availability < 99%
- Response times > 2s
- High error rates (> 1%)
- Memory/CPU exhaustion on servers

## Testing Schedule

### Pre-Production Testing
1. Test during off-peak hours first
2. Monitor server resources during tests
3. Have rollback plan ready

### Production Testing Windows
- **Best times**: Early morning (2-6 AM) or late evening (10 PM - 12 AM)
- **Avoid**: Business hours (9 AM - 5 PM)
- **Duration**: Keep initial tests short (2-5 minutes)

## Monitoring During Tests

### Key Metrics to Watch
1. **Server side**:
   - CPU usage
   - Memory consumption
   - Network I/O
   - Disk I/O (for cache)

2. **Application side**:
   - Error logs
   - Response times
   - Queue lengths
   - Cache performance

### Commands for Monitoring

Monitor nginx access logs:
```bash
tail -f logs/access.log | grep -E "(cs=|urt=)"
```

Watch cache hit rates:
```bash
watch -n 1 'grep -c "cs=HIT" logs/access.log; grep -c "cs=MISS" logs/access.log'
```

## Capacity Planning

Based on typical CDN patterns:

| User Load | Expected Req/s | Cache Hit Rate | Avg Response Time |
|-----------|----------------|----------------|-------------------|
| 50        | 100-200        | 70-80%         | 0.5-1s           |
| 200       | 400-800        | 80-90%         | 0.3-0.8s         |
| 500       | 1000-2000      | 85-95%         | 0.2-0.6s         |
| 1000      | 2000-4000      | 90-98%         | 0.1-0.5s         |

## Emergency Procedures

If production impact is detected:

1. **Immediately stop the test**: `Ctrl+C`
2. **Check server health**
3. **Review error logs**
4. **Scale down if needed**

## Recommendations for Production

1. **Start conservatively**: Begin with 200 concurrent users
2. **Gradual increase**: Add 100 users every test iteration
3. **Monitor continuously**: Watch server metrics in real-time
4. **Document results**: Keep records of each test
5. **Test regularly**: Monthly or after significant changes

## Example Production Test Sequence

```bash
# 1. Warm up cache (50 users, 1 minute)
./siege_image_test.sh https://cdn.qss.wko.at 50 1M

# 2. Normal load test (200 users, 5 minutes)
./siege_image_test.sh https://cdn.qss.wko.at 200 5M

# 3. Generate report
./generate_report.sh

# 4. If results are good, proceed to higher load
./siege_image_test.sh https://cdn.qss.wko.at 400 5M

# 5. Peak load test (only if previous tests passed)
./siege_image_test.sh https://cdn.qss.wko.at 600 3M
```

## Notes

- Image generation is CPU-intensive, so watch CPU usage closely
- Network bandwidth can be a bottleneck with many large images
- Cache warm-up is important for accurate results
- Consider geographic distribution of test traffic