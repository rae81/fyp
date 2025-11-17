#!/bin/bash
#
# Fix Hotchannel Endorsement Policy Issue
# ========================================
# This script recreates the hotchannel with only 2 orgs (LawEnforcement + ForensicLab)
# to resolve ENDORSEMENT_POLICY_FAILURE during chaincode commits
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
echo -e "${MAGENTA}║        Fixing Hotchannel Endorsement Policy (2 orgs)          ║${NC}"
echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================================
# PHASE 1: GENERATE NEW GENESIS BLOCK WITH ONLY 2 ORGS
# ============================================================================

echo -e "${CYAN}[1/6] Generating new genesis block with only 2 orgs...${NC}"

# Generate new genesis block
docker run --rm \
    -v $(pwd):/work \
    -w /work/hot-blockchain \
    -e FABRIC_CFG_PATH=/work/hot-blockchain \
    hyperledger/fabric-tools:2.5 \
    sh -c "cd /work && configtxgen -configPath hot-blockchain -profile HotChainGenesis -outputBlock hot-blockchain/channel-artifacts/hotchannel-fixed.block -channelID hotchannel"

echo -e "  ${GREEN}✓${NC} Generated hotchannel-fixed.block"

# Verify the block contains only 2 orgs
echo ""
echo -e "${CYAN}Verifying genesis block contains only 2 orgs:${NC}"
docker run --rm \
    -v $(pwd):/work \
    -w /work \
    hyperledger/fabric-tools:2.5 \
    sh -c "configtxlator proto_decode --input hot-blockchain/channel-artifacts/hotchannel-fixed.block --type common.Block | jq -r '.data.data[0].payload.data.config.channel_group.groups.Application.groups | keys[]'" | sort

# ============================================================================
# PHASE 2: STOP ORDERER, PEERS, AND CLI
# ============================================================================

echo ""
echo -e "${CYAN}[2/6] Stopping orderer, peers, and CLI...${NC}"

docker-compose -f docker-compose-full.yml stop orderer.hot.coc.com peer0.lawenforcement.hot.coc.com peer0.forensiclab.hot.coc.com cli

echo -e "  ${GREEN}✓${NC} Containers stopped"

# ============================================================================
# PHASE 3: CLEAN OLD CHANNEL DATA
# ============================================================================

echo ""
echo -e "${CYAN}[3/6] Cleaning old channel data...${NC}"

# Clean orderer channel data
echo -e "  ${YELLOW}Cleaning orderer channel data...${NC}"
docker run --rm -v fyp_orderer.hot.coc.com:/var/hyperledger/production busybox sh -c "rm -rf /var/hyperledger/production/orderer/chains/hotchannel"

# Clean peer channel data
echo -e "  ${YELLOW}Cleaning peer0.lawenforcement channel data...${NC}"
docker run --rm -v fyp_peer0.lawenforcement.hot.coc.com:/var/hyperledger/production busybox sh -c "rm -rf /var/hyperledger/production/ledgersData/chains/chains/hotchannel"

echo -e "  ${YELLOW}Cleaning peer0.forensiclab channel data...${NC}"
docker run --rm -v fyp_peer0.forensiclab.hot.coc.com:/var/hyperledger/production busybox sh -c "rm -rf /var/hyperledger/production/ledgersData/chains/chains/hotchannel"

echo -e "  ${GREEN}✓${NC} Old channel data cleaned"

# ============================================================================
# PHASE 4: REPLACE GENESIS BLOCK AND RESTART CONTAINERS
# ============================================================================

echo ""
echo -e "${CYAN}[4/6] Replacing genesis block and restarting...${NC}"

# Fix permissions
sudo chown ramieid:ramieid hot-blockchain/channel-artifacts/hotchannel-fixed.block 2>/dev/null || true
sudo chmod 644 hot-blockchain/channel-artifacts/hotchannel-fixed.block 2>/dev/null || true

# Backup old block
cp hot-blockchain/channel-artifacts/hotchannel.block hot-blockchain/channel-artifacts/hotchannel-4orgs.block.bak 2>/dev/null || true

# Replace with new block
cp hot-blockchain/channel-artifacts/hotchannel-fixed.block hot-blockchain/channel-artifacts/hotchannel.block

echo -e "  ${GREEN}✓${NC} Genesis block replaced"

# Restart containers (including CLI to refresh DNS cache)
docker-compose -f docker-compose-full.yml up -d orderer.hot.coc.com peer0.lawenforcement.hot.coc.com peer0.forensiclab.hot.coc.com cli

echo -e "  ${GREEN}✓${NC} Containers restarted"

# Wait for containers to initialize
echo -e "  ${YELLOW}Waiting for containers to initialize (30s)...${NC}"
sleep 30

