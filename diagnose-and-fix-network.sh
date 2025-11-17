#!/bin/bash
#
# Comprehensive Network Diagnostic and Fix Script
# ================================================
# Diagnoses and fixes Docker network issues for the dual blockchain system
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

echo ""
echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║        Network Diagnostics & Fix for DFIR System              ║${NC}"
echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================================
# PHASE 1: DETECT NETWORK NAME
# ============================================================================

echo -e "${CYAN}[1/7] Detecting Docker Compose network...${NC}"

# Check for active networks
NETWORKS=$(docker network ls --filter "name=dfir" --format "{{.Name}}" 2>/dev/null)

if [ -z "$NETWORKS" ]; then
    echo -e "  ${YELLOW}⚠${NC} No DFIR network found!"
    echo -e "  ${CYAN}Creating network from docker-compose...${NC}"
    docker-compose -f docker-compose-full.yml up --no-start 2>/dev/null
    NETWORKS=$(docker network ls --filter "name=dfir" --format "{{.Name}}" 2>/dev/null)
fi

# Select the first network found (should be fyp_dfir-network)
NETWORK_NAME=$(echo "$NETWORKS" | head -1)

echo -e "  ${GREEN}✓${NC} Network detected: ${YELLOW}$NETWORK_NAME${NC}"

# ============================================================================
# PHASE 2: VERIFY COUCHDB CONTAINERS
# ============================================================================

echo -e "${CYAN}[2/7] Checking CouchDB containers...${NC}"

MISSING_COUCHDB=0

for DB in couchdb0 couchdb1 couchdb2; do
    if docker ps -a --filter "name=$DB" --format "{{.Names}}" | grep -q "^$DB$"; then
        STATUS=$(docker inspect -f '{{.State.Status}}' $DB)
        if [ "$STATUS" = "running" ]; then
            echo -e "  ${GREEN}✓${NC} $DB is running"
        else
            echo -e "  ${YELLOW}⚠${NC} $DB exists but not running (status: $STATUS)"
            MISSING_COUCHDB=1
        fi
    else
        echo -e "  ${RED}✗${NC} $DB not found"
        MISSING_COUCHDB=1
    fi
done

if [ $MISSING_COUCHDB -eq 1 ]; then
    echo -e "  ${CYAN}⚡${NC} Starting CouchDB containers..."
    docker-compose -f docker-compose-full.yml up -d couchdb0 couchdb1 couchdb2

    echo -e "  ${YELLOW}Waiting for CouchDB to initialize (15s)...${NC}"
    sleep 15

    # Verify they're running
    for DB in couchdb0 couchdb1 couchdb2; do
        if docker ps --filter "name=$DB" --filter "status=running" --format "{{.Names}}" | grep -q "$DB"; then
            echo -e "  ${GREEN}✓${NC} $DB now running"
        else
            echo -e "  ${RED}✗${NC} $DB failed to start"
        fi
    done
fi

# ============================================================================
# PHASE 3: VERIFY NETWORK CONNECTIVITY
# ============================================================================

echo -e "${CYAN}[3/7] Verifying network connectivity...${NC}"

# Check if CouchDB containers are on the network
for DB in couchdb0 couchdb1 couchdb2; do
    if docker network inspect $NETWORK_NAME 2>/dev/null | grep -q "\"Name\": \"$DB\""; then
        IP=$(docker inspect -f "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" $DB)
        echo -e "  ${GREEN}✓${NC} $DB connected to network (IP: $IP)"
    else
        echo -e "  ${YELLOW}⚡${NC} Connecting $DB to $NETWORK_NAME..."
        docker network connect $NETWORK_NAME $DB 2>/dev/null || {
            echo -e "  ${YELLOW}Note:${NC} $DB may already be connected"
        }
    fi
done

# ============================================================================
# PHASE 4: TEST DNS RESOLUTION
# ============================================================================

echo -e "${CYAN}[4/7] Testing DNS resolution...${NC}"

# Test from within the network using a running container
TEST_CONTAINER=""

# Try to find a running container to test from
for CONTAINER in "peer0.lawenforcement.hot.coc.com" "peer0.forensiclab.hot.coc.com" "sgx-enclave"; do
    if docker ps --filter "name=$CONTAINER" --filter "status=running" --format "{{.Names}}" | grep -q "$CONTAINER"; then
        TEST_CONTAINER=$CONTAINER
        break
    fi
done

if [ -n "$TEST_CONTAINER" ]; then
    echo -e "  Testing from: ${YELLOW}$TEST_CONTAINER${NC}"

    for DB in couchdb0 couchdb1 couchdb2; do
        if docker exec $TEST_CONTAINER getent hosts $DB > /dev/null 2>&1; then
            IP=$(docker exec $TEST_CONTAINER getent hosts $DB | awk '{print $1}')
            echo -e "  ${GREEN}✓${NC} Can resolve $DB → $IP"
        else
            echo -e "  ${RED}✗${NC} Cannot resolve $DB"
        fi
    done

    # Test HTTP connectivity
    echo ""
    echo -e "  Testing HTTP connectivity:"
    if docker exec $TEST_CONTAINER sh -c "command -v curl" > /dev/null 2>&1; then
        for DB in couchdb0 couchdb1 couchdb2; do
            if docker exec $TEST_CONTAINER curl -s --connect-timeout 3 http://$DB:5984 > /dev/null 2>&1; then
                echo -e "  ${GREEN}✓${NC} HTTP connection to $DB:5984 successful"
            else
                echo -e "  ${RED}✗${NC} HTTP connection to $DB:5984 failed"
            fi
        done
    else
        echo -e "  ${YELLOW}⚠${NC} curl not available in test container, skipping HTTP test"
    fi
