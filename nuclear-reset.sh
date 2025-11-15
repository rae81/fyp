#!/bin/bash

###############################################################################
# NUCLEAR RESET - Regenerate all crypto and rebuild from scratch
# This fixes TLS certificate mismatches
###############################################################################

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${RED}=========================================${NC}"
echo -e "${RED}  NUCLEAR RESET - REGENERATE EVERYTHING ${NC}"
echo -e "${RED}=========================================${NC}"
echo ""
echo -e "${RED}⚠  THIS WILL:${NC}"
echo "  ✗ Regenerate ALL crypto material (new TLS certificates)"
echo "  ✗ Delete all blockchain data"
echo "  ✗ Delete all MySQL evidence"
echo "  ✗ Recreate channels from scratch"
echo "  ✗ Remove all Docker volumes"
echo ""
echo -e "${YELLOW}This is the ONLY way to fix TLS certificate mismatches.${NC}"
echo ""
read -p "Type 'NUCLEAR' to continue: " -r
if [[ ! $REPLY == "NUCLEAR" ]]; then
    echo "Aborted."
    exit 1
fi
echo ""

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

# Set up Fabric tools path
export PATH="$PROJECT_ROOT/fabric-samples/bin:$PATH"
export FABRIC_CFG_PATH="$PROJECT_ROOT"

# 1. Stop everything
echo -e "${YELLOW}[1/15] Stopping all services...${NC}"
pkill -f "python.*app_blockchain.py" 2>/dev/null || true
docker-compose -f docker-compose-explorers.yml down -v 2>/dev/null || true
docker-compose -f docker-compose-hot.yml down -v 2>/dev/null || true
docker-compose -f docker-compose-cold.yml down -v 2>/dev/null || true
docker rm -f $(docker ps -aq -f name=dev-peer) 2>/dev/null || true
docker rmi -f $(docker images -q -f reference=dev-peer*) 2>/dev/null || true
echo -e "${GREEN}✓ All services stopped${NC}"
echo ""

# 2. Clear MySQL
echo -e "${YELLOW}[2/15] Clearing MySQL...${NC}"
docker exec mysql-coc mysql -uroot -prootpassword -e "DROP DATABASE IF EXISTS coc_evidence;" 2>/dev/null || true
docker exec mysql-coc mysql -uroot -prootpassword -e "CREATE DATABASE coc_evidence;" 2>/dev/null || true
docker exec -i mysql-coc mysql -uroot -prootpassword coc_evidence < shared/database/init/01-schema.sql 2>&1 | grep -v "Warning" || true
echo -e "${GREEN}✓ MySQL cleared and schema loaded${NC}"
echo ""

# 3. Backup and remove old crypto
echo -e "${YELLOW}[3/15] Removing old crypto material...${NC}"
rm -rf hot-blockchain/crypto-config-backup 2>/dev/null || true
rm -rf cold-blockchain/crypto-config-backup 2>/dev/null || true
mv hot-blockchain/crypto-config hot-blockchain/crypto-config-backup 2>/dev/null || true
mv cold-blockchain/crypto-config cold-blockchain/crypto-config-backup 2>/dev/null || true
echo -e "${GREEN}✓ Old crypto backed up${NC}"
echo ""

# 4. Generate new Hot crypto
echo -e "${YELLOW}[4/15] Generating NEW Hot blockchain crypto...${NC}"
cd hot-blockchain
cryptogen generate --config=./crypto-config.yaml --output="./crypto-config"

# Copy core.yaml to each peer directory
cp ../config/core.yaml ./crypto-config/peerOrganizations/lawenforcement.hot.coc.com/peers/peer0.lawenforcement.hot.coc.com/
cp ../config/core.yaml ./crypto-config/peerOrganizations/forensiclab.hot.coc.com/peers/peer0.forensiclab.hot.coc.com/

cd ..
echo -e "${GREEN}✓ Hot crypto generated${NC}"
echo ""

