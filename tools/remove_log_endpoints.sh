#!/bin/bash

# Remove temporary log endpoints from nginx config
# Usage: ./remove_log_endpoints.sh

set -e

NGINX_CONFIG="config/nginx.conf"
BACKUP_CONFIG="config/nginx.conf.backup.$(date +%Y%m%d_%H%M%S)"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Removing temporary log endpoints from nginx config${NC}"
echo "=================================================="

# Check if config file exists
if [ ! -f "$NGINX_CONFIG" ]; then
    echo -e "${RED}Error: $NGINX_CONFIG not found${NC}"
    exit 1
fi

# Create backup
echo "Creating backup: $BACKUP_CONFIG"
cp "$NGINX_CONFIG" "$BACKUP_CONFIG"

# Check if log endpoints exist
if grep -q "/access-log\|/error-log" "$NGINX_CONFIG"; then
    echo "Log endpoints found, removing them..."
    
    # Remove the log endpoint blocks
    sed -i.tmp '
        /# Temporary log access endpoint/,/}/ {
            /# Temporary log access endpoint/d
            /location = \/access-log/,/}/ d
        }
        /# Temporary error log access endpoint/,/}/ {
            /# Temporary error log access endpoint/d
            /location = \/error-log/,/}/ d
        }
    ' "$NGINX_CONFIG"
    
    # Clean up temp file
    rm -f "${NGINX_CONFIG}.tmp"
    
    echo -e "${GREEN}✓ Log endpoints removed successfully${NC}"
    
    # Show what was removed
    echo ""
    echo "Removed endpoints:"
    echo "- /access-log"
    echo "- /error-log"
    
    # Restart nginx if running in Docker
    echo ""
    echo -e "${YELLOW}Restarting nginx to apply changes...${NC}"
    if command -v docker-compose &> /dev/null; then
        docker-compose restart nginx
        echo -e "${GREEN}✓ Nginx restarted${NC}"
    else
        echo -e "${YELLOW}Please restart nginx manually to apply changes${NC}"
    fi
    
else
    echo -e "${GREEN}No log endpoints found in config${NC}"
fi

echo ""
echo -e "${GREEN}Security cleanup complete!${NC}"
echo "Backup saved as: $BACKUP_CONFIG"
echo ""
echo -e "${YELLOW}Note: If you need the endpoints again, you can:${NC}"
echo "1. Restore from backup: cp $BACKUP_CONFIG $NGINX_CONFIG"
echo "2. Or re-run the setup manually"