# Nginx Configuration Optimization Recommendations

## Current Issues & Improvements

### 1. **🔧 Configuration Simplifications**

#### **Remove Unused Maps**

You have several maps that aren't being used:

**Remove these unused maps:**

```nginx
# Lines 57-72: Connection upgrade maps (not used for image proxy)
map $http_upgrade $
 { ... }
map $remote_addr $proxy_forwarded_elem { ... }
map $http_forwarded $proxy_add_forwarded { ... }
```

#### **Simplify Size Validation**

You have a size validation map but it's disabled:

```nginx
# Lines 74-99: You could remove this entirely since validation is disabled
map $fill_size $is_valid_size { ... }

# Lines 225-228: This validation is commented out
# if ($is_valid_size = 0) {
#     return 403;
# }
```

### 2. **⚡ Performance Optimizations**

#### **Buffer Size Optimizations**

Your current buffer sizes are conservative:

```nginx
# Current (line 264-267)
proxy_buffer_size 16k;
proxy_buffers 8 16k;
proxy_busy_buffers_size 32k;
proxy_temp_file_write_size 64k;

# Recommended for image proxy
proxy_buffer_size 32k;        # Increased
proxy_buffers 16 32k;         # More buffers, larger size
proxy_busy_buffers_size 64k;  # Doubled
proxy_temp_file_write_size 128k; # Doubled
```

#### **Cache Improvements**

```nginx
# Current cache path (line 102)
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=imgproxy_cache:100m max_size=50g inactive=30d use_temp_path=off;

# Recommended improvements
proxy_cache_path /var/cache/nginx
    levels=1:2
    keys_zone=imgproxy_cache:200m    # Increased memory
    max_size=100g                    # More disk space
    inactive=60d                     # Longer retention
    use_temp_path=off
    loader_threshold=1000m           # Faster cache loading
    loader_files=1000
    loader_sleeps=50ms;
```

### 3. **🛡️ Security Improvements**

#### **Remove Debug Headers in Production**

```nginx
# Line 242: Remove in production
add_header X-Cache-Status $upstream_cache_status always;
```

#### **Improve Request Method Handling**

Replace the `if` statement with a more efficient approach:

```nginx
# Instead of if statement (line 181-183)
location / {
    limit_except GET HEAD OPTIONS {
        deny all;
    }
    # ... rest of config
}
```

### 4. **📊 Monitoring Improvements**

#### **Enhanced Log Format**

```nginx
# Current log format (lines 20-25)
log_format image_proxy '$remote_addr - $remote_user [$time_local] "$request" '
    '$status $body_bytes_sent "$http_referer" '
    '"$http_user_agent" '
    'rt=$request_time uct="$upstream_connect_time" '
    'uht="$upstream_header_time" urt="$upstream_response_time" '
    'cs=$upstream_cache_status';

# Enhanced version with more metrics
log_format image_proxy_enhanced
    '$remote_addr - $remote_user [$time_local] "$request" '
    '$status $body_bytes_sent "$http_referer" "$http_user_agent" '
    'rt=$request_time uct="$upstream_connect_time" '
    'uht="$upstream_header_time" urt="$upstream_response_time" '
    'cs=$upstream_cache_status '
    'hit_ratio=$upstream_cache_status '
    'size=$fill_size gravity=$gravity format=$format';
```

### 5. **🔄 Error Handling Improvements**

#### **Better Error Pages**

```nginx
# Current error handling (lines 282-293)
location @404 {
    internal;
    return 404;
    add_header Content-Type text/plain;
}

# Improved with proper error response
location @404 {
    internal;
    add_header Content-Type application/json always;
    return 404 '{"error":"Image not found","code":404}';
}

location @50x {
    internal;
    add_header Content-Type application/json always;
    add_header Retry-After 30;
    return 503 '{"error":"Service temporarily unavailable","code":503,"retry_after":30}';
}
```

### 6. **🚀 Advanced Optimizations**

#### **HTTP/2 and SSL Preparation**

```nginx
# Add to server block for future SSL/HTTP2
listen 8080 default_server;
listen [::]:8080 default_server;  # IPv6 support

# For future SSL setup
# listen 443 ssl http2 default_server;
# listen [::]:443 ssl http2 default_server;
```

#### **Compression for Small Responses**

```nginx
# Add to http block
gzip on;
gzip_vary on;
gzip_min_length 1000;
gzip_types
    application/json
    text/plain
    text/css
    text/js
    text/xml
    text/javascript
    application/javascript
    application/xml+rss;
```

## Recommended Simplified Config Structure

```nginx
http {
    # Basic settings
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Performance
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 75;
    keepalive_requests 1000;

    # File cache
    open_file_cache max=10000 inactive=60s;
    open_file_cache_valid 30s;
    open_file_cache_min_uses 1;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=imageproxy:20m rate=500r/s;
    limit_conn_zone $binary_remote_addr zone=addr:10m;

    # Logging
    log_format image_proxy_enhanced '...';
    access_log /var/log/nginx/access.log image_proxy_enhanced;

    # Image cache
    proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=imgproxy_cache:200m
                     max_size=100g inactive=60d use_temp_path=off;

    # Upstream
    upstream imageproxy_backend {
        server imageproxy:8080;
        keepalive 128;
    }

    server {
        listen 8080 default_server;

        # Security headers (consolidated)
        include /etc/nginx/security_headers.conf;

        # Rate limiting
        limit_req zone=imageproxy burst=1000 nodelay;
        limit_conn addr 300;

        # Utility endpoints
        include /etc/nginx/utility_endpoints.conf;

        # Main image proxy location
        location ~ ^/uzgdblnadf/rs:fill:(?<fill_size>\d+:\d+:1)/gravity:(?<gravity>\w+)/format:(?<format>\w+)/plain/(.+)$ {
            # Simplified image proxy config
        }
    }
}
```

## Implementation Priority

### **High Priority (Immediate)**

1. Remove unused maps (lines 57-72)
2. Remove X-Cache-Status header in production (line 242)
3. Increase proxy buffer sizes for better performance

### **Medium Priority (Next Week)**

1. Implement better error handling with JSON responses
2. Add enhanced logging format
3. Remove disabled size validation map

### **Low Priority (Future)**

1. Split config into included files for better organization
2. Add HTTP/2 and SSL support
3. Implement advanced monitoring metrics

## Configuration Validation

Test each change:

```bash
# Test config syntax
nginx -t

# Reload gracefully
nginx -s reload

# Performance test after changes
./tools/siege_image_test.sh http://localhost:8081 50 2M
```
