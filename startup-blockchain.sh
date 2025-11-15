#!/bin/bash

echo "==========================================="
echo "   Starting Blockchain Demo System"
echo "==========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 1. Set environment
export PATH="$PWD/fabric-samples/bin:$PATH"

# 2. Create shared Docker network
echo -e "${YELLOW}Creating shared Docker network...${NC}"
docker network create coc-network 2>/dev/null || echo "Network already exists"

# 3. Start Storage Services (IPFS + MySQL)
echo -e "${YELLOW}Starting Storage Services...${NC}"
docker-compose -f docker-compose-storage.yml up -d
echo "Waiting for services to initialize..."
sleep 10

# 4. Start Hot Blockchain
echo -e "${YELLOW}Starting Hot Blockchain...${NC}"
docker-compose -f docker-compose-hot.yml up -d
sleep 15

# 5. Start Cold Blockchain
echo -e "${YELLOW}Starting Cold Blockchain...${NC}"
docker-compose -f docker-compose-cold.yml up -d
sleep 15

# 6. Join channels (in case they disconnected)
echo -e "${YELLOW}Ensuring channels are joined...${NC}"

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

# 7. Configure IPFS for WebUI
echo -e "${YELLOW}Configuring IPFS WebUI...${NC}"
docker exec ipfs-node ipfs config --json API.HTTPHeaders.Access-Control-Allow-Origin '["https://webui.ipfs.io", "*"]' 2>/dev/null
docker restart ipfs-node
sleep 5

# 8. Start Flask Web Application (optional - skip if port 5000 in use)
echo -e "${YELLOW}Starting Web Dashboard...${NC}"
if lsof -Pi :5000 -sTCP:LISTEN -t >/dev/null 2>&1 ; then
    echo "⚠️  Port 5000 is in use. Skipping webapp start."
    echo "   To start manually: cd webapp && python3 app_blockchain.py"
else
    cd webapp
    nohup python3 app_blockchain.py > flask.log 2>&1 &
    cd ..
fi

# 9. Wait and verify
sleep 5

# 10. Status check
echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}   System Started Successfully!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

# Show running containers
echo "📦 Running Containers:"
docker ps --format "table {{.Names}}\t{{.Status}}" | head -15

echo ""
echo "🔍 Blockchain Status:"
echo -n "  Hot Blockchain: "
docker exec cli peer channel list 2>/dev/null | grep -q "hotchannel" && echo "✅ Running" || echo "❌ Error"
echo -n "  Cold Blockchain: "
docker exec cli-cold peer channel list 2>/dev/null | grep -q "coldchannel" && echo "✅ Running" || echo "❌ Error"

echo ""
echo "📊 Access Points:"
echo "  Main Dashboard:  http://localhost:5000"
echo "  IPFS WebUI:      https://webui.ipfs.io/#/files"
echo "  phpMyAdmin:      http://localhost:8081"
echo "  IPFS Gateway:    http://localhost:8080"
echo ""
echo "  MySQL User:      cocuser"
echo "  MySQL Password:  cocpassword"
echo ""
echo "✅ Ready for demo!"