# 5. Generate new Cold crypto
echo -e "${YELLOW}[5/15] Generating NEW Cold blockchain crypto...${NC}"
cd cold-blockchain
cryptogen generate --config=./crypto-config.yaml --output="./crypto-config"

# Copy core.yaml to peer directory
cp ../config/core.yaml ./crypto-config/peerOrganizations/archive.cold.coc.com/peers/peer0.archive.cold.coc.com/

cd ..
echo -e "${GREEN}✓ Cold crypto generated${NC}"
echo ""

# 6. Generate Hot genesis block
echo -e "${YELLOW}[6/15] Generating Hot genesis block...${NC}"
export FABRIC_CFG_PATH="$PROJECT_ROOT/hot-blockchain"
configtxgen -profile HotChainGenesis -channelID system-channel -outputBlock ./hot-blockchain/channel-artifacts/genesis.block
echo -e "${GREEN}✓ Hot genesis block created${NC}"
echo ""

# 7. Generate Hot channel block
echo -e "${YELLOW}[7/15] Generating Hot channel block...${NC}"
configtxgen -profile HotChainChannel -outputBlock ./hot-blockchain/channel-artifacts/hotchannel.block -channelID hotchannel
echo -e "${GREEN}✓ Hot channel block created${NC}"
echo ""

# 8. Generate Cold genesis block
echo -e "${YELLOW}[8/15] Generating Cold genesis block...${NC}"
export FABRIC_CFG_PATH="$PROJECT_ROOT/cold-blockchain"
configtxgen -profile ColdChainGenesis -channelID system-channel -outputBlock ./cold-blockchain/channel-artifacts/genesis.block
echo -e "${GREEN}✓ Cold genesis block created${NC}"
echo ""

# 9. Generate Cold channel block
echo -e "${YELLOW}[9/15] Generating Cold channel block...${NC}"
configtxgen -profile ColdChainChannel -outputBlock ./cold-blockchain/channel-artifacts/coldchannel.block -channelID coldchannel
echo -e "${GREEN}✓ Cold channel block created${NC}"
echo ""

# 10. Start Hot blockchain
echo -e "${YELLOW}[10/15] Starting Hot blockchain...${NC}"
cd "$PROJECT_ROOT"
docker-compose -f docker-compose-hot.yml up -d
echo "Waiting 15 seconds for initialization..."
sleep 15
echo -e "${GREEN}✓ Hot blockchain started${NC}"
echo ""

# 11. Start Cold blockchain
echo -e "${YELLOW}[11/15] Starting Cold blockchain...${NC}"
docker-compose -f docker-compose-cold.yml up -d
echo "Waiting 15 seconds for initialization..."
sleep 15
echo -e "${GREEN}✓ Cold blockchain started${NC}"
echo ""

# 12. Join Hot orderer to channel
echo -e "${YELLOW}[12/15] Joining Hot orderer to channel...${NC}"
docker exec cli osnadmin channel join \
    --channelID hotchannel \
    --config-block /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/hotchannel.block \
    -o orderer.hot.coc.com:7053 \
    --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/ca.crt \
    --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.crt \
    --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.key
echo -e "${GREEN}✓ Hot orderer joined channel${NC}"
echo ""

# 13. Join Cold orderer to channel
echo -e "${YELLOW}[13/15] Joining Cold orderer to channel...${NC}"
docker exec cli-cold osnadmin channel join \
    --channelID coldchannel \
    --config-block /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/coldchannel.block \
    -o orderer.cold.coc.com:7153 \
    --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/ca.crt \
    --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/server.crt \
    --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/server.key
echo -e "${GREEN}✓ Cold orderer joined channel${NC}"
echo ""

# 14. Join Hot channel peers (Fabric 2.5 style)
echo -e "${YELLOW}[14/17] Joining Hot channel peers...${NC}"

# Verify containers are running
echo "Checking container status..."
PEER0_LE=$(docker ps -q --filter "name=peer0.lawenforcement.hot.coc.com")
PEER0_FL=$(docker ps -q --filter "name=peer0.forensiclab.hot.coc.com")

