#!/bin/bash
###############################################################################
# COMPLETE CLEAN START - Remove ALL old certificates and start fresh
# Uses cryptogen for immediate working network
###############################################################################

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo -e "${RED}=========================================="
echo "COMPLETE CLEAN START"
echo -e "==========================================${NC}"
echo ""
echo -e "${YELLOW}This will DELETE all existing certificates and data${NC}"
echo -e "${YELLOW}Press Ctrl+C within 5 seconds to abort...${NC}"
sleep 5
echo ""

cd "$PROJECT_ROOT"

# Step 1: Stop and remove ALL containers and volumes
echo -e "${YELLOW}[1/8] Removing all containers, networks, and volumes...${NC}"
docker-compose -f docker-compose-hot.yml -f docker-compose-cold.yml down -v --remove-orphans 2>/dev/null || true
docker volume prune -f 2>/dev/null || true
echo -e "${GREEN}✓ Docker cleaned${NC}"
echo ""

# Step 2: Remove ALL old certificate directories
echo -e "${YELLOW}[2/8] Removing all old certificate and artifact directories...${NC}"
rm -rf organizations organizations-backup-* 2>/dev/null || true
rm -rf channel-artifacts 2>/dev/null || true
rm -rf fabric-ca 2>/dev/null || true
echo -e "${GREEN}✓ Old directories removed${NC}"
echo ""

# Step 3: Create fresh organizations structure
echo -e "${YELLOW}[3/8] Creating fresh directory structure...${NC}"
mkdir -p organizations/ordererOrganizations
mkdir -p organizations/peerOrganizations
mkdir -p channel-artifacts
echo -e "${GREEN}✓ Fresh directories created${NC}"
echo ""

# Step 4: Generate crypto materials with cryptogen
echo -e "${YELLOW}[4/8] Generating crypto materials with cryptogen...${NC}"

# Generate hot blockchain crypto
echo "  Generating hot blockchain certificates..."
cryptogen generate --config=hot-blockchain/crypto-config.yaml --output=organizations
echo -e "${GREEN}  ✓ Hot blockchain crypto generated${NC}"

# Generate cold blockchain crypto
echo "  Generating cold blockchain certificates..."
cryptogen generate --config=cold-blockchain/crypto-config.yaml --output=organizations
echo -e "${GREEN}  ✓ Cold blockchain crypto generated${NC}"

echo -e "${GREEN}✓ All crypto materials generated with proper SKI/AKI${NC}"
echo ""

# Step 5: Verify certificates have SKI
echo -e "${YELLOW}[5/8] Verifying certificates have SKI extension...${NC}"
HOT_ORDERER_CA=$(find organizations/ordererOrganizations/hot.coc.com/msp/cacerts -type f -name "*.pem" | head -1)
if openssl x509 -in "$HOT_ORDERER_CA" -noout -ext subjectKeyIdentifier 2>&1 | grep -q "X509v3 Subject Key Identifier"; then
    echo -e "${GREEN}✓ Hot orderer CA has SKI extension${NC}"
else
    echo -e "${RED}✗ Hot orderer CA missing SKI - cryptogen failed${NC}"
    exit 1
fi
echo ""

# Step 6: Generate channel genesis blocks
echo -e "${YELLOW}[6/8] Generating channel genesis blocks...${NC}"

# Hot blockchain channel
export FABRIC_CFG_PATH="$PROJECT_ROOT/hot-blockchain"
echo "  Generating hotchannel genesis block..."
configtxgen -profile HotChainGenesis \
    -outputBlock ./channel-artifacts/hotchannel.block \
    -channelID hotchannel
echo "  Generating hot blockchain anchor peer updates..."
configtxgen -profile HotChainChannel \
    -outputAnchorPeersUpdate ./channel-artifacts/LawEnforcementMSPanchors.tx \
    -channelID hotchannel \
    -asOrg LawEnforcementMSP
configtxgen -profile HotChainChannel \
    -outputAnchorPeersUpdate ./channel-artifacts/ForensicLabMSPanchors.tx \
    -channelID hotchannel \
    -asOrg ForensicLabMSP

# Cold blockchain channel
export FABRIC_CFG_PATH="$PROJECT_ROOT/cold-blockchain"
echo "  Generating coldchannel genesis block..."
configtxgen -profile ColdChainGenesis \
    -outputBlock ./channel-artifacts/coldchannel.block \
    -channelID coldchannel
echo "  Generating cold blockchain anchor peer updates..."
configtxgen -profile ColdChainChannel \
    -outputAnchorPeersUpdate ./channel-artifacts/AuditorMSPanchors.tx \
    -channelID coldchannel \
    -asOrg AuditorMSP

echo -e "${GREEN}✓ Channel artifacts generated${NC}"
echo ""

# Step 7: Verify genesis block contains good certificates
echo -e "${YELLOW}[7/8] Verifying genesis block certificates...${NC}"
if configtxblock=$(configtxlator proto_decode --input ./channel-artifacts/hotchannel.block --type common.Block 2>&1); then
    echo -e "${GREEN}✓ Genesis block is valid${NC}"
else
    echo -e "${RED}✗ Genesis block validation failed${NC}"
    exit 1
fi
echo ""

# Step 8: Start the network
echo -e "${YELLOW}[8/8] Starting blockchain network...${NC}"
docker-compose -f docker-compose-hot.yml -f docker-compose-cold.yml up -d
echo -e "${GREEN}✓ Network started${NC}"
echo ""

# Wait for network
echo -e "${YELLOW}Waiting for network to stabilize (20 seconds)...${NC}"
sleep 20
echo ""

# Verify orderers are running
echo -e "${YELLOW}Verifying orderers are running...${NC}"
if docker logs orderer.hot.coc.com 2>&1 | grep -q "Beginning to serve requests"; then
    echo -e "${GREEN}✓ Hot orderer is serving requests${NC}"
else
    echo -e "${RED}✗ Hot orderer not ready - check logs: docker logs orderer.hot.coc.com${NC}"
fi

if docker logs orderer.cold.coc.com 2>&1 | grep -q "Beginning to serve requests"; then
    echo -e "${GREEN}✓ Cold orderer is serving requests${NC}"
else
    echo -e "${RED}✗ Cold orderer not ready - check logs: docker logs orderer.cold.coc.com${NC}"
fi
echo ""

echo -e "${GREEN}=========================================="
echo "✓ Clean Setup Complete!"
echo -e "==========================================${NC}"
echo ""
echo -e "${YELLOW}Network Status:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(peer|orderer)"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Create channels:  ./scripts/create-channels-with-dynamic-mtls.sh"
echo "  2. Deploy chaincode: ./scripts/deploy-chaincode.sh"
echo ""
echo -e "${GREEN}All certificates generated with cryptogen (proper SKI/AKI)${NC}"
echo -e "${YELLOW}No Fabric CA or Enclave dependencies${NC}"
echo ""
