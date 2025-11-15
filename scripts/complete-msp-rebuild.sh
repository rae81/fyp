#!/bin/bash
# Complete MSP rebuild script - fixes all certificate issues

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Complete MSP Rebuild - Fixing All Certificate Issues         ║"
echo "╚════════════════════════════════════════════════════════════════╝"

cd "$PROJECT_ROOT"

# Step 1: Stop all blockchain containers
echo ""
echo "[1/9] Stopping all blockchain containers..."
docker-compose -f docker-compose-hot.yml -f docker-compose-cold.yml down 2>/dev/null || true
echo "✓ Containers stopped"

# Step 2: Start CA servers
echo ""
echo "[2/9] Starting CA servers..."
docker-compose -f docker-compose-full.yml up -d ca-lawenforcement ca-forensiclab ca-auditor ca-court ca-orderer-hot ca-orderer-cold
echo "✓ CA servers started"
echo "Waiting for CA servers to initialize..."
sleep 10

# Step 3: Clean up ALL old MSP directories
echo ""
echo "[3/9] Cleaning up old MSP directories..."
rm -rf organizations/ordererOrganizations/*/orderers/*/msp
rm -rf organizations/ordererOrganizations/*/users/*/msp
rm -rf organizations/ordererOrganizations/*/msp
rm -rf organizations/peerOrganizations/*/peers/*/msp
rm -rf organizations/peerOrganizations/*/users/*/msp
rm -rf organizations/peerOrganizations/*/msp
echo "✓ Old MSPs removed"

# Step 4: Re-enroll all identities
echo ""
echo "[4/9] Re-enrolling all identities with correct CA certificates..."
./scripts/enroll-all-identities.sh
echo "✓ All identities re-enrolled"

# Step 5: Clean up unwanted CA certificates from enrollment
echo ""
echo "[5/9] Cleaning up unwanted CA certificates..."
# Remove localhost-* files that contain root CA instead of intermediate CA
find organizations -type f -name "localhost-*.pem" -delete
echo "✓ Removed localhost CA certificate files"

# Step 6: Update ALL MSP directories with correct CA certificates
echo ""
echo "[6/9] Updating all MSP CA certificates..."

# Function to update CA certs in MSP directory
update_msp_ca_certs() {
    local MSP_DIR=$1
    local CA_CERT=$2

    if [ -d "$MSP_DIR" ]; then
        # Ensure directories exist (not files)
        rm -f "$MSP_DIR/cacerts" 2>/dev/null || true
        rm -f "$MSP_DIR/tlscacerts" 2>/dev/null || true
        mkdir -p "$MSP_DIR/cacerts"
        mkdir -p "$MSP_DIR/tlscacerts"

        # Copy CA certificate
        cp "$CA_CERT" "$MSP_DIR/cacerts/ca-cert.pem"
        cp "$CA_CERT" "$MSP_DIR/tlscacerts/ca-cert.pem"
    fi
}

# Update hot orderer MSPs
update_msp_ca_certs "organizations/ordererOrganizations/hot.coc.com/msp" "fabric-ca/orderer-hot/ca-cert.pem"
update_msp_ca_certs "organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp" "fabric-ca/orderer-hot/ca-cert.pem"
update_msp_ca_certs "organizations/ordererOrganizations/hot.coc.com/users/Admin@hot.coc.com/msp" "fabric-ca/orderer-hot/ca-cert.pem"

# Update cold orderer MSPs
update_msp_ca_certs "organizations/ordererOrganizations/cold.coc.com/msp" "fabric-ca/orderer-cold/ca-cert.pem"
update_msp_ca_certs "organizations/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/msp" "fabric-ca/orderer-cold/ca-cert.pem"
update_msp_ca_certs "organizations/ordererOrganizations/cold.coc.com/users/Admin@cold.coc.com/msp" "fabric-ca/orderer-cold/ca-cert.pem"

# Update law enforcement MSPs
update_msp_ca_certs "organizations/peerOrganizations/lawenforcement.hot.coc.com/msp" "fabric-ca/lawenforcement/ca-cert.pem"
update_msp_ca_certs "organizations/peerOrganizations/lawenforcement.hot.coc.com/peers/peer0.lawenforcement.hot.coc.com/msp" "fabric-ca/lawenforcement/ca-cert.pem"
update_msp_ca_certs "organizations/peerOrganizations/lawenforcement.hot.coc.com/users/Admin@lawenforcement.hot.coc.com/msp" "fabric-ca/lawenforcement/ca-cert.pem"

