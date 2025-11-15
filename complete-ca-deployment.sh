#!/bin/bash
#
# Complete CA-Based Deployment - Run All Steps
# This script executes all steps needed for CA-based deployment
#

set -e

cd "$(dirname "$0")"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  Complete CA-Based Deployment${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""

# Step 1: Stop everything and clean
echo -e "${YELLOW}[Step 1/10] Stopping all containers and cleaning...${NC}"
docker-compose -f docker-compose-full.yml down -v 2>/dev/null || true
docker-compose -f docker-compose-hot.yml down -v 2>/dev/null || true
docker-compose -f docker-compose-cold.yml down -v 2>/dev/null || true

sudo rm -rf organizations/
sudo rm -rf fabric-ca/*/fabric-ca-server.db
echo -e "${GREEN}✓ Cleanup complete${NC}"
echo ""

# Step 2: Test CA certificate generation
echo -e "${YELLOW}[Step 2/10] Testing CA certificate generation...${NC}"
chmod +x test-and-fix-ca.sh
./test-and-fix-ca.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ CA certificate test failed!${NC}"
    echo -e "${YELLOW}The enclave may need to be rebuilt or there's a bug in certificate generation.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ CA certificates tested and bootstrapped${NC}"
echo ""

# Step 3: Start CA servers
echo -e "${YELLOW}[Step 3/10] Starting CA servers...${NC}"
docker-compose -f docker-compose-full.yml up -d \
  ca-lawenforcement \
  ca-forensiclab \
  ca-auditor \
  ca-court \
  ca-orderer-hot \
  ca-orderer-cold

echo "Waiting 60 seconds for CAs to fully initialize..."
sleep 60
echo -e "${GREEN}✓ CA servers started${NC}"
echo ""

# Step 4: Verify CAs are running
echo -e "${YELLOW}[Step 4/10] Verifying CA servers...${NC}"
ALL_CAS_OK=true
for PORT in 7054 8054 9054 10054 11054 12054; do
  echo -n "  Port $PORT: "
  if curl -sk https://localhost:$PORT/cainfo 2>/dev/null | jq -r '.result.CAName' > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Running${NC}"
  else
    echo -e "${RED}✗ Not responding${NC}"
    ALL_CAS_OK=false
  fi
done

if [ "$ALL_CAS_OK" = false ]; then
    echo -e "${RED}❌ Some CA servers are not responding!${NC}"
    echo -e "${YELLOW}Check logs with: docker logs ca-lawenforcement${NC}"
    exit 1
fi
echo -e "${GREEN}✓ All CA servers verified${NC}"
echo ""

# Step 5: Register identities
echo -e "${YELLOW}[Step 5/10] Registering identities inside CA containers...${NC}"
chmod +x scripts/register-identities-in-containers.sh
./scripts/register-identities-in-containers.sh
echo -e "${GREEN}✓ Identities registered${NC}"
echo ""

# Step 6: Enroll identities
echo -e "${YELLOW}[Step 6/10] Enrolling identities to get certificates...${NC}"
chmod +x scripts/enroll-all-identities.sh
./scripts/enroll-all-identities.sh
echo -e "${GREEN}✓ Identities enrolled${NC}"
echo ""

# Step 7: Verify organizations directory was created
if [ ! -d "organizations/ordererOrganizations" ] || [ ! -d "organizations/peerOrganizations" ]; then
    echo -e "${RED}❌ Organizations directory not created properly!${NC}"
    echo -e "${YELLOW}Enrollment may have failed. Check logs above.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Certificate structure verified${NC}"
echo ""

# Step 8: Generate channel artifacts
echo -e "${YELLOW}[Step 7/10] Generating channel artifacts...${NC}"
chmod +x scripts/regenerate-channel-artifacts.sh
./scripts/regenerate-channel-artifacts.sh
echo -e "${GREEN}✓ Channel artifacts generated${NC}"
echo ""

# Step 9: Update Docker Compose files
echo -e "${YELLOW}[Step 8/10] Updating Docker Compose for dynamic mTLS...${NC}"
chmod +x scripts/update-docker-compose-for-dynamic-mtls.sh
./scripts/update-docker-compose-for-dynamic-mtls.sh
echo -e "${GREEN}✓ Docker Compose files updated${NC}"
echo ""

# Step 10: Start blockchain network
echo -e "${YELLOW}[Step 9/10] Starting blockchain network...${NC}"
docker-compose -f docker-compose-hot.yml -f docker-compose-cold.yml up -d

echo "Waiting 90 seconds for network to stabilize..."
sleep 90
echo -e "${GREEN}✓ Blockchain network started${NC}"
echo ""

# Step 11: Verify orderers are running
echo -e "${YELLOW}Verifying orderers...${NC}"
if docker ps | grep -q "orderer.hot.coc.com"; then
    echo -e "${GREEN}✓ Hot orderer is running${NC}"
else
    echo -e "${RED}✗ Hot orderer not running${NC}"
    echo "Hot orderer logs:"
    docker logs orderer.hot.coc.com 2>&1 | tail -30
fi

if docker ps | grep -q "orderer.cold.coc.com"; then
    echo -e "${GREEN}✓ Cold orderer is running${NC}"
else
    echo -e "${RED}✗ Cold orderer not running${NC}"
    echo "Cold orderer logs:"
    docker logs orderer.cold.coc.com 2>&1 | tail -30
fi
echo ""

# Step 12: Create channels
echo -e "${YELLOW}[Step 10/10] Creating channels...${NC}"
chmod +x scripts/create-channels-with-dynamic-mtls.sh
./scripts/create-channels-with-dynamic-mtls.sh
echo -e "${GREEN}✓ Channels created${NC}"
echo ""

# Final verification
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  Deployment Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "${YELLOW}Verifying channels:${NC}"
echo "Hot blockchain:"
docker exec cli peer channel list

echo ""
echo "Cold blockchain:"
docker exec cli-cold peer channel list

echo ""
echo -e "${GREEN}Next step: Deploy chaincode${NC}"
echo -e "  ${YELLOW}./deploy-chaincode.sh${NC}"
echo ""
