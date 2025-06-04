# Nginx Image Proxy Configuration Guide

## Overview

This is an nginx reverse proxy configuration for caching and serving processed images via imgproxy.

## Key Features

- **Image Processing**: Flexible URL pattern for gravity and format parameters
- **Caching**: Nginx proxy cache with 30-day retention
- **Security**: SSRF protection, format validation, rate limiting
- **Performance**: Optimized for high-concurrency image serving

## URL Pattern

```
/uzgdblnadf/rs:fill:{size}/gravity:{gravity}/format:{format}/plain/{source_url}
```

**Examples:**
- `http://localhost:8081/uzgdblnadf/rs:fill:592:334:1/gravity:sm/format:webp/plain/https://www.wko.at/image.jpg`

## Configuration Highlights

### Cache Settings
- **Location**: `/var/cache/nginx`
- **Size**: 50GB max, 200MB memory
- **Retention**: 10 days inactive, 30 days for successful responses
- **Min Uses**: 1 (immediate caching)

### Rate Limiting
- **Rate**: 1000 requests/second
- **Burst**: 2000 requests
- **Connections**: 500 per IP

### Security
- **Source Validation**: Only allows `*.wko.at` domains
- **Format Validation**: webp, jpg, jpeg, png, avif
- **SSRF Protection**: Blocks CDN domains to prevent loops

## Testing

```bash
# Health check
curl http://localhost:8081/health

# Image processing test
curl -I "http://localhost:8081/uzgdblnadf/rs:fill:592:334:1/gravity:sm/format:webp/plain/https://www.wko.at/image.jpg"

# Load testing
./tools/siege_image_test.sh http://localhost:8081 50 2M
```

## Configuration Validation

```bash
# Test syntax
docker exec imgproxy_cache nginx -t

# Reload configuration
docker exec imgproxy_cache nginx -s reload
```

## Common Issues

1. **Empty replies**: Check if both nginx and imgproxy containers are running
2. **404 errors**: Verify URL pattern matches the regex exactly
3. **Rate limiting**: Adjust `limit_req_zone` if getting 429 errors
4. **Cache misses**: Check if `proxy_cache_min_uses` is set correctly