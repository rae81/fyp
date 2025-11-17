#!/bin/bash
#
# DNS Connectivity Test Script
# Tests DNS resolution from CLI container to all blockchain components
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           DNS Connectivity Test for DFIR System               ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if CLI container exists and is running
echo -e "${CYAN}[1] Checking CLI container status...${NC}"
if ! docker ps --format '{{.Names}}' | grep -q "^cli$"; then
    echo -e "  ${RED}✗ CLI container not running${NC}"
    echo ""
    echo -e "${YELLOW}Starting CLI container...${NC}"
    docker-compose -f docker-compose-full.yml up -d cli
    sleep 5
else
    echo -e "  ${GREEN}✓ CLI container is running${NC}"
fi

# Check CLI network membership
echo ""
echo -e "${CYAN}[2] Checking CLI network membership...${NC}"
NETWORKS=$(docker inspect cli --format='{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}')
echo -e "  Networks: ${YELLOW}$NETWORKS${NC}"

if echo "$NETWORKS" | grep -q "fyp_dfir-network"; then
    echo -e "  ${GREEN}✓ CLI is on fyp_dfir-network${NC}"
else
    echo -e "  ${RED}✗ CLI is NOT on fyp_dfir-network${NC}"
    echo -e "  ${YELLOW}Connecting to network...${NC}"
    docker network connect fyp_dfir-network cli 2>/dev/null || echo "  Already connected or failed"
fi

# Test DNS resolution for each component
echo ""
echo -e "${CYAN}[3] Testing DNS resolution from CLI container...${NC}"
echo ""

test_host() {
    local hostname=$1
    local description=$2

    if docker exec cli getent hosts "$hostname" > /dev/null 2>&1; then
        IP=$(docker exec cli getent hosts "$hostname" | awk '{print $1}')
        echo -e "  ${GREEN}✓${NC} $description ($hostname) -> $IP"
        return 0
    else
        echo -e "  ${RED}✗${NC} $description ($hostname) -> FAILED"
        return 1
    fi
}

# Test Hot blockchain components
echo -e "${YELLOW}Hot Blockchain:${NC}"
test_host "orderer.hot.coc.com" "Hot Orderer"
test_host "peer0.lawenforcement.hot.coc.com" "LawEnforcement Peer"
test_host "peer0.forensiclab.hot.coc.com" "ForensicLab Peer"

echo ""
echo -e "${YELLOW}Cold Blockchain:${NC}"
test_host "orderer.cold.coc.com" "Cold Orderer"
test_host "peer0.auditor.cold.coc.com" "Auditor Peer"

echo ""
echo -e "${YELLOW}CAs:${NC}"
test_host "ca.lawenforcement.hot.coc.com" "LawEnforcement CA"
test_host "ca.forensiclab.hot.coc.com" "ForensicLab CA"
test_host "ca.auditor.cold.coc.com" "Auditor CA"
test_host "ca.court.coc.com" "Court CA"
test_host "ca.orderer.hot.coc.com" "Hot Orderer CA"
test_host "ca.orderer.cold.coc.com" "Cold Orderer CA"

echo ""
echo -e "${YELLOW}Databases:${NC}"
test_host "couchdb0" "CouchDB0"
test_host "couchdb1" "CouchDB1"
test_host "couchdb2" "CouchDB2"

echo ""
echo -e "${YELLOW}Storage:${NC}"
test_host "ipfs.hot.coc.com" "IPFS Hot"
test_host "ipfs.cold.coc.com" "IPFS Cold"

echo ""
echo -e "${YELLOW}Enclave:${NC}"
test_host "enclave" "SGX Enclave"

# Test connectivity (ping alternative - check port)
echo ""
echo -e "${CYAN}[4] Testing network connectivity...${NC}"
echo ""

test_port() {
    local hostname=$1
    local port=$2
    local description=$3

    if docker exec cli timeout 2 sh -c "cat < /dev/null > /dev/tcp/$hostname/$port" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $description ($hostname:$port) - REACHABLE"
        return 0
    else
        echo -e "  ${RED}✗${NC} $description ($hostname:$port) - UNREACHABLE"
        return 1
    fi
}

echo -e "${YELLOW}Orderer Admin Endpoints:${NC}"
test_port "orderer.hot.coc.com" "7053" "Hot Orderer Admin"
test_port "orderer.cold.coc.com" "7153" "Cold Orderer Admin"

echo ""
echo -e "${YELLOW}Peer Endpoints:${NC}"
test_port "peer0.lawenforcement.hot.coc.com" "7051" "LawEnforcement Peer"
test_port "peer0.forensiclab.hot.coc.com" "8051" "ForensicLab Peer"
test_port "peer0.auditor.cold.coc.com" "9051" "Auditor Peer"

# Check Docker DNS server
echo ""
echo -e "${CYAN}[5] Checking Docker DNS configuration...${NC}"
DNS_SERVER=$(docker exec cli cat /etc/resolv.conf | grep nameserver | awk '{print $2}')
echo -e "  DNS Server: ${YELLOW}$DNS_SERVER${NC}"

if [ "$DNS_SERVER" = "127.0.0.11" ]; then
    echo -e "  ${GREEN}✓${NC} Using Docker's embedded DNS server"
else
    echo -e "  ${YELLOW}⚠${NC} Not using expected Docker DNS (127.0.0.11)"
fi

# Summary
echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                        Test Summary                            ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

if test_host "orderer.hot.coc.com" "Hot Orderer" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ DNS Resolution: WORKING${NC}"
    echo ""
    echo -e "${GREEN}Your CLI can reach all blockchain components!${NC}"
    echo -e "You can now run: ${CYAN}./fix-hotchannel-endorsement.sh${NC}"
else
    echo -e "${RED}✗ DNS Resolution: FAILED${NC}"
    echo ""
    echo -e "${YELLOW}Troubleshooting Steps:${NC}"
    echo "  1. Restart CLI container:"
    echo "     ${CYAN}docker-compose -f docker-compose-full.yml restart cli${NC}"
    echo ""
    echo "  2. Check all containers are running:"
    echo "     ${CYAN}docker-compose -f docker-compose-full.yml ps${NC}"
    echo ""
    echo "  3. Check Docker network:"
    echo "     ${CYAN}docker network inspect fyp_dfir-network${NC}"
    echo ""
    echo "  4. Full restart:"
    echo "     ${CYAN}docker-compose -f docker-compose-full.yml down${NC}"
    echo "     ${CYAN}docker-compose -f docker-compose-full.yml up -d${NC}"
fi

echo ""
