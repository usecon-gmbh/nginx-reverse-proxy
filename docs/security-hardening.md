# Security Hardening for Image Proxy Cache

## Current Security Posture Analysis

Your nginx serves as an image proxy cache that:
- Processes images from external sources
- Serves images to multiple domains (CORS enabled)
- Uses imgproxy for image transformation
- Is exposed to the internet

## Critical Security Hardening Measures

### 1. **🔒 URL Validation & Input Sanitization**

#### **Current Risk:**
Your current regex allows any URL in the `/plain/` segment, which could be exploited for SSRF attacks.

#### **Hardening:**
```nginx
# Add URL validation map
map $request_uri $is_valid_source {
    default 0;
    
    # Only allow specific domains
    ~*/plain/https://www\.wko\.at/ 1;
    ~*/plain/https://cdn\.qss\.wko\.at/ 1;
    ~*/plain/https://[a-zA-Z0-9-]+\.wko\.at/ 1;
    
    # Add other trusted domains as needed
    # ~*/plain/https://trusted-domain\.com/ 1;
}

# In your location block, add validation
location ~ ^/uzgdblnadf/rs:fill:(?<fill_size>\d+:\d+:1)/gravity:(?<gravity>\w+)/format:(?<format>\w+)/plain/(.+)$ {
    # Validate source URL
    if ($is_valid_source = 0) {
        return 403 "Forbidden source";
    }
    # ... rest of config
}
```

### 2. **🛡️ Enhanced Request Validation**

#### **Format Validation:**
```nginx
# Validate image formats
map $format $is_valid_format {
    default 0;
    "webp" 1;
    "jpg" 1;
    "jpeg" 1;
    "png" 1;
    "avif" 1;
}

# Validate gravity values
map $gravity $is_valid_gravity {
    default 0;
    "sm" 1;    # smart
    "ce" 1;    # center
    "no" 1;    # north
    "so" 1;    # south
    "ea" 1;    # east
    "we" 1;    # west
    "nowe" 1;  # northwest
    "noea" 1;  # northeast
    "sowe" 1;  # southwest
    "soea" 1;  # southeast
}
```

### 3. **🚫 Request Size & Rate Limiting**

#### **Enhanced Rate Limiting:**
```nginx
# Different rate limits by endpoint
limit_req_zone $binary_remote_addr zone=images:20m rate=100r/s;
limit_req_zone $binary_remote_addr zone=health:10m rate=10r/s;

# Add burst protection for sustained attacks
limit_req_zone $binary_remote_addr$request_uri zone=per_url:50m rate=10r/s;

server {
    # Apply different limits
    location = /health {
        limit_req zone=health burst=5 nodelay;
    }
    
    location ~ ^/uzgdblnadf/ {
        limit_req zone=images burst=50 nodelay;
        limit_req zone=per_url burst=3 nodelay;
    }
}
```

#### **Request Size Limits:**
```nginx
# Prevent large requests
location ~ ^/uzgdblnadf/ {
    # Limit URL length to prevent buffer overflow
    if ($request_uri ~ .{2000,}) {
        return 414 "URL too long";
    }
    
    # Validate size parameters aren't too large
    if ($fill_size ~ "([0-9]{5,}):([0-9]{5,}):1") {
        return 400 "Image size too large";
    }
}
```

### 4. **🔐 Security Headers Enhancement**

#### **Improved Security Headers:**
```nginx
# Enhanced security headers
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "DENY" always;  # Changed from SAMEORIGIN
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Content-Security-Policy "default-src 'none'; img-src *; style-src 'unsafe-inline'" always;
add_header Cross-Origin-Resource-Policy "cross-origin" always;
add_header Cross-Origin-Embedder-Policy "unsafe-none" always;

# Remove server signatures
more_clear_headers 'Server';
more_clear_headers 'X-Powered-By';
```

### 5. **🌐 CORS Hardening**

#### **Restrictive CORS (if possible):**
```nginx
# Instead of wildcard, use specific domains if known
map $http_origin $cors_origin {
    default "";
    
    # Add specific domains that should be allowed
    "~^https://[a-zA-Z0-9-]+\.wko\.at$" $http_origin;
    "~^https://wko\.at$" $http_origin;
    
    # Add other trusted domains
    # "~^https://trusted-domain\.com$" $http_origin;
}

location ~ ^/uzgdblnadf/ {
    # Use mapped origin instead of wildcard
    add_header Access-Control-Allow-Origin $cors_origin always;
    add_header Access-Control-Allow-Methods "GET, HEAD" always;  # Removed OPTIONS
    add_header Access-Control-Max-Age "86400" always;
    add_header Access-Control-Allow-Headers "Cache-Control" always;
}
```

