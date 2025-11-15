#!/bin/bash

# Complete restart script for the blockchain system
# Stops all containers, removes orphans, and restarts everything

echo "==========================================="
echo "   Restarting Blockchain Demo System"
echo "==========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 1. Stop all containers
echo -e "${YELLOW}Stopping all containers...${NC}"
docker-compose -f docker-compose-storage.yml down
docker-compose -f docker-compose-hot.yml down
docker-compose -f docker-compose-cold.yml down

# 2. Remove orphan containers if any
echo -e "${YELLOW}Removing orphan containers...${NC}"
docker-compose -f docker-compose-storage.yml down --remove-orphans 2>/dev/null
docker-compose -f docker-compose-hot.yml down --remove-orphans 2>/dev/null
docker-compose -f docker-compose-cold.yml down --remove-orphans 2>/dev/null

# 3. Wait for cleanup
echo "Waiting for cleanup to complete..."
sleep 5

# 4. Create shared network
echo -e "${YELLOW}Creating shared Docker network...${NC}"
docker network create coc-network 2>/dev/null || echo "Network already exists"

# 5. Fix core.yaml files
echo -e "${YELLOW}Ensuring core.yaml files are in place...${NC}"
SOURCE_CORE="fabric-samples/test-network/compose/docker/peercfg/core.yaml"
if [ -f "$SOURCE_CORE" ]; then
    cp "$SOURCE_CORE" hot-blockchain/crypto-config/peerOrganizations/lawenforcement.hot.coc.com/peers/peer0.lawenforcement.hot.coc.com/ 2>/dev/null
    cp "$SOURCE_CORE" hot-blockchain/crypto-config/peerOrganizations/forensiclab.hot.coc.com/peers/peer0.forensiclab.hot.coc.com/ 2>/dev/null
    cp "$SOURCE_CORE" cold-blockchain/crypto-config/peerOrganizations/archive.cold.coc.com/peers/peer0.archive.cold.coc.com/ 2>/dev/null
    echo "✓ core.yaml files copied"
else
    echo "⚠️  Warning: core.yaml not found, peers may fail to start"
fi

# 6. Set environment
export PATH="$PWD/fabric-samples/bin:$PATH"

# 7. Start Storage Services (IPFS + MySQL)
echo -e "${YELLOW}Starting Storage Services...${NC}"
docker-compose -f docker-compose-storage.yml up -d
echo "Waiting for services to initialize..."
sleep 10

# 8. Start Hot Blockchain
echo -e "${YELLOW}Starting Hot Blockchain...${NC}"
docker-compose -f docker-compose-hot.yml up -d
sleep 15

# 9. Start Cold Blockchain
echo -e "${YELLOW}Starting Cold Blockchain...${NC}"
docker-compose -f docker-compose-cold.yml up -d
sleep 15

# 10. Join orderers to channels using Channel Participation API
echo -e "${YELLOW}Joining orderers to channels...${NC}"

# Check if channel blocks exist
if [ ! -f "hot-blockchain/channel-artifacts/hotchannel.block" ]; then
    echo -e "${RED}⚠️  hotchannel.block not found. Run ./create-channels-fabric25.sh first${NC}"
else
    # Join hot orderer to hotchannel
    echo "  Joining orderer.hot.coc.com to hotchannel..."
    docker exec cli osnadmin channel join \
        --channelID hotchannel \
        --config-block /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/hotchannel.block \
        -o orderer.hot.coc.com:7053 \
        --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/tlscacerts/tlsca.hot.coc.com-cert.pem \
        --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.crt \
        --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.key \
        2>&1 | grep -q "already exists\|status: 201\|successfully" && echo "  ✓ Hot orderer joined" || echo "  ⚠️  Hot orderer join attempt completed"
fi

if [ ! -f "cold-blockchain/channel-artifacts/coldchannel.block" ]; then
    echo -e "${RED}⚠️  coldchannel.block not found. Run ./create-channels-fabric25.sh first${NC}"
else
    # Join cold orderer to coldchannel
    echo "  Joining orderer.cold.coc.com to coldchannel..."
    docker exec cli-cold osnadmin channel join \
        --channelID coldchannel \
        --config-block /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/coldchannel.block \
        -o orderer.cold.coc.com:7153 \
        --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/msp/tlscacerts/tlsca.cold.coc.com-cert.pem \
        --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/server.crt \
        --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/server.key \
        2>&1 | grep -q "already exists\|status: 201\|successfully" && echo "  ✓ Cold orderer joined" || echo "  ⚠️  Cold orderer join attempt completed"
fi

echo -e "${GREEN}✓ Orderer channel participation complete${NC}"

# 11. Join channels
echo -e "${YELLOW}Ensuring peer channels are joined...${NC}"

# Copy channel blocks
docker cp hot-blockchain/channel-artifacts/hotchannel.block cli:/opt/gopath/src/github.com/hyperledger/fabric/peer/ 2>/dev/null
docker cp cold-blockchain/channel-artifacts/coldchannel.block cli-cold:/opt/gopath/src/github.com/hyperledger/fabric/peer/ 2>/dev/null

# Join Hot channels
docker exec cli peer channel join -b hotchannel.block 2>/dev/null || echo "Law Enforcement already joined"
docker exec \
  -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/forensiclab.hot.coc.com/users/Admin@forensiclab.hot.coc.com/msp \
  -e CORE_PEER_ADDRESS=peer0.forensiclab.hot.coc.com:8051 \
  -e CORE_PEER_LOCALMSPID=ForensicLabMSP \
  -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/forensiclab.hot.coc.com/peers/peer0.forensiclab.hot.coc.com/tls/ca.crt \
  cli peer channel join -b hotchannel.block 2>/dev/null || echo "Forensic Lab already joined"

# Join Cold channel
docker exec cli-cold peer channel join -b coldchannel.block 2>/dev/null || echo "Archive already joined"

# 12. Configure IPFS for WebUI
echo -e "${YELLOW}Configuring IPFS WebUI...${NC}"
docker exec ipfs-node ipfs config --json API.HTTPHeaders.Access-Control-Allow-Origin '["https://webui.ipfs.io", "*"]' 2>/dev/null
docker restart ipfs-node
sleep 5

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}   System Restarted Successfully!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

# Show running containers
echo "📦 Running Containers:"
docker ps --format "table {{.Names}}\t{{.Status}}" | head -15

echo ""
echo "🔍 Blockchain Status:"
echo -n "  Hot Blockchain: "
docker exec cli peer channel list 2>/dev/null | grep -q "hotchannel" && echo -e "${GREEN}✅ Running${NC}" || echo -e "${RED}❌ Error${NC}"
echo -n "  Cold Blockchain: "
docker exec cli-cold peer channel list 2>/dev/null | grep -q "coldchannel" && echo -e "${GREEN}✅ Running${NC}" || echo -e "${RED}❌ Error${NC}"

echo ""
echo "📊 Access Points:"
echo "  Main Dashboard:  http://localhost:5000"
echo "  IPFS WebUI:      https://webui.ipfs.io/#/files"
echo "  phpMyAdmin:      http://localhost:8081"
echo "  IPFS Gateway:    http://localhost:8080"
echo ""
echo "✅ Ready! Next steps:"
echo "  1. Run ./deploy-chaincode.sh to deploy chaincode"
echo "  2. Run ./update-mysql.sh to update database (if needed)"
echo "  3. Start webapp: cd webapp && python3 app_blockchain.py"
echo ""
