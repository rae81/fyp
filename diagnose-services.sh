#!/bin/bash

###############################################################################
# Service Diagnostics Script
# Diagnose issues with phpMyAdmin, IPFS, and Webapp
###############################################################################

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  Service Diagnostics                   ${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# 1. Check MySQL connectivity
echo -e "${YELLOW}[1/5] Checking MySQL...${NC}"
docker exec mysql-coc mysql -ucocuser -pcocpassword -e "SELECT 'MySQL is accessible' as status;" 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ MySQL is working${NC}"
else
    echo -e "${RED}✗ MySQL has issues${NC}"
fi
echo ""

# 2. Check phpMyAdmin logs
echo -e "${YELLOW}[2/5] phpMyAdmin logs (last 20 lines):${NC}"
docker logs phpmyadmin-coc --tail=20
echo ""

# 3. Test IPFS from inside container
echo -e "${YELLOW}[3/5] Testing IPFS inside container...${NC}"
docker exec ipfs-node ipfs id 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ IPFS daemon is running${NC}"
else
    echo -e "${RED}✗ IPFS daemon has issues${NC}"
fi
echo ""

# 4. Test IPFS API from host
echo -e "${YELLOW}[4/5] Testing IPFS API from host...${NC}"
curl -s -X POST http://localhost:5001/api/v0/version
echo ""
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ IPFS API is accessible from host${NC}"
else
    echo -e "${RED}✗ IPFS API not accessible from host${NC}"
fi
echo ""

# 5. Check if webapp is running
echo -e "${YELLOW}[5/5] Checking webapp...${NC}"
if pgrep -f "python.*app_blockchain.py" > /dev/null; then
    echo -e "${GREEN}✓ Webapp is running${NC}"
    echo "PID: $(pgrep -f 'python.*app_blockchain.py')"
else
    echo -e "${RED}✗ Webapp is NOT running${NC}"
fi
echo ""

# Test webapp connectivity
curl -s http://localhost:5000/health
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Webapp is responding${NC}"
else
    echo -e "${RED}✗ Webapp is not responding on port 5000${NC}"
fi
echo ""

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  Diagnostic Summary                    ${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Container status
echo -e "${YELLOW}Container Status:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "mysql-coc|ipfs-node|phpmyadmin-coc"
echo ""

# Port bindings
echo -e "${YELLOW}Port Bindings:${NC}"
sudo netstat -tulpn | grep -E "3306|5001|8080|8081|5000"
echo ""

echo -e "${YELLOW}Next Steps:${NC}"
echo "1. If MySQL is working but phpMyAdmin fails, restart phpMyAdmin"
echo "2. If IPFS daemon works but API fails, check firewall"
echo "3. If webapp is not running, use ./launch-webapp.sh"
echo ""
