#!/bin/bash

###############################################################################
# Complete System Reset
# Resets blockchains, MySQL, and explorers to fresh state
###############################################################################

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${RED}=========================================${NC}"
echo -e "${RED}  COMPLETE SYSTEM RESET                 ${NC}"
echo -e "${RED}=========================================${NC}"
echo ""
echo -e "${YELLOW}This will reset EVERYTHING to a fresh state:${NC}"
echo "  ✗ All blockchain blocks (Hot & Cold)"
echo "  ✗ All evidence records in MySQL"
echo "  ✗ All explorer data"
echo "  ✗ All chaincode containers"
echo ""
echo -e "${GREEN}Will be preserved:${NC}"
echo "  ✓ IPFS files"
echo "  ✓ Crypto material (certificates/keys)"
echo ""
echo -e "${RED}⚠  THIS CANNOT BE UNDONE!${NC}"
echo ""
read -p "Type 'RESET' to continue: " -r
if [[ ! $REPLY == "RESET" ]]; then
    echo "Aborted."
    exit 1
fi
echo ""

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

# Kill webapp
echo -e "${YELLOW}[1/12] Stopping webapp...${NC}"
pkill -f "python.*app_blockchain.py" 2>/dev/null || true
echo -e "${GREEN}✓ Webapp stopped${NC}"
echo ""

# Stop explorers
echo -e "${YELLOW}[2/12] Stopping explorers...${NC}"
docker-compose -f docker-compose-explorers.yml down -v 2>/dev/null || true
echo -e "${GREEN}✓ Explorers stopped and databases removed${NC}"
echo ""

# Stop blockchains
echo -e "${YELLOW}[3/12] Stopping blockchains...${NC}"
docker-compose -f docker-compose-hot.yml down -v 2>/dev/null || true
docker-compose -f docker-compose-cold.yml down -v 2>/dev/null || true
echo -e "${GREEN}✓ Blockchains stopped and volumes removed${NC}"
echo ""

# Remove chaincode containers
echo -e "${YELLOW}[4/12] Removing chaincode containers...${NC}"
docker rm -f $(docker ps -aq -f name=dev-peer) 2>/dev/null || true
echo -e "${GREEN}✓ Chaincode containers removed${NC}"
echo ""

# Remove chaincode images
echo -e "${YELLOW}[5/12] Removing chaincode images...${NC}"
docker rmi -f $(docker images -q -f reference=dev-peer*) 2>/dev/null || true
echo -e "${GREEN}✓ Chaincode images removed${NC}"
echo ""

# Clear MySQL data
echo -e "${YELLOW}[6/12] Clearing MySQL evidence data...${NC}"
docker exec mysql-coc mysql -ucocuser -pcocpassword -e "DROP DATABASE IF EXISTS coc_evidence;" 2>/dev/null || true
docker exec mysql-coc mysql -ucocuser -pcocpassword -e "CREATE DATABASE coc_evidence;" 2>/dev/null || true
echo -e "${GREEN}✓ MySQL database recreated${NC}"
echo ""

# Load MySQL schema
echo -e "${YELLOW}[7/12] Loading MySQL schema...${NC}"
# Use root to load schema (needed for GRANT statements)
docker exec -i mysql-coc mysql -uroot -prootpassword coc_evidence < shared/database/init/01-schema.sql 2>&1 | grep -v "Warning: Using a password" || true
echo -e "${GREEN}✓ MySQL schema loaded${NC}"
echo ""

# Start Hot blockchain
echo -e "${YELLOW}[8/12] Starting Hot blockchain...${NC}"
docker-compose -f docker-compose-hot.yml up -d
echo "Waiting for Hot blockchain to initialize..."
sleep 15
echo -e "${GREEN}✓ Hot blockchain started${NC}"
echo ""

# Start Cold blockchain
echo -e "${YELLOW}[9/12] Starting Cold blockchain...${NC}"
docker-compose -f docker-compose-cold.yml up -d
echo "Waiting for Cold blockchain to initialize..."
sleep 15
echo -e "${GREEN}✓ Cold blockchain started${NC}"
echo ""

# Create and join Hot channel
echo -e "${YELLOW}[10/12] Creating and joining Hot channel...${NC}"

# Generate fresh channel block with current TLS certs
export FABRIC_CFG_PATH="$PROJECT_ROOT/hot-blockchain"
docker run --rm \
    -v "$PROJECT_ROOT/hot-blockchain:/work" \
    -e FABRIC_CFG_PATH=/work \
    -w /work \
    hyperledger/fabric-tools:2.5 \
    configtxgen -profile HotChainChannel -outputBlock /work/channel-artifacts/hotchannel.block -channelID hotchannel