# Update forensiclab MSPs
update_msp_ca_certs "organizations/peerOrganizations/forensiclab.hot.coc.com/msp" "fabric-ca/forensiclab/ca-cert.pem"
update_msp_ca_certs "organizations/peerOrganizations/forensiclab.hot.coc.com/peers/peer0.forensiclab.hot.coc.com/msp" "fabric-ca/forensiclab/ca-cert.pem"
update_msp_ca_certs "organizations/peerOrganizations/forensiclab.hot.coc.com/users/Admin@forensiclab.hot.coc.com/msp" "fabric-ca/forensiclab/ca-cert.pem"

# Update auditor MSPs
update_msp_ca_certs "organizations/peerOrganizations/auditor.cold.coc.com/msp" "fabric-ca/auditor/ca-cert.pem"
update_msp_ca_certs "organizations/peerOrganizations/auditor.cold.coc.com/peers/peer0.auditor.cold.coc.com/msp" "fabric-ca/auditor/ca-cert.pem"
update_msp_ca_certs "organizations/peerOrganizations/auditor.cold.coc.com/users/Admin@auditor.cold.coc.com/msp" "fabric-ca/auditor/ca-cert.pem"

# Update court MSPs
update_msp_ca_certs "organizations/peerOrganizations/court.coc.com/msp" "fabric-ca/court/ca-cert.pem"
update_msp_ca_certs "organizations/peerOrganizations/court.coc.com/users/Admin@court.coc.com/msp" "fabric-ca/court/ca-cert.pem"

echo "✓ All MSP CA certificates updated with correct SKI/AKI certs"

# Step 7: Apply MSP config fixes
echo ""
echo "[7/9] Applying MSP configuration (config.yaml and admincerts)..."
./scripts/fix-msp-config.sh
echo "✓ MSP configuration applied"

# Step 8: Regenerate channel artifacts
echo ""
echo "[8/9] Regenerating channel artifacts..."
mkdir -p channel-artifacts

# Generate genesis blocks
export FABRIC_CFG_PATH="$PROJECT_ROOT/hot-blockchain"
configtxgen -profile HotChainGenesis -outputBlock ./channel-artifacts/hotchannel.block -channelID hotchannel

export FABRIC_CFG_PATH="$PROJECT_ROOT/cold-blockchain"
configtxgen -profile ColdChainGenesis -outputBlock ./channel-artifacts/coldchannel.block -channelID coldchannel

# Generate anchor peer update transactions
echo "Generating anchor peer update transactions..."
export FABRIC_CFG_PATH="$PROJECT_ROOT/hot-blockchain"
configtxgen -profile HotChainChannel -outputAnchorPeersUpdate ./channel-artifacts/LawEnforcementMSPanchors.tx -channelID hotchannel -asOrg LawEnforcementMSP
configtxgen -profile HotChainChannel -outputAnchorPeersUpdate ./channel-artifacts/ForensicLabMSPanchors.tx -channelID hotchannel -asOrg ForensicLabMSP

export FABRIC_CFG_PATH="$PROJECT_ROOT/cold-blockchain"
configtxgen -profile ColdChainChannel -outputAnchorPeersUpdate ./channel-artifacts/AuditorMSPanchors.tx -channelID coldchannel -asOrg AuditorMSP

echo "✓ Channel artifacts and anchor peer transactions generated"

# Step 9: Start the blockchain network
echo ""
echo "[9/9] Starting blockchain network..."
docker-compose -f docker-compose-hot.yml -f docker-compose-cold.yml up -d

echo ""
echo "Waiting for network to initialize..."
sleep 15

# Verify all containers are running
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Network Status                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(peer|orderer)"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  ✓ MSP Rebuild Complete!                                      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo "  1. Verify orderers are running: docker logs orderer.hot.coc.com 2>&1 | tail -10"
echo "  2. Create channels: ./scripts/create-channels-with-dynamic-mtls.sh"
