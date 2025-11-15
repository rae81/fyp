#!/bin/bash

###############################################################################
# Complete DFIR Dual-Blockchain Deployment Script
# Deploys entire system with SGX Enclave Root CA and Dynamic mTLS
###############################################################################

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}    DFIR Dual-Blockchain Complete Deployment${NC}"
echo -e "${BLUE}    With SGX Enclave Root CA & Dynamic mTLS${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""

# Track deployment time
START_TIME=$(date +%s)

###############################################################################
# PHASE 1: PRE-DEPLOYMENT CHECKS
###############################################################################

echo -e "${YELLOW}[PHASE 1/7] Pre-Deployment Checks${NC}"
echo ""

# Check if running as root (needed for some operations)
if [ "$EUID" -eq 0 ]; then
    echo -e "${YELLOW}⚠ Running as root - this is acceptable for deployment${NC}"
fi

# Check for required commands
echo -e "${YELLOW}Checking required tools...${NC}"
for cmd in docker docker-compose fabric-ca-client; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}✗ $cmd not found!${NC}"
        echo -e "${RED}Please install $cmd before continuing${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ $cmd found${NC}"
done
echo ""

# Clean up previous deployment if requested
read -p "Clean up previous deployment? (y/N): " -n 1 -r CLEAN
echo
if [[ $CLEAN =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cleaning up previous deployment...${NC}"

    # Stop containers
    docker-compose -f docker-compose-hot.yml -f docker-compose-cold.yml down -v 2>/dev/null || true

    # Remove old certificates
    sudo rm -rf organizations/ 2>/dev/null || true

    # Remove CA databases
    sudo rm -rf fabric-ca/*/fabric-ca-server.db 2>/dev/null || true
    sudo rm -rf fabric-ca/*/msp 2>/dev/null || true

    echo -e "${GREEN}✓ Cleanup complete${NC}"
else
    echo -e "${YELLOW}Skipping cleanup - using existing state${NC}"
fi
echo ""

###############################################################################
# PHASE 2: START INFRASTRUCTURE
###############################################################################

echo -e "${YELLOW}[PHASE 2/7] Starting Infrastructure Services${NC}"
echo ""

echo -e "${YELLOW}Starting Enclave Root CA and Fabric CAs...${NC}"
./bootstrap-complete-system.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Infrastructure startup failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Infrastructure services started${NC}"
echo ""

# Wait for CAs to be fully ready
echo -e "${YELLOW}Waiting for CAs to be ready (30 seconds)...${NC}"
sleep 30
echo -e "${GREEN}✓ CAs ready${NC}"
echo ""

###############################################################################
# PHASE 3: IDENTITY REGISTRATION & ENROLLMENT
###############################################################################

echo -e "${YELLOW}[PHASE 3/7] Registering and Enrolling Identities${NC}"
echo ""

# Register identities inside CA containers
echo -e "${YELLOW}Registering identities (container-based workaround)...${NC}"
./scripts/register-identities-in-containers.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Identity registration failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All identities registered${NC}"
echo ""

# Enroll all identities from host
echo -e "${YELLOW}Enrolling identities (dynamic mTLS issuance)...${NC}"
./scripts/enroll-all-identities.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Identity enrollment failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All identities enrolled with dynamic mTLS certificates${NC}"
echo ""

# Verify certificate chain
echo -e "${YELLOW}Verifying certificate chain...${NC}"
ORDERER_CERT="$SCRIPT_DIR/organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/signcerts/cert.pem"
if [ -f "$ORDERER_CERT" ]; then
    openssl x509 -in "$ORDERER_CERT" -noout -issuer | grep -q "Fabric CA" && \
        echo -e "${GREEN}✓ Certificate chain verified: Enclave Root CA → Fabric CA → Identity${NC}"
else
    echo -e "${RED}✗ Certificate verification failed${NC}"
    exit 1
fi
echo ""

###############################################################################
# PHASE 4: CHANNEL ARTIFACTS GENERATION
###############################################################################

echo -e "${YELLOW}[PHASE 4/7] Generating Channel Artifacts${NC}"
echo ""

./scripts/regenerate-channel-artifacts.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Channel artifact generation failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Channel artifacts generated${NC}"
echo ""

# Verify artifacts
echo -e "${YELLOW}Verifying channel artifacts...${NC}"
if [ -f "hot-blockchain/channel-artifacts/hotchannel.block" ] && \
   [ -f "cold-blockchain/channel-artifacts/coldchannel.block" ]; then
    HOT_SIZE=$(stat -f%z "hot-blockchain/channel-artifacts/hotchannel.block" 2>/dev/null || stat -c%s "hot-blockchain/channel-artifacts/hotchannel.block" 2>/dev/null)
    COLD_SIZE=$(stat -f%z "cold-blockchain/channel-artifacts/coldchannel.block" 2>/dev/null || stat -c%s "cold-blockchain/channel-artifacts/coldchannel.block" 2>/dev/null)
    echo -e "${GREEN}✓ Hot channel genesis block: ${HOT_SIZE} bytes${NC}"
    echo -e "${GREEN}✓ Cold channel genesis block: ${COLD_SIZE} bytes${NC}"
else
    echo -e "${RED}✗ Channel artifacts missing!${NC}"
    exit 1
fi
echo ""

###############################################################################
# PHASE 5: UPDATE DOCKER COMPOSE FILES
###############################################################################

echo -e "${YELLOW}[PHASE 5/7] Updating Docker Compose for Dynamic mTLS${NC}"
echo ""

./scripts/update-docker-compose-for-dynamic-mtls.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Docker compose update failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Docker compose files updated${NC}"
echo ""

###############################################################################
# PHASE 6: START BLOCKCHAIN NETWORK
###############################################################################

echo -e "${YELLOW}[PHASE 6/7] Starting Blockchain Network${NC}"
echo ""

# Stop any running containers
echo -e "${YELLOW}Stopping any existing blockchain containers...${NC}"
docker-compose -f docker-compose-hot.yml -f docker-compose-cold.yml down 2>/dev/null || true
echo ""

# Start the blockchain network
echo -e "${YELLOW}Starting orderers and peers...${NC}"
docker-compose -f docker-compose-hot.yml -f docker-compose-cold.yml up -d

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Blockchain network startup failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Blockchain network started${NC}"
echo ""

# Wait for network to be ready
echo -e "${YELLOW}Waiting for network to initialize (45 seconds)...${NC}"
sleep 45
echo -e "${GREEN}✓ Network initialized${NC}"
echo ""

# Verify containers are running
echo -e "${YELLOW}Verifying container status...${NC}"
EXPECTED_CONTAINERS=("orderer.hot.coc.com" "orderer.cold.coc.com" "peer0.lawenforcement.hot.coc.com" "peer0.forensiclab.hot.coc.com" "peer0.auditor.cold.coc.com")
for container in "${EXPECTED_CONTAINERS[@]}"; do
    if docker ps | grep -q "$container"; then
        echo -e "${GREEN}✓ $container running${NC}"
    else
        echo -e "${RED}✗ $container not running!${NC}"
        docker logs "$container" 2>&1 | tail -20
        exit 1
    fi
done
echo ""

###############################################################################
# PHASE 7: CREATE CHANNELS
###############################################################################

echo -e "${YELLOW}[PHASE 7/7] Creating and Joining Channels${NC}"
echo ""

./scripts/create-channels-with-dynamic-mtls.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Channel creation failed!${NC}"
    echo -e "${YELLOW}Checking logs...${NC}"
    docker logs cli 2>&1 | tail -20
    exit 1
fi

echo -e "${GREEN}✓ Channels created and peers joined${NC}"
echo ""

###############################################################################
# DEPLOYMENT COMPLETE
###############################################################################

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

echo ""
echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}           DEPLOYMENT COMPLETE!${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""
echo -e "${GREEN}✓ Infrastructure: Enclave Root CA + 6 Fabric CAs${NC}"
echo -e "${GREEN}✓ Identities: All enrolled with dynamic mTLS certificates${NC}"
echo -e "${GREEN}✓ Certificate Chain: Enclave Root CA → Fabric CA → Identities${NC}"
echo -e "${GREEN}✓ Network: 2 Orderers + 3 Peers running${NC}"
echo -e "${GREEN}✓ Channels: hotchannel (4 orgs) + coldchannel (2 orgs)${NC}"
echo ""
echo -e "${YELLOW}Deployment Time: ${MINUTES}m ${SECONDS}s${NC}"
echo ""

# Network Summary
echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}           NETWORK SUMMARY${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""
echo -e "${YELLOW}HOT BLOCKCHAIN (hotchannel):${NC}"
echo -e "  Orderer:       orderer.hot.coc.com:7050"
echo -e "  Organizations:"
echo -e "    • LawEnforcementMSP  - peer0.lawenforcement.hot.coc.com:7051"
echo -e "    • ForensicLabMSP     - peer0.forensiclab.hot.coc.com:8051"
echo -e "    • CourtMSP           - (client-only)"
echo -e "    • AuditorMSP         - (read-only access)"
echo ""
echo -e "${YELLOW}COLD BLOCKCHAIN (coldchannel):${NC}"
echo -e "  Orderer:       orderer.cold.coc.com:7150"
echo -e "  Organizations:"
echo -e "    • AuditorMSP         - peer0.auditor.cold.coc.com:9051"
echo -e "    • CourtMSP           - (client-only)"
echo ""

# Next Steps
echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}           NEXT STEPS${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""
echo -e "${YELLOW}1. Verify Channel Status:${NC}"
echo -e "   docker exec cli peer channel list"
echo -e "   docker exec cli-cold peer channel list"
echo ""
echo -e "${YELLOW}2. Check Container Logs:${NC}"
echo -e "   docker logs orderer.hot.coc.com"
echo -e "   docker logs peer0.lawenforcement.hot.coc.com"
echo ""
echo -e "${YELLOW}3. Deploy Chaincode:${NC}"
echo -e "   ./scripts/deploy-evidence-chaincode.sh"
echo ""
echo -e "${YELLOW}4. Test Network:${NC}"
echo -e "   docker exec cli peer chaincode query ..."
echo ""
echo -e "${GREEN}Deployment logs saved to: deployment-$(date +%Y%m%d-%H%M%S).log${NC}"
echo ""
