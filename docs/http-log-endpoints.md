# HTTP Log Endpoints for Production Testing

This document explains the temporary HTTP endpoints for accessing nginx logs, useful for production environments where direct log file access isn't available.

## Overview

The nginx configuration includes temporary endpoints that expose access and error logs via HTTP. These are secured with IP restrictions and should be removed after testing.

## Endpoints

### Access Log
- **URL**: `http://your-server:8081/access-log`
- **Method**: GET
- **Response**: Raw nginx access log content
- **Content-Type**: text/plain
- **Security**: IP-restricted to local networks

### Error Log  
- **URL**: `http://your-server:8081/error-log`
- **Method**: GET
- **Response**: Raw nginx error log content
- **Content-Type**: text/plain
- **Security**: IP-restricted to local networks

### Health Check
- **URL**: `http://your-server:8081/health`
- **Method**: GET
- **Response**: "OK"
- **Purpose**: Verify nginx is accessible

## Security Configuration

The endpoints are restricted to:
- `127.0.0.1` (localhost)
- `172.16.0.0/12` (Docker networks)
- `192.168.0.0/16` (Private networks)
- `10.0.0.0/8` (Private networks)

All other IPs are denied access.

## Usage

### Manual Testing
```bash
# Test health endpoint
curl http://localhost:8081/health

# Download access log
curl http://localhost:8081/access-log -o access.log

# Download error log  
curl http://localhost:8081/error-log -o error.log
```

### Automated Collection
```bash
# Collect logs via HTTP
./tools/collect_logs_http.sh http://localhost:8081

# Complete production test workflow
./tools/production_test.sh http://localhost:8081 50 2M
```

## Production Workflow

### 1. Enable Endpoints
The endpoints are already configured in `config/nginx.conf`. Simply restart nginx:
```bash
docker-compose restart nginx
```

### 2. Run Load Tests
```bash
# Complete workflow with automatic log collection
./tools/production_test.sh https://your-cdn.com 50 2M

# Or manual steps:
./tools/collect_logs_http.sh https://your-cdn.com  # Pre-test
./tools/siege_image_test.sh https://your-cdn.com 50 2M
./tools/collect_logs_http.sh https://your-cdn.com  # Post-test
./tools/generate_report.sh
```

### 3. Remove Endpoints (Important!)
```bash
# Remove endpoints for security
./tools/remove_log_endpoints.sh
```

## Security Considerations

### ⚠️ Important Security Notes

1. **Temporary Use Only**: These endpoints expose log data and should be removed after testing
2. **IP Restrictions**: Only accessible from local/private networks
3. **No Authentication**: Relies solely on IP filtering
4. **Log Content**: May contain sensitive information (IPs, URLs, user agents)

### Best Practices

- **Enable only during testing periods**
- **Remove immediately after use**
- **Verify IP restrictions match your network**
- **Monitor access to these endpoints**
- **Consider log data sensitivity**

### Network Security

Adjust IP restrictions in `nginx.conf` if needed:
```nginx
# Allow your specific production network
allow 10.1.0.0/16;    # Your production subnet
allow 172.20.0.0/16;  # Your staging subnet
deny all;
```

## Troubleshooting

### Endpoint Not Accessible
```bash
# Check nginx is running
curl http://localhost:8081/health

# Check IP restrictions
# Make sure your client IP is in the allowed ranges

# Check nginx logs
docker logs nginx-container
```

### Empty Log Response
```bash
# Check log file permissions in container
docker exec nginx-container ls -la /var/log/nginx/

# Check log file paths in nginx config
docker exec nginx-container nginx -T | grep log
```

### 403 Forbidden
```bash
# Your IP is not in the allowed list
# Check your IP: curl ifconfig.me
# Add your IP to nginx config allow list
```

## Configuration Details

The endpoints are configured in `config/nginx.conf`:

```nginx
# Temporary log access endpoint (REMOVE IN PRODUCTION!)
location = /access-log {
    access_log off;
    alias /var/log/nginx/access.log;
    add_header Content-Type text/plain;
    add_header Content-Disposition "attachment; filename=access.log";
    # Security: Only allow from local network
    allow 127.0.0.1;
    allow 172.16.0.0/12;  # Docker networks
    allow 192.168.0.0/16; # Private networks
    allow 10.0.0.0/8;     # Private networks
    deny all;
}
```

## Advantages Over Other Methods

- **Simple Setup**: No SSH keys, Docker access, or Kubernetes permissions needed
- **Universal**: Works with any nginx deployment (Docker, K8s, bare metal)
- **Fast**: Direct HTTP download, no container copying
- **Secure**: IP-restricted and temporary
- **Automated**: Integrates with existing test scripts

## Cleanup

Always remove the endpoints when done:

```bash
# Automated removal
./tools/remove_log_endpoints.sh

# Manual removal
# Edit config/nginx.conf and remove the log endpoint blocks
# Restart nginx
```

This method provides a clean, secure way to access logs for performance testing without requiring complex infrastructure access.