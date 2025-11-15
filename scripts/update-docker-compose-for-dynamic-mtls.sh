#!/bin/bash

###############################################################################
# Update docker-compose files to use organizations directory
# instead of crypto-config for dynamic mTLS certificates
###############################################################################

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Updating Docker Compose for Dynamic mTLS${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

# Backup original files
echo -e "${YELLOW}Creating backups...${NC}"
cp docker-compose-hot.yml docker-compose-hot.yml.backup
cp docker-compose-cold.yml docker-compose-cold.yml.backup
echo -e "${GREEN}✓ Backups created${NC}"
echo ""

# Update hot blockchain docker-compose
echo -e "${YELLOW}Updating hot blockchain docker-compose...${NC}"

# Replace crypto-config with organizations
sed -i 's|/crypto-config/|/organizations/|g' docker-compose-hot.yml
sed -i 's|crypto-config:|organizations:|g' docker-compose-hot.yml

# Update CLI volume mapping
sed -i 's|./hot-blockchain/crypto-config:/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/|./organizations:/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations|g' docker-compose-hot.yml

# Update environment variables in CLI to use organizations
sed -i 's|/peer/crypto/peerOrganizations|/peer/organizations/peerOrganizations|g' docker-compose-hot.yml
sed -i 's|/peer/crypto/ordererOrganizations|/peer/organizations/ordererOrganizations|g' docker-compose-hot.yml

echo -e "${GREEN}✓ Hot blockchain docker-compose updated${NC}"
echo ""

# Update cold blockchain docker-compose
echo -e "${YELLOW}Updating cold blockchain docker-compose...${NC}"

# Replace crypto-config with organizations
sed -i 's|/crypto-config/|/organizations/|g' docker-compose-cold.yml
sed -i 's|crypto-config:|organizations:|g' docker-compose-cold.yml

# Update CLI volume mapping
sed -i 's|./cold-blockchain/crypto-config:/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/|./organizations:/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations|g' docker-compose-cold.yml

# Update environment variables in CLI to use organizations
sed -i 's|/peer/crypto/peerOrganizations|/peer/organizations/peerOrganizations|g' docker-compose-cold.yml
sed -i 's|/peer/crypto/ordererOrganizations|/peer/organizations/ordererOrganizations|g' docker-compose-cold.yml

echo -e "${GREEN}✓ Cold blockchain docker-compose updated${NC}"
echo ""

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}✓ Docker Compose files updated!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "${YELLOW}Changes made:${NC}"
echo -e "  • Replaced crypto-config with organizations"
echo -e "  • Updated volume mounts to use new certificate structure"
echo -e "  • Updated CLI environment variables"
echo ""
echo -e "${YELLOW}Note: Backups saved as:${NC}"
echo -e "  • docker-compose-hot.yml.backup"
echo -e "  • docker-compose-cold.yml.backup"
echo ""
