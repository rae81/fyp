#!/bin/bash
#
# Fix CouchDB DNS Resolution Issue
# ==================================
# This script ensures all containers are on the same Docker network
# and peers can resolve CouchDB hostnames.
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}   Fixing CouchDB DNS Resolution       ${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Check which network is being used
NETWORK_NAME=$(docker network ls | grep -E "dfir|coc" | awk '{print $2}' | head -1)

if [ -z "$NETWORK_NAME" ]; then
    echo -e "${YELLOW}No DFIR network found. Checking docker-compose...${NC}"
    NETWORK_NAME="fyp_dfir-network"
fi

echo -e "${CYAN}Using network: $NETWORK_NAME${NC}"
echo ""

# Step 1: Check which containers are on the network
echo -e "${CYAN}Step 1: Inspecting network...${NC}"
docker network inspect $NETWORK_NAME > /dev/null 2>&1 || {
    echo -e "${RED}Network $NETWORK_NAME not found!${NC}"
    echo -e "${YELLOW}Creating network...${NC}"
    docker network create $NETWORK_NAME
}

# Step 2: Check if CouchDB containers are running
echo -e "${CYAN}Step 2: Checking CouchDB containers...${NC}"
COUCHDB_CONTAINERS=$(docker ps -a --filter "name=couchdb" --format "{{.Names}}")

if [ -z "$COUCHDB_CONTAINERS" ]; then
    echo -e "${RED}No CouchDB containers found!${NC}"
    echo -e "${YELLOW}Starting CouchDB containers...${NC}"
    docker-compose -f docker-compose-full.yml up -d couchdb0 couchdb1 couchdb2
    sleep 10
fi

# Step 3: Ensure CouchDB containers are on the network
echo -e "${CYAN}Step 3: Connecting CouchDB to network...${NC}"
for COUCHDB in couchdb0 couchdb1 couchdb2; do
    if docker ps --filter "name=$COUCHDB" --format "{{.Names}}" | grep -q "$COUCHDB"; then
        # Check if already connected
        if docker network inspect $NETWORK_NAME | grep -q "$COUCHDB"; then
            echo -e "  ${GREEN}✓${NC} $COUCHDB already connected"
        else
            echo -e "  ${YELLOW}⚡${NC} Connecting $COUCHDB to $NETWORK_NAME"
            docker network connect $NETWORK_NAME $COUCHDB 2>/dev/null || echo -e "  ${YELLOW}Note: $COUCHDB may already be connected${NC}"
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} $COUCHDB not running"
    fi
done

# Step 4: Verify DNS resolution from a peer
echo ""
echo -e "${CYAN}Step 4: Testing DNS resolution...${NC}"
PEER_CONTAINER=$(docker ps --filter "name=peer0.lawenforcement" --format "{{.Names}}" | head -1)

if [ -n "$PEER_CONTAINER" ]; then
    echo -e "  Testing from $PEER_CONTAINER..."
    for DB in couchdb0 couchdb1 couchdb2; do
        if docker exec $PEER_CONTAINER getent hosts $DB > /dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} Can resolve $DB"
        else
            echo -e "  ${RED}✗${NC} Cannot resolve $DB"
        fi
    done
else
    echo -e "  ${YELLOW}⚠${NC} No peer container running to test from"
fi

# Step 5: Restart peers to reconnect
echo ""
echo -e "${CYAN}Step 5: Restarting peers to apply changes...${NC}"
PEER_CONTAINERS=$(docker ps --filter "name=peer0" --format "{{.Names}}")

if [ -n "$PEER_CONTAINERS" ]; then
    for PEER in $PEER_CONTAINERS; do
        echo -e "  ${CYAN}⚡${NC} Restarting $PEER..."
        docker restart $PEER > /dev/null 2>&1
    done

    echo -e "${YELLOW}Waiting for peers to reconnect (15s)...${NC}"
    sleep 15
else
    echo -e "  ${YELLOW}⚠${NC} No peer containers running"
fi

# Step 6: Check logs for CouchDB connection
echo ""
echo -e "${CYAN}Step 6: Verifying CouchDB connections...${NC}"
PEER_CONTAINER=$(docker ps --filter "name=peer0.lawenforcement" --format "{{.Names}}" | head -1)

if [ -n "$PEER_CONTAINER" ]; then
    echo -e "  Checking logs for $PEER_CONTAINER..."
    if docker logs $PEER_CONTAINER 2>&1 | tail -30 | grep -i "couchdb" | grep -i "error\|no such host"; then
        echo -e "  ${RED}✗${NC} Still seeing CouchDB connection errors"
        echo ""
        echo -e "${YELLOW}Recent logs:${NC}"
        docker logs $PEER_CONTAINER 2>&1 | tail -10
    else
        echo -e "  ${GREEN}✓${NC} No recent CouchDB errors detected"
    fi
else
    echo -e "  ${YELLOW}⚠${NC} No peer container to check"
fi

# Step 7: Show network topology
echo ""
echo -e "${CYAN}Step 7: Network topology:${NC}"
docker network inspect $NETWORK_NAME --format '{{range $key, $value := .Containers}}  {{$value.Name}}: {{$value.IPv4Address}}{{"\n"}}{{end}}'

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   CouchDB DNS Fix Complete            ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo "  1. Check peer logs: docker logs peer0.lawenforcement.hot.coc.com 2>&1 | tail -30"
echo "  2. If still issues, check CouchDB is accessible: curl http://localhost:5984"
echo "  3. Verify CouchDB from inside peer: docker exec peer0.lawenforcement.hot.coc.com curl http://couchdb0:5984"
echo ""
