#!/bin/bash
#
# Master Bootstrap Script for Complete DFIR Blockchain System
# ============================================================
# This script initializes the entire system with:
# - SGX Enclave Simulator (Root CA + Remote Attestation)
# - Fabric CA servers (dynamic cert issuance)
# - IPFS nodes (evidence storage)
# - Hyperledger Fabric (hot + cold blockchains)
# - All with dynamic mTLS certificates
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  DFIR Blockchain - Complete System Bootstrap                  ║"
echo "║  With SGX Enclave Root CA & Dynamic Certificate Issuance      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================================
# Step 1: Start Enclave Service
# ============================================================================
echo "=== Step 1: Starting SGX Enclave Simulator ==="
docker-compose -f docker-compose-full.yml up -d enclave

echo "Waiting for enclave to be ready..."
sleep 5
until curl -sf http://localhost:5001/health > /dev/null; do
    echo "  Enclave not ready, waiting..."
    sleep 2
done
echo "✓ Enclave service is running"

# Initialize Root CA in enclave
echo "Initializing Root CA in enclave..."
INIT_RESPONSE=$(curl -s -X POST http://localhost:5001/ca/init)
if echo "$INIT_RESPONSE" | grep -q "error.*already initialized"; then
    echo "✓ Root CA already initialized"
elif echo "$INIT_RESPONSE" | grep -q "success"; then
    echo "✓ Root CA initialized successfully"
    echo "$INIT_RESPONSE" | python3 -m json.tool
else
    echo "❌ Failed to initialize Root CA"
    echo "$INIT_RESPONSE"
    exit 1
fi

# Generate orderer keys in enclave
echo "Generating orderer private keys in enclave..."
curl -s -X POST http://localhost:5001/orderer/init -H "Content-Type: application/json" -d '{"chain":"hot"}' | python3 -m json.tool
curl -s -X POST http://localhost:5001/orderer/init -H "Content-Type: application/json" -d '{"chain":"cold"}' | python3 -m json.tool

# Get attestation quote
echo "Generating remote attestation quote..."
curl -s -X POST http://localhost:5001/enclave/attestation | python3 -m json.tool > enclave-attestation.json
echo "✓ Attestation quote saved to enclave-attestation.json"

echo ""

# ============================================================================
# Step 2: Bootstrap Fabric CA Servers
# ============================================================================
echo "=== Step 2: Bootstrapping Fabric CA Servers ==="
chmod +x fabric-ca/bootstrap-fabric-ca.sh
ENCLAVE_URL=http://localhost:5001 ./fabric-ca/bootstrap-fabric-ca.sh

echo ""

# ============================================================================
# Step 3: Start Fabric CA Servers
# ============================================================================
echo "=== Step 3: Starting Fabric CA Servers ==="
docker-compose -f docker-compose-full.yml up -d \
    ca-lawenforcement \
    ca-forensiclab \
    ca-auditor \
    ca-court \
    ca-orderer-hot \
    ca-orderer-cold

echo "Waiting for CA servers to initialize..."
sleep 10

echo ""

# ============================================================================
# Step 4: Enroll All Identities
# ============================================================================
echo "=== Step 4: Enrolling all identities with dynamic certificates ==="
chmod +x scripts/enroll-all-identities.sh
./scripts/enroll-all-identities.sh

echo ""

# ============================================================================
# Step 5: Start CouchDB
# ============================================================================
echo "=== Step 5: Starting CouchDB state databases ==="
docker-compose -f docker-compose-full.yml up -d couchdb0 couchdb1 couchdb2

echo "Waiting for CouchDB to initialize..."
sleep 5

echo ""

# ============================================================================
# Step 6: Start Orderers and Peers
# ============================================================================
echo "=== Step 6: Starting Orderers and Peers ==="
docker-compose -f docker-compose-full.yml up -d \
    orderer.hot.coc.com \
    orderer.cold.coc.com \
    peer0.lawenforcement.hot.coc.com \
    peer0.forensiclab.hot.coc.com \
    peer0.auditor.cold.coc.com

echo "Waiting for blockchain network to initialize..."
sleep 10

# Verify all containers are running
echo ""
echo "Verifying container status..."
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(enclave|ca-|peer0|orderer|couchdb)"

echo ""

# ============================================================================
# Step 7: Enroll IPFS Nodes with mTLS Certificates
# ============================================================================
echo "=== Step 7: Enrolling IPFS nodes with mTLS certificates ==="
chmod +x scripts/enroll-ipfs-mtls.sh
./scripts/enroll-ipfs-mtls.sh

echo ""

# ============================================================================
# Step 7.5: Start IPFS Nodes
# ============================================================================
echo "=== Step 7.5: Starting IPFS nodes with mTLS ==="
docker-compose -f docker-compose-full.yml up -d ipfs-hot ipfs-cold

sleep 5

echo "✓ IPFS nodes started with mTLS certificates"

echo ""

# ============================================================================
# Step 8: Create Channels
# ============================================================================
echo "=== Step 8: Creating blockchain channels ==="

# Generate channel configuration
echo "Generating channel configuration blocks..."
chmod +x scripts/regenerate-channel-artifacts.sh
./scripts/regenerate-channel-artifacts.sh

# Create and join channels
echo "Creating and joining channels..."
chmod +x scripts/create-channels.sh
./scripts/create-channels.sh

echo ""

# ============================================================================
# ============================================================================
# Step 9: Get Enclave Measurements for Chaincode Initialization
# ============================================================================
echo "=== Step 9: Extracting enclave measurements for chaincode ==="

# Get enclave information
ENCLAVE_INFO=$(curl -s http://localhost:5001/enclave/info)
export MRENCLAVE=$(echo "$ENCLAVE_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin)['mr_enclave'])")
export MRSIGNER=$(echo "$ENCLAVE_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin)['mr_signer'])")

# Get Root CA public key from enclave
curl -s http://localhost:5001/ca/certificate -o /tmp/enclave_root_ca.pem
export PUBLIC_KEY=$(openssl x509 -in /tmp/enclave_root_ca.pem -pubkey -noout | grep -v "BEGIN\|END" | tr -d '\n')

echo "✓ Extracted enclave measurements:"
echo "  MRENCLAVE: ${MRENCLAVE:0:32}..."
echo "  MRSIGNER:  ${MRSIGNER:0:32}..."
echo "  Public Key: ${PUBLIC_KEY:0:32}..."

echo ""

# ============================================================================
# Step 10: Deploy Chaincode with Enclave Attestation
# ============================================================================
echo "=== Step 10: Deploying chaincode with enclave attestation ==="
chmod +x deploy-chaincode.sh
./deploy-chaincode.sh

echo "✓ System bootstrap complete with chaincode deployed"

echo ""

# ============================================================================
# Final Status
# ============================================================================
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  DFIR Blockchain System - Status                               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

echo "✓ SGX Enclave Simulator:    http://localhost:5001"
echo "✓ Fabric CA (LawEnforcement):  https://localhost:7054"
echo "✓ Fabric CA (ForensicLab):     https://localhost:8054"
echo "✓ Fabric CA (Auditor):         https://localhost:9054"
echo "✓ Fabric CA (Court):           https://localhost:10054"
echo "✓ Fabric CA (Orderer Hot):     https://localhost:11054"
echo "✓ Fabric CA (Orderer Cold):    https://localhost:12054"
echo ""
echo "✓ Hot Orderer:   localhost:7050 (Admin: 7053)"
echo "✓ Cold Orderer:  localhost:7150 (Admin: 7153)"
echo ""
echo "✓ LawEnforcement Peer:  localhost:7051"
echo "✓ ForensicLab Peer:     localhost:8051"
echo "✓ Auditor Peer:         localhost:9051"
echo ""
echo "✓ IPFS Hot:   localhost:5001 (API), localhost:8080 (Gateway)"
echo "✓ IPFS Cold:  localhost:5002 (API), localhost:8081 (Gateway)"
echo ""
echo "Certificate Chain:"
echo "  SGX Enclave Root CA (sealed in enclave)"
echo "    ↓"
echo "  Fabric CA Intermediate CAs (per org)"
echo "    ↓"
echo "  Dynamically issued identity certificates (peers, orderers, users)"
echo ""
echo "Enclave Measurements (for attestation):"
curl -s http://localhost:5001/enclave/info | python3 -c "
import sys, json
info = json.load(sys.stdin)
print(f\"  MRENCLAVE: {info['mrenclave'][:32]}...\")
print(f\"  MRSIGNER:  {info['mrsigner'][:32]}...\")
print(f\"  Security Version: {info['security_version']}\")
"

echo ""
echo "Next steps:"
echo "  1. Deploy chaincode: ./scripts/deploy-chaincode.sh"
echo "  2. Test evidence upload: curl -X POST ..."
echo "  3. Test cross-chain transfer: ..."
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Ready for Testing                                             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
