# Production Testing Guide

This guide explains how to perform load testing and collect logs in production environments where you don't have direct access to nginx log files.

## Quick Start

### Docker Environment
```bash
# Test with Docker container log collection
./tools/production_test.sh https://your-cdn.com 50 2M docker nginx-container
```

### Kubernetes Environment  
```bash
# Test with Kubernetes pod log collection
./tools/production_test.sh https://your-cdn.com 50 2M k8s nginx-pod-name
```

### SSH Access to Server
```bash
# Test with SSH log collection
./tools/production_test.sh https://your-cdn.com 50 2M ssh user@prod-server
```

## Log Collection Methods

### 1. Docker Container Logs

**Requirements:**
- Docker access to the nginx container
- Container name or ID

**Setup:**
```bash
# Find your nginx container
docker ps | grep nginx

# Collect logs
./tools/collect_logs.sh docker nginx-container 5m
```

**What it collects:**
- `/var/log/nginx/access.log` from container
- `/var/log/nginx/error.log` from container  
- Container stdout/stderr logs

### 2. Kubernetes Pod Logs

**Requirements:**
- `kubectl` access to the cluster
- Pod name or selector

**Setup:**
```bash
# Find your nginx pod
kubectl get pods | grep nginx

# Collect logs
./tools/collect_logs.sh k8s nginx-pod-name 5m
```

**What it collects:**
- Pod logs via `kubectl logs`
- Log files from pod filesystem (if accessible)

### 3. SSH Server Access

**Requirements:**
- SSH access to the server
- Read permissions on log files

**Setup:**
```bash
# Test SSH connection
ssh user@prod-server "echo 'Connected'"

# Collect logs
./tools/collect_logs.sh ssh user@prod-server 5m
```

**What it collects:**
- Nginx log files via `scp`
- systemd journal entries for nginx
- Custom log paths

### 4. Manual Log Collection

If automated collection doesn't work:

```bash
# 1. Manually copy logs to collected_logs/
mkdir -p collected_logs
cp /path/to/access.log collected_logs/access_$(date +%Y%m%d_%H%M%S).log

# 2. Run your test
./tools/siege_image_test.sh https://your-cdn.com 50 2M

# 3. Collect post-test logs
cp /path/to/access.log collected_logs/access_$(date +%Y%m%d_%H%M%S)_post.log

# 4. Generate report
./tools/generate_report.sh
```

## Production Configuration Tips

### Nginx Log Format

Ensure your nginx config includes response time logging:

```nginx
log_format detailed '$remote_addr - $remote_user [$time_local] '
                   '"$request" $status $body_bytes_sent '
                   '"$http_referer" "$http_user_agent" '
                   'rt=$request_time uct="$upstream_connect_time" '
                   'uht="$upstream_header_time" urt="$upstream_response_time" '
                   'cs=$upstream_cache_status';

access_log /var/log/nginx/access.log detailed;
```

### Log Rotation

Ensure logs don't grow too large:

```bash
# Add to logrotate.d/nginx
/var/log/nginx/*.log {
    daily
    missingok
    rotate 7
    compress
    notifempty
    create 0644 nginx nginx
    postrotate
        nginx -s reload
    endscript
}
```

### Security Considerations

- **Log Permissions**: Ensure log collection scripts have minimal required permissions
- **Data Sensitivity**: Be careful with logs containing user data
- **Network Security**: Use secure channels (SSH, VPN) for log transfer
- **Retention**: Set appropriate log retention policies

## Troubleshooting

### Common Issues

**Cannot connect to Docker container:**
```bash
# Check container status
docker ps -a | grep nginx

# Check if container is running
docker logs nginx-container
```

**SSH connection fails:**
```bash
# Test connection
ssh -v user@server

# Check SSH key authentication
ssh-copy-id user@server
```

**Kubectl access denied:**
```bash
# Check cluster access
kubectl auth can-i get pods

# Check namespace
kubectl get pods -n your-namespace
```

**No logs collected:**
```bash
# Check log paths manually
find /var/log -name "*nginx*" -name "*.log"

# Check permissions
ls -la /var/log/nginx/
```

### Performance Impact

**Log Collection Impact:**
- Minimal during log copying
- Brief network usage during transfer
- No impact on nginx performance

**Load Testing Impact:**
- Configure appropriate concurrency levels
- Start with lower loads in production
- Monitor server resources during tests

## Example Workflows

### Complete Production Test
```bash
#!/bin/bash

# 1. Pre-test health check
curl -f https://your-cdn.com/health

# 2. Collect baseline logs
./tools/collect_logs.sh docker nginx 5m

# 3. Run progressive load test
./tools/production_test.sh https://your-cdn.com 10 1M docker nginx
./tools/production_test.sh https://your-cdn.com 25 2M docker nginx  
./tools/production_test.sh https://your-cdn.com 50 2M docker nginx

# 4. Generate comparison report
./tools/generate_report.sh
```

### Monitoring During Test
```bash
# Monitor container resources
docker stats nginx-container

# Monitor pod resources  
kubectl top pod nginx-pod

# Monitor server resources
ssh user@server "top -p \$(pgrep nginx)"
```

## Results Analysis

After testing, you'll have:

- **Performance Reports**: HTML reports with charts and metrics
- **Log Archive**: Timestamped logs for historical comparison
- **Cache Analysis**: Hit rates and performance trends
- **Error Analysis**: Any issues encountered during testing

Use these to optimize your nginx configuration and scaling strategy.