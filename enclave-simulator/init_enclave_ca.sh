#!/bin/bash
#
# Initialize Enclave Root CA
# This script initializes the software enclave and generates the Root CA
#

set -e

ENCLAVE_URL="http://localhost:5001"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "======================================================================"
echo "Initializing Enclave Root CA for DFIR Blockchain"
echo "======================================================================"

# Check if enclave is running
echo "Checking enclave status..."
if ! curl -s "$ENCLAVE_URL/health" > /dev/null; then
    echo "❌ Enclave service is not running!"
    echo "   Start it with: docker-compose -f docker-compose-enclave.yml up -d"
    exit 1
fi

echo "✓ Enclave service is running"

# Get enclave info
echo ""
echo "Enclave Information:"
ENCLAVE_INFO=$(curl -s "$ENCLAVE_URL/enclave/info")
echo "$ENCLAVE_INFO" | python3 -m json.tool

# Check if Root CA already exists
ROOT_CA_INITIALIZED=$(echo "$ENCLAVE_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin)['root_ca_initialized'])")

if [ "$ROOT_CA_INITIALIZED" = "True" ]; then
    echo ""
    echo "⚠ Root CA already initialized in enclave"
    echo ""
    read -p "Do you want to reinitialize? This will invalidate all existing certificates! (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Keeping existing Root CA"
        exit 0
    fi

    echo ""
    echo "⚠ WARNING: Reinitializing will break all existing certificates!"
    echo "⚠ You will need to regenerate ALL certificates for ALL components!"
    echo ""
    read -p "Type 'REINIT' to confirm: " final_confirm
    if [ "$final_confirm" != "REINIT" ]; then
        echo "Cancelled"
        exit 0
    fi

    # Backup existing ca-cert.pem if it exists
    if [ -f "$PROJECT_DIR/organizations/fabric-ca/org1/ca-cert.pem" ]; then
        backup_dir="$PROJECT_DIR/backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_dir"
        echo "Backing up existing certificates to $backup_dir"
        cp -r "$PROJECT_DIR/organizations" "$backup_dir/"
    fi
fi

# Initialize Root CA in enclave
echo ""
echo "Generating Root CA in enclave..."
INIT_RESPONSE=$(curl -s -X POST "$ENCLAVE_URL/ca/init")

if echo "$INIT_RESPONSE" | grep -q "error"; then
    echo "❌ Failed to initialize Root CA:"
    echo "$INIT_RESPONSE" | python3 -m json.tool
    exit 1
fi

echo "✓ Root CA generated successfully"
echo ""
echo "Certificate Details:"
echo "$INIT_RESPONSE" | python3 -m json.tool

# Download Root CA certificate
echo ""
echo "Downloading Root CA certificate..."
curl -s "$ENCLAVE_URL/ca/certificate" -o "$PROJECT_DIR/enclave-data/root-ca.crt"

if [ ! -f "$PROJECT_DIR/enclave-data/root-ca.crt" ]; then
    echo "❌ Failed to download Root CA certificate"
    exit 1
fi

echo "✓ Root CA certificate saved to: $PROJECT_DIR/enclave-data/root-ca.crt"

# Display certificate info
echo ""
echo "Root CA Certificate Info:"
openssl x509 -in "$PROJECT_DIR/enclave-data/root-ca.crt" -text -noout | grep -A 2 "Subject:"
openssl x509 -in "$PROJECT_DIR/enclave-data/root-ca.crt" -text -noout | grep -A 2 "Validity"

# Extract MREnclave and MRSigner for blockchain registration
echo ""
echo "Enclave Measurements (for blockchain registration):"
echo "$ENCLAVE_INFO" | python3 -c "
import sys, json
info = json.load(sys.stdin)
print(f\"  MREnclave: {info['mr_enclave']}\")
print(f\"  MRSigner:  {info['mr_signer']}\")
print(f\"  TCB Level: {info['tcb_level']}\")
"

echo ""
echo "======================================================================"
echo "✓ Enclave Root CA Initialized Successfully"
echo "======================================================================"
echo ""
echo "Next steps:"
echo "  1. Generate certificates for Fabric components:"
echo "     ./generate_fabric_certs.sh"
echo ""
echo "  2. Register enclave with blockchain:"
echo "     peer chaincode invoke -C hotchannel -n dfir_chaincode \\"
echo "       -c '{\"function\":\"InitLedger\",\"Args\":[\"<pubkey>\",\"<mrenclave>\",\"<mrsigner>\"]}'"
echo ""
