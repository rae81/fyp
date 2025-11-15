#!/bin/bash
#
# Enroll IPFS Nodes with mTLS Certificates from Enclave Root CA
# =============================================================
# This script generates mTLS certificates for IPFS hot and cold nodes
# signed by the Enclave Root CA for secure evidence storage.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENCLAVE_URL="${ENCLAVE_URL:-http://localhost:5001}"
IPFS_CERT_DIR="$PROJECT_ROOT/ipfs-certs"

echo "================================================================"
echo "IPFS mTLS Certificate Enrollment via Enclave Root CA"
echo "================================================================"

# Create certificate directories
mkdir -p "$IPFS_CERT_DIR/hot"
mkdir -p "$IPFS_CERT_DIR/cold"

# Wait for enclave
echo "Waiting for enclave service..."
until curl -sf "$ENCLAVE_URL/health" > /dev/null; do
    echo "  Enclave not ready, waiting..."
    sleep 2
done
echo "✓ Enclave service ready"

# Download Root CA certificate
echo "Downloading Root CA certificate..."
curl -s "$ENCLAVE_URL/ca/certificate" > "$IPFS_CERT_DIR/root-ca.pem"
echo "✓ Root CA downloaded"

# ============================================================================
# Function to generate IPFS node certificate
# ============================================================================
generate_ipfs_cert() {
    local NODE_NAME=$1  # "hot" or "cold"
    local NODE_HOST=$2  # "ipfs.hot.coc.com" or "ipfs.cold.coc.com"
    local CERT_DIR="$IPFS_CERT_DIR/$NODE_NAME"

    echo ""
    echo "Generating certificate for IPFS $NODE_NAME node..."

    # Generate private key
    echo "  1. Generating private key..."
    openssl genrsa -out "$CERT_DIR/ipfs-key.pem" 2048

    # Create certificate signing request
    echo "  2. Creating CSR..."
    openssl req -new -key "$CERT_DIR/ipfs-key.pem" \
        -out "$CERT_DIR/ipfs-csr.pem" \
        -subj "/C=US/ST=California/L=San Francisco/O=DFIR IPFS/OU=Evidence Storage/CN=$NODE_HOST"

    # Get CSR content
    CSR_CONTENT=$(cat "$CERT_DIR/ipfs-csr.pem")

    # Sign with enclave Root CA
    echo "  3. Requesting signature from enclave..."
    CERT_RESPONSE=$(curl -s -X POST "$ENCLAVE_URL/ca/sign" \
        -H "Content-Type: application/json" \
        -d "{\"csr\": $(echo "$CSR_CONTENT" | jq -Rs .), \"type\": \"peer\", \"validity_days\": 825}")

    # Extract certificate
    echo "$CERT_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['certificate'])" > "$CERT_DIR/ipfs-cert.pem"

    # Create certificate chain
    cat "$CERT_DIR/ipfs-cert.pem" "$IPFS_CERT_DIR/root-ca.pem" > "$CERT_DIR/ipfs-chain.pem"

    # Set proper permissions (private key must be protected)
    chmod 600 "$CERT_DIR/ipfs-key.pem"
    chmod 644 "$CERT_DIR/ipfs-cert.pem"
    chmod 644 "$CERT_DIR/ipfs-chain.pem"

    echo "  ✓ Certificate generated for IPFS $NODE_NAME"
    echo "    - Private Key:  $CERT_DIR/ipfs-key.pem"
    echo "    - Certificate:  $CERT_DIR/ipfs-cert.pem"
    echo "    - Chain:        $CERT_DIR/ipfs-chain.pem"
}

# ============================================================================
# Generate certificates for both IPFS nodes
# ============================================================================

generate_ipfs_cert "hot" "ipfs.hot.coc.com"
generate_ipfs_cert "cold" "ipfs.cold.coc.com"

echo ""
echo "================================================================"
echo "✓ IPFS mTLS Certificate Enrollment Complete"
echo "================================================================"
echo ""
echo "Certificate Storage:"
echo "  Hot Node:  $IPFS_CERT_DIR/hot/"
echo "  Cold Node: $IPFS_CERT_DIR/cold/"
echo "  Root CA:   $IPFS_CERT_DIR/root-ca.pem"
echo ""
echo "Next Steps:"
echo "  1. Configure IPFS to use these certificates"
echo "  2. Update docker-compose volumes to mount certs"
echo "  3. Enable IPFS TLS/SSL in configuration"
echo ""
echo "Example IPFS TLS Config:"
echo "  ipfs config --json Addresses.API '\"/ip4/0.0.0.0/tcp/5001/https\"'"
echo "  ipfs config --json API.HTTPHeaders.Access-Control-Allow-Origin '[\"https://localhost\"]'"
echo ""
