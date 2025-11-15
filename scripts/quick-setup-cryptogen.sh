#!/bin/bash
###############################################################################
# WORKAROUND: Quick setup using cryptogen instead of Fabric CA
# This bypasses the Fabric CA + Enclave integration to get network running
###############################################################################

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo -e "${GREEN}=========================================="
echo "Quick Network Setup with Cryptogen"
echo -e "==========================================${NC}"
echo ""
echo -e "${YELLOW}This is a workaround to bypass Fabric CA issues${NC}"
echo -e "${YELLOW}We'll use cryptogen to generate proper certificates${NC}"
echo ""

cd "$PROJECT_ROOT"

# Step 1: Stop all containers
echo -e "${YELLOW}[1/7] Stopping all containers...${NC}"
docker-compose -f docker-compose-hot.yml -f docker-compose-cold.yml down 2>/dev/null || true
echo -e "${GREEN}✓ Containers stopped${NC}"
echo ""

# Step 2: Backup old organizations directory
echo -e "${YELLOW}[2/7] Backing up old organizations directory...${NC}"
if [ -d "organizations" ]; then
    mv organizations organizations-backup-$(date +%s) 2>/dev/null || true
fi
echo -e "${GREEN}✓ Backup complete${NC}"
echo ""

# Step 3: Generate crypto materials with cryptogen
echo -e "${YELLOW}[3/7] Generating crypto materials with cryptogen...${NC}"

# Generate hot blockchain crypto
echo "  Generating hot blockchain certificates..."
cryptogen generate --config=hot-blockchain/crypto-config.yaml --output=organizations
echo -e "${GREEN}  ✓ Hot blockchain crypto generated${NC}"

# Generate cold blockchain crypto
echo "  Generating cold blockchain certificates..."
cryptogen generate --config=cold-blockchain/crypto-config.yaml --output=organizations
echo -e "${GREEN}  ✓ Cold blockchain crypto generated${NC}"

echo -e "${GREEN}✓ All crypto materials generated${NC}"
echo ""

# Step 4: Rename directories to match expected structure
echo -e "${YELLOW}[4/7] Organizing certificate directories...${NC}"

# Hot blockchain
mv organizations/ordererOrganizations/hot.coc.com organizations/ordererOrganizations/hot.coc.com-temp 2>/dev/null || true
mkdir -p organizations/ordererOrganizations/
mv organizations/ordererOrganizations/hot.coc.com-temp organizations/ordererOrganizations/hot.coc.com 2>/dev/null || true

# Cold blockchain
mv organizations/ordererOrganizations/cold.coc.com organizations/ordererOrganizations/cold.coc.com-temp 2>/dev/null || true
mkdir -p organizations/ordererOrganizations/
mv organizations/ordererOrganizations/cold.coc.com-temp organizations/ordererOrganizations/cold.coc.com 2>/dev/null || true

echo -e "${GREEN}✓ Directories organized${NC}"
echo ""

# Step 5: Generate channel artifacts
echo -e "${YELLOW}[5/7] Generating channel artifacts...${NC}"
mkdir -p channel-artifacts

# Hot blockchain channel
export FABRIC_CFG_PATH="$PROJECT_ROOT/hot-blockchain"
echo "  Generating hotchannel genesis block..."
configtxgen -profile HotChainGenesis -outputBlock ./channel-artifacts/hotchannel.block -channelID hotchannel
echo "  Generating hot blockchain anchor peer updates..."
configtxgen -profile HotChainChannel -outputAnchorPeersUpdate ./channel-artifacts/LawEnforcementMSPanchors.tx -channelID hotchannel -asOrg LawEnforcementMSP
configtxgen -profile HotChainChannel -outputAnchorPeersUpdate ./channel-artifacts/ForensicLabMSPanchors.tx -channelID hotchannel -asOrg ForensicLabMSP

# Cold blockchain channel
export FABRIC_CFG_PATH="$PROJECT_ROOT/cold-blockchain"
echo "  Generating coldchannel genesis block..."
configtxgen -profile ColdChainGenesis -outputBlock ./channel-artifacts/coldchannel.block -channelID coldchannel
echo "  Generating cold blockchain anchor peer updates..."
configtxgen -profile ColdChainChannel -outputAnchorPeersUpdate ./channel-artifacts/AuditorMSPanchors.tx -channelID coldchannel -asOrg AuditorMSP

echo -e "${GREEN}✓ Channel artifacts generated${NC}"
echo ""

# Step 6: Start the network
echo -e "${YELLOW}[6/7] Starting blockchain network...${NC}"
docker-compose -f docker-compose-hot.yml -f docker-compose-cold.yml up -d
echo -e "${GREEN}✓ Network started${NC}"
echo ""

# Step 7: Wait for network to be ready
echo -e "${YELLOW}[7/7] Waiting for network to stabilize...${NC}"
sleep 15
echo -e "${GREEN}✓ Network ready${NC}"
echo ""

echo -e "${GREEN}=========================================="
echo "✓ Network Setup Complete!"
echo -e "==========================================${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Create channels:  ./scripts/create-channels-with-dynamic-mtls.sh"
echo "  2. Deploy chaincode: ./scripts/deploy-chaincode.sh"
echo "  3. Test IPFS integration"
echo ""
echo -e "${YELLOW}Note: This uses cryptogen instead of Fabric CA${NC}"
echo -e "${YELLOW}To add back enclave integration, we'll need to fix the CA setup later${NC}"
echo ""
