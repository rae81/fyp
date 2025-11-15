#!/bin/bash

###############################################################################
# Reset Blockchains to Height 0
# Clears all blockchain data, MySQL records, and explorer databases
###############################################################################

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${RED}=========================================${NC}"
echo -e "${RED}  BLOCKCHAIN RESET - ALL DATA WILL BE LOST${NC}"
echo -e "${RED}=========================================${NC}"
echo ""
echo -e "${YELLOW}This will:${NC}"
echo "  - Stop all blockchain containers"
echo "  - Remove all blocks and transaction data"
echo "  - Clear MySQL evidence records"
echo "  - Reset explorer databases"
echo "  - Remove chaincode containers"
echo ""
echo -e "${RED}⚠  WARNING: This cannot be undone!${NC}"
echo ""
read -p "Are you sure you want to continue? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Aborted."
    exit 1
fi
echo ""

# 1. Stop explorers
echo -e "${YELLOW}[1/8] Stopping explorers...${NC}"
docker-compose -f docker-compose-explorers.yml down -v
echo -e "${GREEN}✓ Explorers stopped${NC}"
echo ""

# 2. Stop blockchains
echo -e "${YELLOW}[2/8] Stopping blockchains...${NC}"
docker-compose -f docker-compose-hot.yml down -v
docker-compose -f docker-compose-cold.yml down -v
echo -e "${GREEN}✓ Blockchains stopped${NC}"
echo ""

# 3. Remove chaincode containers
echo -e "${YELLOW}[3/8] Removing chaincode containers...${NC}"
docker rm -f $(docker ps -aq -f name=dev-peer) 2>/dev/null || true
echo -e "${GREEN}✓ Chaincode containers removed${NC}"
echo ""

# 4. Remove chaincode images
echo -e "${YELLOW}[4/8] Removing chaincode images...${NC}"
docker rmi -f $(docker images -q -f reference=dev-peer*) 2>/dev/null || true
echo -e "${GREEN}✓ Chaincode images removed${NC}"
echo ""

# 5. Clear MySQL evidence data
echo -e "${YELLOW}[5/8] Clearing MySQL evidence records...${NC}"
docker exec mysql-coc mysql -ucocuser -pcocpassword -e "DROP TABLE IF EXISTS evidence_metadata;" coc_evidence 2>/dev/null || true
docker exec mysql-coc mysql -ucocuser -pcocpassword -e "DROP TABLE IF EXISTS custody_events;" coc_evidence 2>/dev/null || true
docker exec mysql-coc mysql -ucocuser -pcocpassword -e "DROP TABLE IF EXISTS access_logs;" coc_evidence 2>/dev/null || true
docker exec mysql-coc mysql -ucocuser -pcocpassword -e "DROP TABLE IF EXISTS ipfs_pins;" coc_evidence 2>/dev/null || true
echo -e "${GREEN}✓ MySQL evidence records cleared${NC}"
echo ""

# 6. Reload MySQL schema
echo -e "${YELLOW}[6/8] Reloading MySQL schema...${NC}"
# Use root to load schema (needed for GRANT statements)
docker exec -i mysql-coc mysql -uroot -prootpassword coc_evidence < shared/database/init/01-schema.sql 2>&1 | grep -v "Warning: Using a password" || {
    echo -e "${YELLOW}  Schema reload from file failed, creating manually...${NC}"
    docker exec -i mysql-coc mysql -uroot -prootpassword coc_evidence <<'EOF'
CREATE TABLE IF NOT EXISTS evidence_metadata (
    evidence_id VARCHAR(64) PRIMARY KEY,
    case_id VARCHAR(64) NOT NULL,
    evidence_type VARCHAR(50) NOT NULL,
    file_size BIGINT,
    ipfs_hash VARCHAR(128),
    sha256_hash VARCHAR(64) NOT NULL,
    collected_timestamp TIMESTAMP NOT NULL,
    collected_by VARCHAR(128),
    location VARCHAR(255),
    description TEXT,
    blockchain_type ENUM('hot', 'cold') NOT NULL,
    transaction_id VARCHAR(128),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_case_id (case_id),
    INDEX idx_blockchain_type (blockchain_type),
    INDEX idx_collected_timestamp (collected_timestamp)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
EOF
}
echo -e "${GREEN}✓ MySQL schema reloaded${NC}"
echo ""

# 7. Restart blockchains
echo -e "${YELLOW}[7/8] Restarting blockchains...${NC}"
docker-compose -f docker-compose-hot.yml up -d
sleep 10
docker-compose -f docker-compose-cold.yml up -d
sleep 10
echo -e "${GREEN}✓ Blockchains restarted${NC}"
echo ""

# 8. Create channels
echo -e "${YELLOW}[8/8] Creating channels...${NC}"

# Hot channel
docker exec cli peer channel create \
    -o orderer.hot.coc.com:7050 \
    -c hotchannel \
    -f /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/hotchannel.tx \
    --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/tlscacerts/tlsca.hot.coc.com-cert.pem

sleep 3

# Join peers to hot channel
docker exec cli peer channel join -b hotchannel.block
docker exec -e CORE_PEER_ADDRESS=peer0.forensiclab.hot.coc.com:8051 \
    -e CORE_PEER_LOCALMSPID=ForensicLabMSP \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/forensiclab.hot.coc.com/peers/peer0.forensiclab.hot.coc.com/tls/ca.crt \
    -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/forensiclab.hot.coc.com/users/Admin@forensiclab.hot.coc.com/msp \
    cli peer channel join -b hotchannel.block

sleep 3

# Cold channel
docker exec cli-cold peer channel create \
    -o orderer.cold.coc.com:7150 \
    -c coldchannel \
    -f /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/coldchannel.tx \
    --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/msp/tlscacerts/tlsca.cold.coc.com-cert.pem

sleep 3

# Join peer to cold channel
docker exec cli-cold peer channel join -b coldchannel.block

echo -e "${GREEN}✓ Channels created${NC}"
echo ""

# Show blockchain heights
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  Blockchain Heights After Reset        ${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

HOT_INFO=$(docker exec cli peer channel getinfo -c hotchannel 2>/dev/null | grep -oP '(?<="height":)\d+' || echo "1")
COLD_INFO=$(docker exec cli-cold peer channel getinfo -c coldchannel 2>/dev/null | grep -oP '(?<="height":)\d+' || echo "1")

echo -e "${GREEN}Hot Blockchain Height:  $HOT_INFO${NC}"
echo -e "${GREEN}Cold Blockchain Height: $COLD_INFO${NC}"
echo ""

echo -e "${YELLOW}Next steps:${NC}"
echo "1. Deploy chaincode: ./deploy-chaincode.sh"
echo "2. Start explorers: ./start-explorers.sh"
echo "3. Start webapp: ./launch-webapp.sh"
echo ""
echo -e "${GREEN}✓ Reset complete! Blockchains are at height 1 (genesis block)${NC}"
echo ""
