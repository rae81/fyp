#!/bin/bash

# Diagnostic script to check peer container status and logs
echo "==========================================="
echo "   Peer Container Diagnostics"
echo "==========================================="
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Checking all peer containers..."
echo ""

# Check Hot Blockchain Peers
echo -e "${YELLOW}Hot Blockchain Peers:${NC}"
echo "----------------------------------------"

for peer in peer0.lawenforcement.hot.coc.com peer0.forensiclab.hot.coc.com; do
    echo ""
    echo "=== $peer ==="
    STATUS=$(docker inspect -f '{{.State.Status}}' $peer 2>/dev/null)

    if [ -z "$STATUS" ]; then
        echo -e "${RED}Container does not exist${NC}"
    else
        echo "Status: $STATUS"

        if [ "$STATUS" != "running" ]; then
            echo ""
            echo "Exit Code: $(docker inspect -f '{{.State.ExitCode}}' $peer 2>/dev/null)"
            echo ""
            echo -e "${YELLOW}Last 30 lines of logs:${NC}"
            docker logs --tail 30 $peer 2>&1
        fi
    fi
done

echo ""
echo "----------------------------------------"
echo -e "${YELLOW}Cold Blockchain Peer:${NC}"
echo "----------------------------------------"

peer="peer0.archive.cold.coc.com"
echo ""
echo "=== $peer ==="
STATUS=$(docker inspect -f '{{.State.Status}}' $peer 2>/dev/null)

if [ -z "$STATUS" ]; then
    echo -e "${RED}Container does not exist${NC}"
else
    echo "Status: $STATUS"

    if [ "$STATUS" != "running" ]; then
        echo ""
        echo "Exit Code: $(docker inspect -f '{{.State.ExitCode}}' $peer 2>/dev/null)"
        echo ""
        echo -e "${YELLOW}Last 30 lines of logs:${NC}"
        docker logs --tail 30 $peer 2>&1
    fi
fi

echo ""
echo "==========================================="
echo "   Network Connectivity Check"
echo "==========================================="
echo ""

# Check if containers are on coc-network
echo "Containers on coc-network:"
docker network inspect coc-network -f '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null

echo ""
echo "==========================================="
echo "   Volume and File Check"
echo "==========================================="
echo ""

# Check if crypto-config exists
if [ -d "hot-blockchain/crypto-config" ]; then
    echo -e "${GREEN}✓${NC} hot-blockchain/crypto-config exists"
    echo "  Peer directories:"
    ls -d hot-blockchain/crypto-config/peerOrganizations/*/peers/* 2>/dev/null | head -5
else
    echo -e "${RED}✗${NC} hot-blockchain/crypto-config missing"
fi

if [ -d "cold-blockchain/crypto-config" ]; then
    echo -e "${GREEN}✓${NC} cold-blockchain/crypto-config exists"
    echo "  Peer directories:"
    ls -d cold-blockchain/crypto-config/peerOrganizations/*/peers/* 2>/dev/null | head -5
else
    echo -e "${RED}✗${NC} cold-blockchain/crypto-config missing"
fi

echo ""
echo "==========================================="
echo "   Running Containers"
echo "==========================================="
echo ""
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(NAME|peer|orderer|cli)"

echo ""