else
    echo -e "  ${YELLOW}⚠${NC} No running container found to test DNS from"
fi

# ============================================================================
# PHASE 5: CHECK PEER CONTAINERS
# ============================================================================

echo -e "${CYAN}[5/7] Checking peer containers...${NC}"

PEER_ISSUES=0

for PEER in "peer0.lawenforcement.hot.coc.com" "peer0.forensiclab.hot.coc.com" "peer0.auditor.cold.coc.com"; do
    if docker ps --filter "name=$PEER" --filter "status=running" --format "{{.Names}}" | grep -q "^$PEER$"; then
        echo -e "  ${GREEN}✓${NC} $PEER is running"

        # Check for CouchDB errors in logs
        if docker logs $PEER 2>&1 | tail -20 | grep -qi "couchdb.*error\|no such host"; then
            echo -e "    ${YELLOW}⚠${NC} CouchDB connection errors detected in logs"
            PEER_ISSUES=1
        fi
    else
        if docker ps -a --filter "name=$PEER" --format "{{.Names}}" | grep -q "^$PEER$"; then
            STATUS=$(docker inspect -f '{{.State.Status}}' $PEER)
            echo -e "  ${YELLOW}⚠${NC} $PEER exists but not running (status: $STATUS)"
        else
            echo -e "  ${RED}✗${NC} $PEER not found"
        fi
        PEER_ISSUES=1
    fi
done

# ============================================================================
# PHASE 6: RESTART PEERS IF NEEDED
# ============================================================================

if [ $PEER_ISSUES -eq 1 ]; then
    echo -e "${CYAN}[6/7] Restarting peers to fix connectivity...${NC}"

    for PEER in "peer0.lawenforcement.hot.coc.com" "peer0.forensiclab.hot.coc.com" "peer0.auditor.cold.coc.com"; do
        if docker ps -a --filter "name=$PEER" --format "{{.Names}}" | grep -q "^$PEER$"; then
            echo -e "  ${CYAN}⚡${NC} Restarting $PEER..."
            docker restart $PEER > /dev/null 2>&1 || {
                echo -e "    ${YELLOW}⚠${NC} Restart failed, trying to start..."
                docker start $PEER > /dev/null 2>&1
            }
        fi
    done

    echo -e "  ${YELLOW}Waiting for peers to reconnect (20s)...${NC}"
    sleep 20
else
    echo -e "${CYAN}[6/7] Peers look healthy, skipping restart${NC}"
fi

# ============================================================================
# PHASE 7: FINAL VERIFICATION
# ============================================================================

echo -e "${CYAN}[7/7] Final verification...${NC}"
echo ""

# Show network topology
echo -e "${YELLOW}Network Topology ($NETWORK_NAME):${NC}"
docker network inspect $NETWORK_NAME --format '{{range $key, $value := .Containers}}  {{printf "%-40s" $value.Name}} → {{$value.IPv4Address}}{{"\n"}}{{end}}' | sort

echo ""

# Check peer logs for recent errors
echo -e "${YELLOW}Recent Peer Status:${NC}"
for PEER in "peer0.lawenforcement.hot.coc.com" "peer0.forensiclab.hot.coc.com" "peer0.auditor.cold.coc.com"; do
    if docker ps --filter "name=$PEER" --filter "status=running" --format "{{.Names}}" | grep -q "^$PEER$"; then
        # Check last 10 lines for errors
        if docker logs $PEER 2>&1 | tail -10 | grep -qi "error\|fatal\|no such host"; then
            echo -e "  ${RED}✗${NC} $PEER has recent errors"
            echo -e "    ${YELLOW}Last error:${NC}"
            docker logs $PEER 2>&1 | tail -10 | grep -i "error\|fatal\|no such host" | tail -1 | sed 's/^/    /'
        else
            echo -e "  ${GREEN}✓${NC} $PEER looks healthy"
        fi
    else
        echo -e "  ${RED}✗${NC} $PEER not running"
    fi
done

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                  Diagnostics Complete                          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${CYAN}Verification Commands:${NC}"
echo ""
echo "1. Check specific peer logs:"
echo "   docker logs peer0.lawenforcement.hot.coc.com 2>&1 | tail -30"
echo ""
echo "2. Test CouchDB from inside peer:"
echo "   docker exec peer0.lawenforcement.hot.coc.com curl http://couchdb0:5984"
echo ""
echo "3. Check CouchDB directly:"
echo "   curl http://localhost:5984"
echo ""
echo "4. View all container statuses:"
echo "   docker ps --format 'table {{.Names}}\t{{.Status}}'"
echo ""
echo "5. If peers still have issues, check detailed logs:"
echo "   docker logs peer0.lawenforcement.hot.coc.com 2>&1 | grep -i couchdb"
echo ""