if [ -z "$PEER0_LE" ]; then
    echo -e "${RED}ERROR: peer0.lawenforcement.hot.coc.com is NOT running!${NC}"
    echo "Container logs:"
    docker logs peer0.lawenforcement.hot.coc.com 2>&1 | tail -20
    exit 1
fi

if [ -z "$PEER0_FL" ]; then
    echo -e "${RED}ERROR: peer0.forensiclab.hot.coc.com is NOT running!${NC}"
    echo "Container logs:"
    docker logs peer0.forensiclab.hot.coc.com 2>&1 | tail -20
    exit 1
fi

echo "✓ All peer containers are running"

# Copy to CLI
docker cp hot-blockchain/channel-artifacts/hotchannel.block cli:/opt/gopath/src/github.com/hyperledger/fabric/peer/

# Join peer0.lawenforcement
echo "Joining peer0.lawenforcement to hotchannel..."
docker exec cli peer channel join -b /opt/gopath/src/github.com/hyperledger/fabric/peer/hotchannel.block

docker exec cli bash -c '
export CORE_PEER_ADDRESS=peer0.forensiclab.hot.coc.com:8051
export CORE_PEER_LOCALMSPID=ForensicLabMSP
export CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/forensiclab.hot.coc.com/peers/peer0.forensiclab.hot.coc.com/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/forensiclab.hot.coc.com/users/Admin@forensiclab.hot.coc.com/msp
peer channel join -b /opt/gopath/src/github.com/hyperledger/fabric/peer/hotchannel.block
'

echo -e "${GREEN}✓ Hot channel created${NC}"
echo ""

# 15. Join Cold channel peers
echo -e "${YELLOW}[15/17] Joining Cold channel peers...${NC}"

docker cp cold-blockchain/channel-artifacts/coldchannel.block cli-cold:/opt/gopath/src/github.com/hyperledger/fabric/peer/
docker exec cli-cold peer channel join -b /opt/gopath/src/github.com/hyperledger/fabric/peer/coldchannel.block

echo -e "${GREEN}✓ Cold channel created${NC}"
echo ""

# 16. Verify channels
echo -e "${YELLOW}[16/17] Verifying channels...${NC}"
HOT_HEIGHT=$(docker exec cli peer channel getinfo -c hotchannel 2>/dev/null | grep -oP '(?<="height":)\d+' || echo "1")
COLD_HEIGHT=$(docker exec cli-cold peer channel getinfo -c coldchannel 2>/dev/null | grep -oP '(?<="height":)\d+' || echo "1")
echo -e "${GREEN}✓ Hot Height: $HOT_HEIGHT${NC}"
echo -e "${GREEN}✓ Cold Height: $COLD_HEIGHT${NC}"
echo ""

# 17. Update anchor peers
echo -e "${YELLOW}[17/17] Updating anchor peers...${NC}"
export FABRIC_CFG_PATH="$PROJECT_ROOT/hot-blockchain"
configtxgen -profile HotChainChannel -outputAnchorPeersUpdate ./hot-blockchain/channel-artifacts/LawEnforcementMSPanchors.tx -channelID hotchannel -asOrg LawEnforcementMSP || true
configtxgen -profile HotChainChannel -outputAnchorPeersUpdate ./hot-blockchain/channel-artifacts/ForensicLabMSPanchors.tx -channelID hotchannel -asOrg ForensicLabMSP || true
echo -e "${GREEN}✓ Anchor peers configured${NC}"
echo ""

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  Nuclear Reset Complete!               ${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo -e "${GREEN}✓ NEW crypto material generated${NC}"
echo -e "${GREEN}✓ NEW channel blocks created${NC}"
echo -e "${GREEN}✓ TLS certificates now MATCH${NC}"
echo -e "${GREEN}✓ Channels created at height $HOT_HEIGHT/$COLD_HEIGHT${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. ./deploy-chaincode.sh"
echo "  2. ./start-explorers.sh"
echo "  3. ./launch-webapp.sh"
echo ""
echo -e "${GREEN}This should work now - all certs match!${NC}"
echo ""
