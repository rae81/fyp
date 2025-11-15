#!/bin/bash

###############################################################################
# Soft Reset - Clears data without destroying orderer channel state
# Use this instead of complete-reset.sh to avoid certificate issues
###############################################################################

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  SOFT RESET (Preserves Orderer State)  ${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo -e "${YELLOW}This will:${NC}"
echo "  ✗ Remove chaincode containers and images"
echo "  ✗ Clear MySQL evidence records"
echo "  ✗ Stop and restart all containers"
echo ""
echo -e "${GREEN}This will preserve:${NC}"
echo "  ✓ Orderer channel configuration"
echo "  ✓ Blockchain ledger data"
echo "  ✓ IPFS files"
echo "  ✓ Crypto material"
echo ""
read -p "Continue? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Aborted."
    exit 1
fi
echo ""

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

# Stop webapp
echo -e "${YELLOW}[1/8] Stopping webapp...${NC}"
pkill -f "python.*app_blockchain.py" 2>/dev/null || true
echo -e "${GREEN}✓ Webapp stopped${NC}"
echo ""

# Stop explorers (but don't remove volumes)
echo -e "${YELLOW}[2/8] Stopping explorers...${NC}"
docker-compose -f docker-compose-explorers.yml down 2>/dev/null || true
echo -e "${GREEN}✓ Explorers stopped${NC}"
echo ""

# Remove chaincode containers
echo -e "${YELLOW}[3/8] Removing chaincode containers...${NC}"
docker rm -f $(docker ps -aq -f name=dev-peer) 2>/dev/null || true
echo -e "${GREEN}✓ Chaincode containers removed${NC}"
echo ""

# Remove chaincode images
echo -e "${YELLOW}[4/8] Removing chaincode images...${NC}"
docker rmi -f $(docker images -q -f reference=dev-peer*) 2>/dev/null || true
echo -e "${GREEN}✓ Chaincode images removed${NC}"
echo ""

# Clear MySQL evidence data (but keep schema)
echo -e "${YELLOW}[5/8] Clearing MySQL evidence data...${NC}"
docker exec mysql-coc mysql -ucocuser -pcocpassword -e "TRUNCATE TABLE evidence_metadata;" coc_evidence 2>/dev/null || true
echo -e "${GREEN}✓ MySQL evidence data cleared${NC}"
echo ""

# Restart blockchains (maintains state in volumes)
echo -e "${YELLOW}[6/8] Restarting Hot blockchain...${NC}"
docker-compose -f docker-compose-hot.yml restart
sleep 5
echo -e "${GREEN}✓ Hot blockchain restarted${NC}"
echo ""

echo -e "${YELLOW}[7/8] Restarting Cold blockchain...${NC}"
docker-compose -f docker-compose-cold.yml restart
sleep 5
echo -e "${GREEN}✓ Cold blockchain restarted${NC}"
echo ""

# Check blockchain heights
echo -e "${YELLOW}[8/8] Checking blockchain status...${NC}"
HOT_HEIGHT=$(docker exec cli peer channel getinfo -c hotchannel 2>/dev/null | grep -oP '(?<="height":)\d+' || echo "unknown")
COLD_HEIGHT=$(docker exec cli-cold peer channel getinfo -c coldchannel 2>/dev/null | grep -oP '(?<="height":)\d+' || echo "unknown")

echo -e "${GREEN}✓ Hot Blockchain Height:  $HOT_HEIGHT${NC}"
echo -e "${GREEN}✓ Cold Blockchain Height: $COLD_HEIGHT${NC}"
echo ""

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  Soft Reset Complete!                  ${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo -e "${GREEN}✓ Chaincode removed${NC}"
echo -e "${GREEN}✓ MySQL evidence data cleared${NC}"
echo -e "${GREEN}✓ Blockchains still at previous heights${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
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
echo -e "${YELLOW}Note: Blockchain ledgers were NOT reset.${NC}"
echo -e "${YELLOW}To fully reset to height 0, you need to fix the orderer TLS cert issue first.${NC}"
echo ""