# Verify DNS resolution works
echo -e "  ${YELLOW}Verifying CLI can resolve orderer hostname...${NC}"
for i in {1..5}; do
    if docker exec cli getent hosts orderer.hot.coc.com > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} DNS resolution working"
        break
    else
        if [ $i -eq 5 ]; then
            echo -e "  ${RED}✗${NC} DNS resolution failed after 5 attempts"
            echo -e "  ${YELLOW}Restarting CLI container to clear DNS cache...${NC}"
            docker-compose -f docker-compose-full.yml restart cli
            sleep 5
        else
            echo -e "  ${YELLOW}Attempt $i/5 failed, retrying in 2s...${NC}"
            sleep 2
        fi
    fi
done

# ============================================================================
# PHASE 5: JOIN ORDERER TO CHANNEL
# ============================================================================

echo ""
echo -e "${CYAN}[5/6] Joining orderer to channel...${NC}"

# Join orderer to channel using osnadmin
docker exec cli osnadmin channel join \
    --channelID hotchannel \
    --config-block /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/hotchannel.block \
    -o orderer.hot.coc.com:7053 \
    --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/ca.crt \
    --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.crt \
    --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.key

echo -e "  ${GREEN}✓${NC} Orderer joined to hotchannel"

# Wait for orderer to activate channel
echo -e "  ${YELLOW}Waiting for orderer to activate channel (30s)...${NC}"
sleep 30

# Check orderer status
echo ""
echo -e "${YELLOW}Orderer channel status:${NC}"
docker exec cli osnadmin channel list -o orderer.hot.coc.com:7053 \
    --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/ca.crt \
    --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.crt \
    --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.key

# ============================================================================
# PHASE 6: JOIN PEERS TO CHANNEL
# ============================================================================

echo ""
echo -e "${CYAN}[6/6] Joining peers to hotchannel...${NC}"

# Fetch genesis block from orderer
echo -e "  ${YELLOW}Fetching genesis block from orderer...${NC}"
docker exec cli peer channel fetch 0 /tmp/hotchannel.block -c hotchannel -o orderer.hot.coc.com:7050 \
    --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/ca.crt

echo -e "  ${GREEN}✓${NC} Genesis block fetched"

# Join LawEnforcement peer
echo -e "  ${YELLOW}Joining peer0.lawenforcement to hotchannel...${NC}"
docker exec -e CORE_PEER_LOCALMSPID=LawEnforcementMSP \
    -e CORE_PEER_ADDRESS=peer0.lawenforcement.hot.coc.com:7051 \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/lawenforcement.hot.coc.com/peers/peer0.lawenforcement.hot.coc.com/tls/ca.crt \
    -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/lawenforcement.hot.coc.com/users/Admin@lawenforcement.hot.coc.com/msp \
    cli peer channel join -b /tmp/hotchannel.block

echo -e "  ${GREEN}✓${NC} peer0.lawenforcement joined"

# Join ForensicLab peer
echo -e "  ${YELLOW}Joining peer0.forensiclab to hotchannel...${NC}"
docker exec -e CORE_PEER_LOCALMSPID=ForensicLabMSP \
    -e CORE_PEER_ADDRESS=peer0.forensiclab.hot.coc.com:8051 \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/forensiclab.hot.coc.com/peers/peer0.forensiclab.hot.coc.com/tls/ca.crt \
    -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/forensiclab.hot.coc.com/users/Admin@forensiclab.hot.coc.com/msp \
    cli peer channel join -b /tmp/hotchannel.block

echo -e "  ${GREEN}✓${NC} peer0.forensiclab joined"

# ============================================================================
# VERIFICATION
# ============================================================================

echo ""
echo -e "${CYAN}Verifying channel membership...${NC}"

# Check LawEnforcement peer
echo -e "  ${YELLOW}LawEnforcement channels:${NC}"
docker exec -e CORE_PEER_LOCALMSPID=LawEnforcementMSP \
    -e CORE_PEER_ADDRESS=peer0.lawenforcement.hot.coc.com:7051 \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/lawenforcement.hot.coc.com/peers/peer0.lawenforcement.hot.coc.com/tls/ca.crt \
    -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/lawenforcement.hot.coc.com/users/Admin@lawenforcement.hot.coc.com/msp \
    cli peer channel list

# Check ForensicLab peer
echo -e "  ${YELLOW}ForensicLab channels:${NC}"
docker exec -e CORE_PEER_LOCALMSPID=ForensicLabMSP \
    -e CORE_PEER_ADDRESS=peer0.forensiclab.hot.coc.com:8051 \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/forensiclab.hot.coc.com/peers/peer0.forensiclab.hot.coc.com/tls/ca.crt \
    -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/forensiclab.hot.coc.com/users/Admin@forensiclab.hot.coc.com/msp \
    cli peer channel list

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Hotchannel Recreation Complete!                   ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${CYAN}Channel now has ONLY 2 organizations:${NC}"
echo "  1. LawEnforcementMSP"
echo "  2. ForensicLabMSP"
echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo "  1. Run: ./deploy-chaincode.sh"
echo "     This will deploy chaincode to both hotchannel and coldchannel"
echo ""
echo "  2. Chaincode approval should now succeed with 2-org endorsement policy"
echo "  3. After chaincode deployment, start IPFS and MySQL:"
echo "     docker-compose -f docker-compose-storage.yml up -d"
echo ""
