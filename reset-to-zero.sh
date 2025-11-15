#!/bin/bash

# Complete reset script - Sets blockchain heights back to 0
# This removes ALL data including chaincode, volumes, and databases

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo -e "${RED}==========================================${NC}"
echo -e "${RED}   COMPLETE BLOCKCHAIN RESET TO ZERO"
echo -e "${RED}==========================================${NC}"
echo ""
echo -e "${YELLOW}WARNING: This will:${NC}"
echo "  - Delete ALL blockchain data"
echo "  - Reset block heights to 0"
echo "  - Remove ALL evidence records"
echo "  - Delete MySQL database contents"
echo "  - Remove ALL IPFS files"
echo "  - Delete explorer databases"
echo "  - Remove chaincode containers and images"
echo ""
echo -e "${RED}This action CANNOT be undone!${NC}"
echo ""
read -p "Type 'RESET' to confirm: " confirm

if [ "$confirm" != "RESET" ]; then
    echo "Reset cancelled."
    exit 1
fi

echo ""
echo -e "${YELLOW}[1/12] Stopping all containers...${NC}"
docker-compose -f docker-compose-storage.yml down
docker-compose -f docker-compose-hot.yml down
docker-compose -f docker-compose-cold.yml down
docker-compose -f docker-compose-explorers.yml down

echo -e "${YELLOW}[2/12] Removing all containers...${NC}"
docker rm -f $(docker ps -aq --filter "name=peer" --filter "name=orderer" --filter "name=cli" --filter "name=couchdb" --filter "name=mysql" --filter "name=ipfs" --filter "name=explorer" --filter "name=phpmyadmin") 2>/dev/null || echo "No containers to remove"

echo -e "${YELLOW}[3/12] Removing chaincode containers...${NC}"
docker rm -f $(docker ps -aq --filter "name=dev-peer") 2>/dev/null || echo "No chaincode containers"

echo -e "${YELLOW}[4/12] Removing chaincode images...${NC}"
docker rmi -f $(docker images -q --filter "reference=dev-peer*") 2>/dev/null || echo "No chaincode images"

echo -e "${YELLOW}[5/12] Removing ALL Docker volumes...${NC}"
docker volume rm $(docker volume ls -q --filter "name=couchdb" --filter "name=orderer" --filter "name=peer" --filter "name=mysql" --filter "name=ipfs" --filter "name=explorer") 2>/dev/null || echo "No volumes to remove"

echo -e "${YELLOW}[6/12] Removing blockchain networks...${NC}"
docker network rm hot-chain-network cold-chain-network storage-network 2>/dev/null || echo "Networks already removed"

echo -e "${YELLOW}[7/12] Cleaning up crypto material (keeping for reuse)...${NC}"
# Keep crypto-config but you could regenerate if needed

echo -e "${YELLOW}[8/12] Removing IPFS data directory...${NC}"
sudo rm -rf ./ipfs-data/* 2>/dev/null || echo "No IPFS data to remove"

echo -e "${YELLOW}[9/12] Removing MySQL data directory...${NC}"
sudo rm -rf ./mysql-data/* 2>/dev/null || echo "No MySQL data to remove"

echo -e "${YELLOW}[10/12] Removing explorer database volumes...${NC}"
docker volume rm dual-hyperledger-blockchain_explorerdb-hot-data 2>/dev/null || echo "Hot explorer DB already removed"
docker volume rm dual-hyperledger-blockchain_explorerdb-cold-data 2>/dev/null || echo "Cold explorer DB already removed"

echo -e "${YELLOW}[11/12] Removing any orphaned volumes...${NC}"
docker volume prune -f 2>/dev/null || echo "No orphaned volumes"

echo -e "${YELLOW}[12/12] Resetting chaincode sequence to 1...${NC}"
sed -i 's/CC_SEQUENCE=.*/CC_SEQUENCE=1/' deploy-chaincode.sh
echo "✓ Chaincode sequence reset to 1"

sleep 3

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}   Reset Complete!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo "All blockchain data has been erased."
echo "Block heights will be 0 when you restart."
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "  1. ./restart-blockchain.sh    # Start fresh blockchains (height 0)"
echo "  2. ./deploy-chaincode.sh      # Deploy chaincode (sequence 1)"
echo "  3. ./start-explorers.sh       # Start explorers"
echo "  4. cd webapp && python3 app_blockchain.py"
echo ""
echo "Your blockchain will start fresh with block height 0!"
echo ""
