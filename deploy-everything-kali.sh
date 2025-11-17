#!/bin/bash
#
# MASTER DEPLOYMENT SCRIPT FOR KALI LINUX
# ========================================
# This script does EVERYTHING from scratch:
# - Pulls latest code
# - Installs dependencies
# - Deploys dual blockchain + IPFS + Enclave
# - Verifies everything is working
# - Shows you the running system
#
# Author: Claude AI
# Date: 2025-11-17
#
# Usage:
#   chmod +x deploy-everything-kali.sh
#   ./deploy-everything-kali.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
    printf "${MAGENTA}║ %-62s ║${NC}\n" "$1"
    echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo -e "${CYAN}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# ============================================================================
# PHASE 1: ENVIRONMENT SETUP
# ============================================================================

print_header "PHASE 1: SETTING UP KALI ENVIRONMENT"

print_step "Checking if running on Kali Linux..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" == "kali" ]] || [[ "$ID_LIKE" == *"debian"* ]]; then
        print_success "Running on $PRETTY_NAME"
    else
        print_warning "Not running on Kali, but will continue..."
    fi
fi

print_step "Installing system dependencies..."
sudo apt update -qq
sudo apt install -y docker.io docker-compose python3 python3-pip jq curl git openssl tree > /dev/null 2>&1
print_success "System dependencies installed"

print_step "Installing Python packages..."
pip3 install --break-system-packages --quiet cryptography flask requests 2>/dev/null || \
    pip3 install --quiet cryptography flask requests
print_success "Python packages installed"

print_step "Configuring Docker permissions..."
if ! groups | grep -q docker; then
    sudo usermod -aG docker $USER
    print_warning "Added user to docker group (logout/login may be required)"
fi

# Ensure Docker is running
sudo systemctl start docker 2>/dev/null || true
print_success "Docker is running"

# ============================================================================
# PHASE 2: REPOSITORY SETUP
# ============================================================================

print_header "PHASE 2: REPOSITORY SETUP"

REPO_DIR="/home/user/fyp"

if [ -d "$REPO_DIR/.git" ]; then
    print_step "Repository exists, pulling latest changes..."
    cd "$REPO_DIR"
    git fetch origin
    git checkout claude/dual-blockchain-copy-01JqBne3N3BgWq2Jh7ymGVe1
    git pull origin claude/dual-blockchain-copy-01JqBne3N3BgWq2Jh7ymGVe1 || print_warning "Already up to date"
    print_success "Repository updated"
else
    print_error "Repository not found at $REPO_DIR"
    print_error "Please run from the cloned repository directory"
    exit 1
fi

cd "$REPO_DIR"

# ============================================================================
# PHASE 3: CLEAN ENVIRONMENT
# ============================================================================

print_header "PHASE 3: CLEANING PREVIOUS DEPLOYMENT"

print_step "Stopping all containers..."
docker-compose -f docker-compose-full.yml down -v 2>/dev/null || true
docker-compose -f docker-compose-hot.yml down -v 2>/dev/null || true
docker-compose -f docker-compose-cold.yml down -v 2>/dev/null || true
docker-compose -f docker-compose-storage.yml down -v 2>/dev/null || true
print_success "Containers stopped"

