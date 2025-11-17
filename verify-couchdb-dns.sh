#!/bin/bash
#
# Verify CouchDB DNS Resolution from Peers
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║              CouchDB DNS Verification                          ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if CouchDB containers are running
echo -e "${YELLOW}[1/3] Checking CouchDB containers...${NC}"
echo ""

for db in couchdb0 couchdb1 couchdb2; do
    if docker ps --format '{{.Names}}' | grep -q "^${db}$"; then
        STATUS=$(docker ps --filter "name=^${db}$" --format "{{.Status}}")
        echo -e "  ${GREEN}✓${NC} $db is running: $STATUS"
    else
        echo -e "  ${RED}✗${NC} $db is NOT running"
    fi
done

# Check DNS resolution from peers
echo ""
echo -e "${YELLOW}[2/3] Testing DNS resolution from peers...${NC}"
echo ""

echo -e "${CYAN}From LawEnforcement peer:${NC}"
docker exec peer0.lawenforcement.hot.coc.com getent hosts couchdb0 2>&1 | head -1
if [ $? -eq 0 ]; then
    echo -e "  ${GREEN}✓${NC} Can resolve couchdb0"
else
    echo -e "  ${RED}✗${NC} Cannot resolve couchdb0"
fi

echo ""
echo -e "${CYAN}From ForensicLab peer:${NC}"
docker exec peer0.forensiclab.hot.coc.com getent hosts couchdb1 2>&1 | head -1
if [ $? -eq 0 ]; then
    echo -e "  ${GREEN}✓${NC} Can resolve couchdb1"
else
    echo -e "  ${RED}✗${NC} Cannot resolve couchdb1"
fi

echo ""
echo -e "${CYAN}From Auditor peer:${NC}"
docker exec peer0.auditor.cold.coc.com getent hosts couchdb2 2>&1 | head -1
if [ $? -eq 0 ]; then
    echo -e "  ${GREEN}✓${NC} Can resolve couchdb2"
else
    echo -e "  ${RED}✗${NC} Cannot resolve couchdb2"
fi

# Check CouchDB connectivity
echo ""
echo -e "${YELLOW}[3/3] Testing CouchDB HTTP connectivity...${NC}"
echo ""

for db in couchdb0 couchdb1 couchdb2; do
    IP=$(docker exec cli getent hosts $db 2>/dev/null | awk '{print $1}')
    if [ ! -z "$IP" ]; then
        if docker exec cli curl -s --max-time 2 http://$db:5984/ > /dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} $db ($IP) is reachable via HTTP"
        else
            echo -e "  ${YELLOW}⚠${NC} $db ($IP) DNS works but HTTP connection failed"
        fi
    else
        echo -e "  ${RED}✗${NC} $db - DNS resolution failed"
    fi
done

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""
