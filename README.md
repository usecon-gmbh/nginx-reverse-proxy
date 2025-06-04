# Nginx Reverse Proxy for Image Processing

A high-performance nginx reverse proxy with imgproxy for image resizing and optimization.

## Project Structure

```
.
├── config/                     # Configuration files
│   ├── nginx.conf              # Nginx configuration
│   └── PRODUCTION_TESTING_GUIDE.md  # Production testing guidelines
├── data/                       # Runtime data (gitignored)
│   ├── cache/                  # Nginx cache files
│   └── logs/                   # Application logs
├── reports/                    # Test reports and results
├── tools/                      # Testing and monitoring tools
│   ├── siege_image_test.sh     # Main load testing script
│   ├── cache_test.sh           # Cache performance testing
│   ├── generate_report.sh      # HTML report generator
│   └── monitor_cache.sh        # Real-time cache monitoring
├── docker-compose.yml          # Docker configuration
├── performance_plotter.ps1     # PowerShell performance plotter
├── performance_test.ps1        # PowerShell performance test
└── .gitignore                  # Git ignore rules
```

## Quick Start

1. **Start the services:**

   ```bash
   docker-compose up -d
   ```

2. **Run a load test:**

   ```bash
   ./tools/siege_image_test.sh
   ```

3. **Monitor cache performance:**
   ```bash
   ./tools/monitor_cache.sh
   ```

## Configuration

### Nginx Configuration

- Located in `config/nginx.conf`
- Optimized for high concurrency (10,240 worker connections)
- Rate limiting: 500 requests/second with 1,000 burst
- Cache configuration for optimal performance

### Environment Variables

- `BASE_URL`: Target URL for testing (default: http://localhost:8081)
- `CONCURRENT_USERS`: Number of concurrent siege users (default: 50)
- `TEST_DURATION`: Duration of load test (default: 2M)

## Testing Tools

### Load Testing

```bash
# Basic test (50 users, 2 minutes)
./tools/siege_image_test.sh

# Custom test (200 users, 5 minutes)
./tools/siege_image_test.sh http://localhost:8081 200 5M

# Production test
./tools/siege_image_test.sh https://cdn.example.com 300 3M
```

### Cache Testing

```bash
# Quick cache performance test
./tools/cache_test.sh

# Custom duration
./tools/cache_test.sh http://localhost:8081 60s
```

### Real-time Monitoring

```bash
# Monitor cache hit rates
./tools/monitor_cache.sh

# Monitor access logs
tail -f data/logs/access.log | grep --color 'cs='
```

### Report Generation

```bash
# Generate HTML report from latest test
./tools/generate_report.sh

# Generate report from specific log
./tools/generate_report.sh reports/siege_20240604_123456.log
```

## Performance Optimization

### Nginx Optimizations

- Worker connections: 10,240
- Keepalive connections: 128 upstream, 1,000 requests
- File caching: 10,000 files, 60s inactive
- Rate limiting: 500 r/s with 1,000 burst

### Cache Settings

- Minimum uses before caching: 1
- Cache validity: 30 days for 200/206/301/302
- Background updates enabled
- Stale content served during updates

### Recommended Concurrency Levels

- **Local testing**: 50-100 concurrent users
- **Staging**: 100-200 concurrent users
- **Production**: 200-500 concurrent users
- **Stress testing**: 500-1000 concurrent users

## Production Deployment

1. **Review production guide:**

   ```bash
   cat config/PRODUCTION_TESTING_GUIDE.md
   ```

2. **Progressive load testing:**

   ```bash
   # Start conservative
   ./tools/siege_image_test.sh https://your-cdn.com 200 5M

   # Increase gradually
   ./tools/siege_image_test.sh https://your-cdn.com 400 5M
   ```

3. **Monitor during tests:**
   - Server CPU/memory usage
   - Network I/O
   - Cache hit rates
   - Error logs

## Troubleshooting

### Common Issues

- **Rate limiting (429 errors)**: Reduce concurrent users or increase rate limits
- **Low cache hit rate**: Check `proxy_cache_min_uses` setting
- **High response times**: Monitor server resources and cache performance
- **Connection errors**: Verify nginx and imgproxy containers are running

### Log Analysis

```bash
# Check error logs
tail -f data/logs/error.log

# Analyze cache performance
grep -E "cs=(HIT|MISS)" data/logs/access.log | tail -100

# Count status codes
awk '{print $9}' data/logs/access.log | sort | uniq -c
```

## Development

### File Organization

- **Configuration**: `config/` directory
- **Tools**: `tools/` directory with executable scripts
- **Data**: `data/` directory (gitignored for cache and logs)
- **Reports**: `reports/` directory for test results

### Adding New Tools

1. Create script in `tools/` directory
2. Make executable: `chmod +x tools/your-script.sh`
3. Update paths to use `data/logs/` and `data/cache/`
4. Update this README if needed

## License

[Your License Here]
