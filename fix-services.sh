#!/bin/bash

###############################################################################
# Service Fix Script
# Fix phpMyAdmin, IPFS, and start webapp
###############################################################################

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  Fixing Services                       ${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# 1. Fix phpMyAdmin - restart the container
echo -e "${YELLOW}[1/4] Restarting phpMyAdmin...${NC}"
docker restart phpmyadmin-coc
sleep 3
echo -e "${GREEN}✓ phpMyAdmin restarted${NC}"
echo ""

# 2. Verify MySQL is accessible
echo -e "${YELLOW}[2/4] Testing MySQL connection...${NC}"
docker exec mysql-coc mysql -ucocuser -pcocpassword -e "SHOW DATABASES;" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ MySQL is accessible${NC}"
else
    echo -e "${RED}✗ MySQL connection failed${NC}"
    echo "Restarting MySQL..."
    docker restart mysql-coc
    sleep 5
fi
echo ""

# 3. Test IPFS
echo -e "${YELLOW}[3/4] Testing IPFS...${NC}"
docker exec ipfs-node ipfs id > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ IPFS daemon is running${NC}"

    # Test API endpoint
    IPFS_VERSION=$(curl -s -X POST http://localhost:5001/api/v0/version 2>&1)
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ IPFS API is accessible${NC}"
    else
        echo -e "${YELLOW}⚠  IPFS API may have connectivity issues${NC}"
    fi
else
    echo -e "${RED}✗ IPFS daemon has issues${NC}"
    echo "Restarting IPFS..."
    docker restart ipfs-node
    sleep 5
fi
echo ""

# 4. Start webapp
echo -e "${YELLOW}[4/4] Starting webapp...${NC}"

# Kill any existing webapp process
pkill -f "python.*app_blockchain.py" 2>/dev/null

# Change to webapp directory
cd "$(dirname "$0")/webapp"

# Install dependencies if needed
if ! python3 -c "import flask" 2>/dev/null; then
    echo "Installing Python packages..."
    pip3 install flask mysql-connector-python requests --user
fi

# Start webapp
nohup python3 app_blockchain.py > flask.log 2>&1 &
WEBAPP_PID=$!

sleep 5

# Check if running
if curl -s http://localhost:5000/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Webapp is running (PID: $WEBAPP_PID)${NC}"
else
    echo -e "${RED}✗ Webapp failed to start${NC}"
    echo "Check logs: tail -f webapp/flask.log"
fi
echo ""

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  Service Status                        ${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Test all services
echo -e "${YELLOW}Testing Services:${NC}"
echo ""

# phpMyAdmin
echo -n "  phpMyAdmin (8081):    "
if curl -s http://localhost:8081 > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Working${NC}"
else
    echo -e "${RED}✗ Not responding${NC}"
fi

# IPFS Gateway
echo -n "  IPFS Gateway (8080):  "
if curl -s http://localhost:8080/ipfs/QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Working${NC}"
else
    echo -e "${RED}✗ Not responding${NC}"
fi

# IPFS API
echo -n "  IPFS API (5001):      "
if curl -s -X POST http://localhost:5001/api/v0/version > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Working${NC}"
else
    echo -e "${RED}✗ Not responding${NC}"
fi

# MySQL
echo -n "  MySQL (3306):         "
if docker exec mysql-coc mysql -ucocuser -pcocpassword -e "SELECT 1" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Working${NC}"
else
    echo -e "${RED}✗ Not responding${NC}"
fi

# Webapp
echo -n "  Webapp (5000):        "
if curl -s http://localhost:5000/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Working${NC}"
else
    echo -e "${RED}✗ Not responding${NC}"
fi

echo ""
echo -e "${BLUE}=========================================${NC}"
echo ""

echo -e "${GREEN}Service URLs:${NC}"
echo "  📊 Main Dashboard:     http://localhost:5000"
echo "  💾 phpMyAdmin:         http://localhost:8081 (cocuser/cocpassword)"
echo "  📁 IPFS Gateway:       http://localhost:8080"
echo "  🔥 Hot Explorer:       http://localhost:8090 (exploreradmin/exploreradminpw)"
echo "  ❄️  Cold Explorer:      http://localhost:8091 (exploreradmin/exploreradminpw)"
echo ""
echo -e "${YELLOW}If any service is not working, check Docker logs:${NC}"
echo "  docker logs phpmyadmin-coc"
echo "  docker logs ipfs-node"
echo "  docker logs mysql-coc"
echo "  tail -f webapp/flask.log"
echo ""
