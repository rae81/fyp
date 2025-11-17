#!/bin/bash
#
# Fix CouchDB DNS and Create Cold Channel
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

echo ""
echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║           Fix CouchDB DNS & Create Cold Channel               ║${NC}"
echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================================
# STEP 1: Check and restart CouchDB containers
# ============================================================================

echo -e "${CYAN}[1/4] Checking CouchDB containers...${NC}"
echo ""

for db in couchdb0 couchdb1 couchdb2; do
    if docker ps --format '{{.Names}}' | grep -q "^${db}$"; then
        echo -e "  ${GREEN}✓${NC} $db is running"
    else
        echo -e "  ${YELLOW}⚠${NC} $db not running, starting..."
        docker-compose -f docker-compose-full.yml up -d $db
    fi
done

echo ""
echo -e "${CYAN}Waiting for CouchDB to initialize (10s)...${NC}"
sleep 10

# ============================================================================
# STEP 2: Restart hot blockchain peers to refresh DNS
# ============================================================================

echo ""
echo -e "${CYAN}[2/4] Restarting hot blockchain peers to refresh DNS cache...${NC}"
echo ""

docker-compose -f docker-compose-full.yml restart peer0.lawenforcement.hot.coc.com peer0.forensiclab.hot.coc.com

echo -e "${YELLOW}Waiting for peers to reconnect to CouchDB (15s)...${NC}"
sleep 15

# Check peer logs for CouchDB connection
echo -e "${YELLOW}Checking if peers can connect to CouchDB:${NC}"
if docker logs peer0.lawenforcement.hot.coc.com 2>&1 | tail -20 | grep -qi "couchdb.*connected\|created CouchDB"; then
    echo -e "  ${GREEN}✓${NC} LawEnforcement peer connected to CouchDB"
else
    echo -e "  ${YELLOW}⚠${NC} Check LawEnforcement peer logs for CouchDB status"
fi

# ============================================================================
# STEP 3: Create coldchannel
# ============================================================================

echo ""
echo -e "${CYAN}[3/4] Creating coldchannel...${NC}"
echo ""

# Check if cold-blockchain directory and configtx.yaml exist
if [ ! -f "cold-blockchain/configtx.yaml" ]; then
    echo -e "${RED}✗ cold-blockchain/configtx.yaml not found${NC}"
    echo "Cannot create coldchannel without configuration file"
    exit 1
fi

# Generate genesis block for cold channel
echo -e "${YELLOW}Generating coldchannel genesis block...${NC}"
docker run --rm -v $(pwd):/work -w /work/cold-blockchain \
    hyperledger/fabric-tools:2.5 \
    sh -c "cd /work && configtxgen -configPath cold-blockchain -profile ColdChainGenesis \
    -outputBlock cold-blockchain/channel-artifacts/coldchannel.block -channelID coldchannel"

if [ $? -eq 0 ]; then
    echo -e "  ${GREEN}✓${NC} Genesis block generated"
else
    echo -e "  ${RED}✗${NC} Failed to generate genesis block"
    exit 1
fi

# Join orderer to coldchannel
echo -e "${YELLOW}Joining orderer to coldchannel...${NC}"
docker exec cli-cold osnadmin channel join \
    --channelID coldchannel \
    --config-block /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/coldchannel.block \
    -o orderer.cold.coc.com:7153 \
    --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/ca.crt \
    --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/server.crt \
    --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/server.key

if [ $? -eq 0 ]; then
    echo -e "  ${GREEN}✓${NC} Orderer joined coldchannel"
else
    echo -e "  ${YELLOW}⚠${NC} Orderer join may have failed (check if already joined)"
fi

echo -e "${YELLOW}Waiting for orderer to activate channel (30s)...${NC}"
sleep 30

# Join auditor peer to coldchannel
echo -e "${YELLOW}Joining auditor peer to coldchannel...${NC}"
docker exec cli-cold peer channel fetch 0 /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/coldchannel_genesis.block \
    -o orderer.cold.coc.com:7150 \
    --ordererTLSHostnameOverride orderer.cold.coc.com \
    -c coldchannel \
    --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/ca.crt

docker exec cli-cold peer channel join \
    -b /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/coldchannel_genesis.block

if [ $? -eq 0 ]; then
    echo -e "  ${GREEN}✓${NC} Auditor peer joined coldchannel"
else
    echo -e "  ${RED}✗${NC} Failed to join auditor peer"
fi

# ============================================================================
# STEP 4: Verify channels
# ============================================================================

echo ""
echo -e "${CYAN}[4/4] Verifying channels...${NC}"
echo ""

echo -e "${YELLOW}Hot blockchain channels:${NC}"
docker exec cli peer channel list 2>&1 | grep "Channels peers has joined" -A 10

echo ""
echo -e "${YELLOW}Cold blockchain channels:${NC}"
docker exec cli-cold peer channel list 2>&1 | grep "Channels peers has joined" -A 10

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                        Setup Complete!                         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${CYAN}Next Steps:${NC}"
echo "  1. Retry chaincode deployment:"
echo "     ${MAGENTA}./deploy-chaincode.sh${NC}"
echo ""
echo "  2. If CouchDB DNS still fails, check logs:"
echo "     ${MAGENTA}docker logs peer0.lawenforcement.hot.coc.com 2>&1 | grep -i couchdb${NC}"
echo ""