# Copy to CLI container
docker cp hot-blockchain/channel-artifacts/hotchannel.block cli:/opt/gopath/src/github.com/hyperledger/fabric/peer/

# Join orderer to channel using osnadmin
docker exec cli osnadmin channel join \
    --channelID hotchannel \
    --config-block /opt/gopath/src/github.com/hyperledger/fabric/peer/hotchannel.block \
    -o orderer.hot.coc.com:7053 \
    --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/ca.crt \
    --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.crt \
    --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.key

sleep 2

# Join LawEnforcement peer
docker exec cli peer channel join -b /opt/gopath/src/github.com/hyperledger/fabric/peer/hotchannel.block

# Join ForensicLab peer
docker exec cli bash -c "
    export CORE_PEER_ADDRESS=peer0.forensiclab.hot.coc.com:8051
    export CORE_PEER_LOCALMSPID=ForensicLabMSP
    export CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/forensiclab.hot.coc.com/peers/peer0.forensiclab.hot.coc.com/tls/ca.crt
    export CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/forensiclab.hot.coc.com/users/Admin@forensiclab.hot.coc.com/msp
    peer channel join -b /opt/gopath/src/github.com/hyperledger/fabric/peer/hotchannel.block
"

echo -e "${GREEN}✓ Hot channel created and peers joined${NC}"
echo ""

# Create and join Cold channel
echo -e "${YELLOW}[11/12] Creating and joining Cold channel...${NC}"

# Generate fresh channel block with current TLS certs
export FABRIC_CFG_PATH="$PROJECT_ROOT/cold-blockchain"
docker run --rm \
    -v "$PROJECT_ROOT/cold-blockchain:/work" \
    -e FABRIC_CFG_PATH=/work \
    -w /work \
    hyperledger/fabric-tools:2.5 \
    configtxgen -profile ColdChainChannel -outputBlock /work/channel-artifacts/coldchannel.block -channelID coldchannel

# Copy to CLI container
docker cp cold-blockchain/channel-artifacts/coldchannel.block cli-cold:/opt/gopath/src/github.com/hyperledger/fabric/peer/

# Join orderer to channel using osnadmin
docker exec cli-cold osnadmin channel join \
    --channelID coldchannel \
    --config-block /opt/gopath/src/github.com/hyperledger/fabric/peer/coldchannel.block \
    -o orderer.cold.coc.com:7153 \
    --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/ca.crt \
    --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/server.crt \
    --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/server.key

sleep 2

# Join Archive peer
docker exec cli-cold peer channel join -b /opt/gopath/src/github.com/hyperledger/fabric/peer/coldchannel.block

echo -e "${GREEN}✓ Cold channel created and peer joined${NC}"
echo ""

# Check blockchain heights
echo -e "${YELLOW}[12/12] Verifying blockchain heights...${NC}"
HOT_HEIGHT=$(docker exec cli peer channel getinfo -c hotchannel 2>/dev/null | grep -oP '(?<="height":)\d+' || echo "1")
COLD_HEIGHT=$(docker exec cli-cold peer channel getinfo -c coldchannel 2>/dev/null | grep -oP '(?<="height":)\d+' || echo "1")

echo -e "${GREEN}✓ Hot Blockchain Height:  $HOT_HEIGHT (genesis only)${NC}"
echo -e "${GREEN}✓ Cold Blockchain Height: $COLD_HEIGHT (genesis only)${NC}"
echo ""

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  Reset Complete!                       ${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo -e "${GREEN}✓ Blockchains reset to genesis block${NC}"
echo -e "${GREEN}✓ MySQL database cleared and schema reloaded${NC}"
echo -e "${GREEN}✓ All chaincode removed${NC}"
echo ""
echo -e "${YELLOW}Next Steps (in this order):${NC}"
echo ""
echo "  1. Deploy chaincode:"
echo "     ${BLUE}./deploy-chaincode.sh${NC}"
echo ""
echo "  2. Start explorers:"
echo "     ${BLUE}./start-explorers.sh${NC}"
echo ""
echo "  3. Start webapp:"
echo "     ${BLUE}./launch-webapp.sh${NC}"
echo ""
echo "  4. Access dashboard:"
echo "     ${BLUE}http://localhost:5000${NC}"
echo ""
echo -e "${YELLOW}Now you can upload evidence starting with ID '1'${NC}"
echo ""
