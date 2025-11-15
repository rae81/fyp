#!/bin/bash

###############################################################################
# Quick Fix: Regenerate certificates with cryptogen and restart everything
###############################################################################

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=========================================${NC}"
echo -e "${YELLOW}   Quick Fix - Regenerate & Restart${NC}"
echo -e "${YELLOW}=========================================${NC}"
echo ""

# Stop all containers
echo -e "${YELLOW}[1/8] Stopping all containers...${NC}"
docker-compose -f docker-compose-hot.yml down -v 2>/dev/null || true
docker-compose -f docker-compose-cold.yml down -v 2>/dev/null || true
docker-compose -f docker-compose-storage.yml down 2>/dev/null || true
echo -e "${GREEN}✓ Containers stopped${NC}"
echo ""

# Regenerate crypto using cryptogen (rami branch standard)
echo -e "${YELLOW}[2/8] Regenerating certificates with cryptogen...${NC}"
# DELETE old certificates first to force fresh generation
rm -rf hot-blockchain/crypto-config
rm -rf cold-blockchain/crypto-config

cd hot-blockchain
cryptogen generate --config=./crypto-config.yaml --output="./crypto-config"
cp ../config/core.yaml ./crypto-config/peerOrganizations/lawenforcement.hot.coc.com/peers/peer0.lawenforcement.hot.coc.com/ 2>/dev/null || true
cp ../config/core.yaml ./crypto-config/peerOrganizations/forensiclab.hot.coc.com/peers/peer0.forensiclab.hot.coc.com/ 2>/dev/null || true
cd ..
echo -e "${GREEN}✓ Hot blockchain crypto generated${NC}"

cd cold-blockchain
cryptogen generate --config=./crypto-config.yaml --output="./crypto-config"
cp ../config/core.yaml ./crypto-config/peerOrganizations/archive.cold.coc.com/peers/peer0.archive.cold.coc.com/ 2>/dev/null || true
cd ..
echo -e "${GREEN}✓ Cold blockchain crypto generated${NC}"
echo ""

# Generate channel artifacts
echo -e "${YELLOW}[3/8] Generating channel artifacts...${NC}"
export FABRIC_CFG_PATH="$PWD/hot-blockchain"
configtxgen -profile HotChainGenesis -channelID system-channel -outputBlock ./hot-blockchain/channel-artifacts/genesis.block
configtxgen -profile HotChainChannel -outputBlock ./hot-blockchain/channel-artifacts/hotchannel.block -channelID hotchannel
echo -e "${GREEN}✓ Hot channel artifacts generated${NC}"

export FABRIC_CFG_PATH="$PWD/cold-blockchain"
configtxgen -profile ColdChainGenesis -channelID system-channel -outputBlock ./cold-blockchain/channel-artifacts/genesis.block
configtxgen -profile ColdChainChannel -outputBlock ./cold-blockchain/channel-artifacts/coldchannel.block -channelID coldchannel
echo -e "${GREEN}✓ Cold channel artifacts generated${NC}"
echo ""

# Start storage services
echo -e "${YELLOW}[4/8] Starting storage services...${NC}"
docker-compose -f docker-compose-storage.yml up -d
sleep 5
echo -e "${GREEN}✓ Storage services started${NC}"
echo ""

# Load MySQL schema
echo -e "${YELLOW}[5/8] Loading MySQL schema...${NC}"
docker exec -i mysql-coc mysql -uroot -prootpassword -e "DROP DATABASE IF EXISTS coc_evidence; CREATE DATABASE coc_evidence;" 2>/dev/null || true
docker exec -i mysql-coc mysql -uroot -prootpassword coc_evidence < shared/database/init/01-schema.sql 2>&1 | grep -v "Warning" || true
echo -e "${GREEN}✓ MySQL schema loaded${NC}"
echo ""

# Start blockchains
echo -e "${YELLOW}[6/8] Starting blockchains...${NC}"
docker-compose -f docker-compose-hot.yml up -d
docker-compose -f docker-compose-cold.yml up -d
echo "Waiting for all containers to be healthy (30 seconds)..."
sleep 30
echo -e "${GREEN}✓ Blockchains started${NC}"
echo ""

# Create channels
echo -e "${YELLOW}[7/8] Creating channels...${NC}"
./scripts/create-channels-fabric25.sh
echo ""

# Deploy chaincode
echo -e "${YELLOW}[8/8] Deploying chaincode...${NC}"
./deploy-chaincode.sh
echo ""

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}   Quick Fix Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "${YELLOW}Next step: Run ./verify-blockchain.sh${NC}"