### 6. **🛑 Error Information Disclosure**

#### **Minimal Error Responses:**
```nginx
# Hide detailed error information
proxy_intercept_errors on;
error_page 400 401 402 403 405 406 410 411 413 414 415 416 417 418 422 423 424 426 444 449 450 451 = @error;
error_page 500 501 502 503 504 505 506 507 508 509 510 511 = @error;

location @error {
    internal;
    add_header Content-Type text/plain always;
    return 400 "Bad Request";  # Generic response for all errors
}
```

### 7. **📊 Security Monitoring**

#### **Enhanced Logging for Security Events:**
```nginx
# Security-focused log format
log_format security '$remote_addr - $remote_user [$time_local] "$request" '
                   '$status $body_bytes_sent "$http_referer" "$http_user_agent" '
                   'rt=$request_time size=$fill_size gravity=$gravity format=$format '
                   'cs=$upstream_cache_status blocked="$is_valid_source$is_valid_format$is_valid_gravity"';

# Log security events to separate file
access_log /var/log/nginx/security.log security;

# Log rate limit violations
error_log /var/log/nginx/error.log warn;
```

### 8. **🔧 System-Level Hardening**

#### **Nginx Process Security:**
```nginx
# In main context
user nginx;
worker_processes auto;

# Limit worker process resources
worker_rlimit_nofile 65535;
worker_rlimit_core 0;  # Disable core dumps

# Additional security in events
events {
    worker_connections 10240;
    use epoll;
    multi_accept on;
    accept_mutex off;  # Better for high load
}
```

#### **File System Protection:**
```nginx
# Disable access to hidden files more strictly
location ~ /\. {
    deny all;
    access_log off;
    log_not_found off;
    return 404;
}

# Block common attack patterns
location ~* \.(bak|config|sql|fla|psd|ini|log|sh|inc|swp|dist)$ {
    deny all;
    access_log off;
    return 404;
}

# Block user agents that are commonly malicious
if ($http_user_agent ~* (nmap|nikto|wikto|sf|sqlmap|bsqlbf|w3af|acunetix|havij|appscan)) {
    return 403;
}
```

## Implementation Priority

### **Critical (Implement Immediately):**
1. **URL validation** - Prevent SSRF attacks
2. **Format/gravity validation** - Prevent injection
3. **Enhanced rate limiting** - Prevent DoS
4. **Request size limits** - Prevent buffer overflow

### **High Priority (This Week):**
1. **Improved security headers** - Better browser protection
2. **Restrictive CORS** - Limit cross-origin access
3. **Error information hiding** - Prevent information disclosure

### **Medium Priority (Next Week):**
1. **Security monitoring** - Better attack detection
2. **System-level hardening** - Process isolation
3. **File system protection** - Additional access controls

## Monitoring & Alerting

### **Key Metrics to Monitor:**
```bash
# Rate limit violations
grep "limiting requests" /var/log/nginx/error.log

# Blocked requests
grep "blocked=" /var/log/nginx/security.log | grep "000"

# Large image requests
grep "Image size too large" /var/log/nginx/access.log

# Invalid sources
grep "Forbidden source" /var/log/nginx/access.log
```

### **Alerting Rules:**
- More than 100 rate limit violations per minute
- More than 50 blocked requests per minute  
- Any requests for image sizes > 5000px
- Any requests to non-whitelisted domains

## Testing Security Measures

```bash
# Test URL validation
curl "http://localhost:8081/uzgdblnadf/rs:fill:592:334:1/gravity:sm/format:webp/plain/https://evil.com/image.jpg"

# Test size limits
curl "http://localhost:8081/uzgdblnadf/rs:fill:99999:99999:1/gravity:sm/format:webp/plain/https://www.wko.at/image.jpg"

# Test format validation
curl "http://localhost:8081/uzgdblnadf/rs:fill:592:334:1/gravity:sm/format:exe/plain/https://www.wko.at/image.jpg"

# Test rate limiting
for i in {1..200}; do curl -s "http://localhost:8081/health" > /dev/null; done
```