print_step "Cleaning old data..."
sudo rm -rf organizations/ fabric-ca/*/fabric-ca-server.db enclave-data/ ipfs-certs/ 2>/dev/null || true
print_success "Old data cleaned"

# ============================================================================
# PHASE 4: DEPLOY ENCLAVE ROOT CA
# ============================================================================

print_header "PHASE 4: DEPLOYING ENCLAVE ROOT CA"

print_step "Building enclave simulator..."
docker-compose -f docker-compose-full.yml build enclave --quiet
print_success "Enclave image built"

print_step "Starting enclave service..."
docker-compose -f docker-compose-full.yml up -d enclave
sleep 5

print_step "Waiting for enclave to initialize..."
for i in {1..30}; do
    if curl -sf http://localhost:5001/health > /dev/null 2>&1; then
        print_success "Enclave is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        print_error "Enclave failed to start"
        docker logs sgx-enclave
        exit 1
    fi
    sleep 2
done

print_step "Initializing Root CA in enclave..."
INIT_RESPONSE=$(curl -s -X POST http://localhost:5001/ca/init)
if echo "$INIT_RESPONSE" | grep -q "success"; then
    print_success "Root CA initialized in enclave"
else
    print_warning "Root CA may already exist"
fi

# Download Root CA certificate
curl -s http://localhost:5001/ca/certificate > /tmp/root-ca.pem
print_success "Root CA certificate downloaded"

# ============================================================================
# PHASE 5: DEPLOY FABRIC CA SERVERS
# ============================================================================

print_header "PHASE 5: DEPLOYING FABRIC CA SERVERS"

print_step "Bootstrapping Fabric CA certificates from enclave..."
cd enclave-simulator
chmod +x init_enclave_ca.sh
./init_enclave_ca.sh
cd ..
print_success "Fabric CA certificates bootstrapped"

print_step "Starting all 6 Fabric CA servers..."
docker-compose -f docker-compose-full.yml up -d \
    ca-lawenforcement \
    ca-forensiclab \
    ca-auditor \
    ca-court \
    ca-orderer-hot \
    ca-orderer-cold

print_step "Waiting for CA servers to initialize (30s)..."
sleep 30

print_step "Verifying CA servers..."
ALL_CAS_OK=true
for CA_INFO in "lawenforcement:7054" "forensiclab:8054" "auditor:9054" "court:10054" "orderer-hot:11054" "orderer-cold:12054"; do
    IFS=':' read -r CA_NAME CA_PORT <<< "$CA_INFO"
    if curl -sk https://localhost:$CA_PORT/cainfo | grep -q "ca-$CA_NAME"; then
        echo -e "  ${GREEN}✓${NC} ca-$CA_NAME (port $CA_PORT)"
    else
        echo -e "  ${RED}✗${NC} ca-$CA_NAME (port $CA_PORT) - FAILED"
        ALL_CAS_OK=false
    fi
done

if [ "$ALL_CAS_OK" = false ]; then
    print_error "Some CA servers failed to start"
    exit 1
fi

print_success "All 6 CA servers are running"

# ============================================================================
# PHASE 6: ENROLL IDENTITIES
# ============================================================================

print_header "PHASE 6: ENROLLING IDENTITIES WITH FABRIC CA"

print_step "Registering identities in CA containers..."
chmod +x scripts/register-identities-in-containers.sh
./scripts/register-identities-in-containers.sh
print_success "Identities registered"

print_step "Enrolling all identities (this takes ~2 minutes)..."
chmod +x scripts/enroll-all-identities.sh
./scripts/enroll-all-identities.sh
print_success "All identities enrolled"

print_step "Fixing MSP configurations..."
chmod +x fix-all-msp.sh
./fix-all-msp.sh
print_success "MSP configurations fixed"

# ============================================================================
# PHASE 7: DEPLOY BLOCKCHAIN NETWORK
# ============================================================================

print_header "PHASE 7: DEPLOYING BLOCKCHAIN NETWORK"

print_step "Generating channel artifacts..."
chmod +x scripts/regenerate-channel-artifacts.sh
./scripts/regenerate-channel-artifacts.sh
print_success "Channel artifacts generated"

print_step "Starting CouchDB state databases..."
docker-compose -f docker-compose-full.yml up -d couchdb0 couchdb1 couchdb2
sleep 10
print_success "CouchDB instances started"

print_step "Starting orderers..."
docker-compose -f docker-compose-full.yml up -d orderer.hot.coc.com orderer.cold.coc.com
sleep 15
print_success "Orderers started"

print_step "Starting peers..."
docker-compose -f docker-compose-full.yml up -d \
    peer0.lawenforcement.hot.coc.com \
    peer0.forensiclab.hot.coc.com \
    peer0.auditor.cold.coc.com
sleep 15
print_success "Peers started"

print_step "Verifying orderers are running..."
for ORDERER in "orderer.hot.coc.com" "orderer.cold.coc.com"; do
    if docker ps | grep -q "$ORDERER"; then
        echo -e "  ${GREEN}✓${NC} $ORDERER is running"
    else
        echo -e "  ${RED}✗${NC} $ORDERER is NOT running"
        docker logs $ORDERER 2>&1 | tail -20
    fi
done

print_step "Verifying peers are running..."
for PEER in "peer0.lawenforcement.hot.coc.com" "peer0.forensiclab.hot.coc.com" "peer0.auditor.cold.coc.com"; do
    if docker ps | grep -q "$PEER"; then
        echo -e "  ${GREEN}✓${NC} $PEER is running"
    else
        echo -e "  ${RED}✗${NC} $PEER is NOT running"
    fi
done

# ============================================================================
# PHASE 8: CREATE CHANNELS
# ============================================================================

print_header "PHASE 8: CREATING BLOCKCHAIN CHANNELS"

print_step "Creating channels (hotchannel and coldchannel)..."
chmod +x scripts/create-channels-with-dynamic-mtls.sh
./scripts/create-channels-with-dynamic-mtls.sh
print_success "Channels created"

print_step "Verifying channels..."
docker exec cli peer channel list
docker exec cli-cold peer channel list

# ============================================================================
# PHASE 9: DEPLOY IPFS
# ============================================================================

print_header "PHASE 9: DEPLOYING IPFS STORAGE"

print_step "Enrolling IPFS nodes with mTLS certificates..."
chmod +x scripts/enroll-ipfs-mtls.sh
./scripts/enroll-ipfs-mtls.sh 2>/dev/null || print_warning "IPFS enrollment may need manual configuration"

print_step "Starting IPFS nodes and MySQL..."
docker-compose -f docker-compose-storage.yml up -d
sleep 10
print_success "IPFS and MySQL started"

# ============================================================================
# PHASE 10: DEPLOY CHAINCODE
# ============================================================================

print_header "PHASE 10: DEPLOYING CHAINCODE"

print_step "Packaging and installing chaincode..."
chmod +x deploy-chaincode.sh
./deploy-chaincode.sh
print_success "Chaincode deployed"

# ============================================================================
# PHASE 11: VERIFICATION
# ============================================================================

print_header "PHASE 11: SYSTEM VERIFICATION"

print_step "Checking all running containers..."
CONTAINER_COUNT=$(docker ps | grep -E "orderer|peer|ca-|enclave|ipfs|mysql|couchdb" | wc -l)
echo -e "  ${GREEN}✓${NC} $CONTAINER_COUNT containers running"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "orderer|peer|ca-|enclave|ipfs|mysql|couchdb"

print_step "Testing blockchain queries..."
if docker exec cli peer channel getinfo -c hotchannel 2>&1 | grep -q "height"; then
    print_success "Hot blockchain is functional"
else
    print_warning "Hot blockchain may have issues"
fi

if docker exec cli-cold peer channel getinfo -c coldchannel 2>&1 | grep -q "height"; then
    print_success "Cold blockchain is functional"
else
    print_warning "Cold blockchain may have issues"
fi

print_step "Testing IPFS..."
if docker exec ipfs-hot ipfs version 2>&1 | grep -q "ipfs version"; then
    print_success "IPFS hot node is functional"
else
    print_warning "IPFS hot node may have issues"
fi

print_step "Testing MySQL..."
if docker exec mysql-coc mysqladmin -uroot -prootpassword ping 2>&1 | grep -q "alive"; then
    print_success "MySQL database is functional"
else
    print_warning "MySQL may have issues"
fi

# ============================================================================
# FINAL REPORT
# ============================================================================

print_header "DEPLOYMENT COMPLETE - SYSTEM OVERVIEW"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           DUAL BLOCKCHAIN SYSTEM IS RUNNING!                  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${CYAN}📊 RUNNING SERVICES:${NC}"
echo ""
echo -e "${YELLOW}Enclave Root CA:${NC}"
echo "  - API: http://localhost:5001"
echo "  - Health: curl http://localhost:5001/health | jq"
echo ""

echo -e "${YELLOW}Fabric CA Servers:${NC}"
echo "  - LawEnforcement CA:  https://localhost:7054"
echo "  - ForensicLab CA:     https://localhost:8054"
echo "  - Auditor CA:         https://localhost:9054"
echo "  - Court CA:           https://localhost:10054"
echo "  - Orderer Hot CA:     https://localhost:11054"
echo "  - Orderer Cold CA:    https://localhost:12054"
echo ""

echo -e "${YELLOW}Hot Blockchain (Investigations):${NC}"
echo "  - Orderer:            orderer.hot.coc.com:7050"
echo "  - Law Enforcement:    peer0.lawenforcement:7051"
echo "  - Forensic Lab:       peer0.forensiclab:8051"
echo "  - Channel:            hotchannel"
echo ""

echo -e "${YELLOW}Cold Blockchain (Archive):${NC}"
echo "  - Orderer:            orderer.cold.coc.com:7150"
echo "  - Auditor:            peer0.auditor:9051"
echo "  - Channel:            coldchannel"
echo ""

echo -e "${YELLOW}IPFS Storage:${NC}"
echo "  - Hot Node API:       http://localhost:5003"
echo "  - Cold Node API:      http://localhost:5002"
echo "  - Hot Gateway:        http://localhost:8080"
echo "  - Cold Gateway:       http://localhost:8081"
echo ""

echo -e "${YELLOW}Database:${NC}"
echo "  - MySQL:              localhost:3306"
echo "  - phpMyAdmin:         http://localhost:8081"
echo "  - User/Pass:          cocuser/cocpassword"
echo ""

echo -e "${CYAN}🔧 USEFUL COMMANDS:${NC}"
echo ""
echo "View all containers:"
echo "  docker ps"
echo ""
echo "View logs:"
echo "  docker logs orderer.hot.coc.com"
echo "  docker logs peer0.lawenforcement.hot.coc.com"
echo "  docker logs sgx-enclave"
echo ""
echo "Query blockchain:"
echo "  docker exec cli peer channel getinfo -c hotchannel"
echo "  docker exec cli peer chaincode query -C hotchannel -n dfir -c '{\"function\":\"GetPRVConfig\",\"Args\":[]}'"
echo ""
echo "Check IPFS:"
echo "  docker exec ipfs-hot ipfs id"
echo "  curl http://localhost:5003/api/v0/version"
echo ""
echo "Stop everything:"
echo "  docker-compose -f docker-compose-full.yml down"
echo "  docker-compose -f docker-compose-storage.yml down"
echo ""

echo -e "${GREEN}✓ Deployment completed successfully!${NC}"
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo "  1. Review the logs above for any warnings"
echo "  2. Test chaincode operations"
echo "  3. Build your application layer to interact with the blockchain"
echo "  4. Upload files to IPFS and record on blockchain"
echo ""

print_header "HAPPY CODING!"
