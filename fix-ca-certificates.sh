#!/bin/bash
#
# Fix for CA Certificate Issue - Add cert sign key usage
# This script regenerates the CA certificates with proper key usage flags
#

set -e

cd "$(dirname "$0")"
PROJECT_ROOT="$(pwd)"

echo "=== Fixing CA Certificate Issue ==="
echo ""

# Check if enclave is running
if ! curl -s http://localhost:5001/health > /dev/null 2>&1; then
    echo "❌ Enclave is not running. Starting it..."
    docker-compose -f docker-compose-full.yml up -d sgx-enclave
    sleep 10
fi

echo "✓ Enclave is running"
echo ""

# Stop CA containers
echo "Stopping CA containers..."
docker-compose -f docker-compose-full.yml stop ca-lawenforcement ca-forensiclab ca-auditor ca-court ca-orderer-hot ca-orderer-cold 2>/dev/null || true

# Remove bad certificates
echo "Removing invalid certificates..."
sudo rm -rf fabric-ca/*/ca-cert.pem
sudo rm -rf fabric-ca/*/ca-key.pem
sudo rm -rf fabric-ca/*/ca-chain.pem
sudo rm -rf fabric-ca/*/fabric-ca-server.db

echo "✓ Cleaned up bad certificates"
echo ""

# Re-run bootstrap to regenerate certificates
echo "Regenerating certificates with proper key usage..."
chmod +x fabric-ca/bootstrap-fabric-ca.sh
ENCLAVE_URL=http://localhost:5001 ./fabric-ca/bootstrap-fabric-ca.sh

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Certificates regenerated successfully"
    echo ""

    # Verify certificates
    echo "Verifying certificates..."
    for CA_DIR in fabric-ca/*/; do
        if [ -f "$CA_DIR/ca-cert.pem" ]; then
            CA_NAME=$(basename "$CA_DIR")
            echo -n "  $CA_NAME: "

            # Check for cert sign key usage
            if openssl x509 -in "$CA_DIR/ca-cert.pem" -noout -text | grep -q "Certificate Sign"; then
                echo "✓ Valid"
            else
                echo "✗ Missing cert sign usage"
            fi
        fi
    done

    echo ""
    echo "Restarting CA containers..."
    docker-compose -f docker-compose-full.yml up -d ca-lawenforcement ca-forensiclab ca-auditor ca-court ca-orderer-hot ca-orderer-cold

    echo ""
    echo "Waiting for CAs to start (30 seconds)..."
    sleep 30

    echo ""
    echo "Testing CA connectivity..."
    for PORT in 7054 8054 9054 10054 11054 12054; do
        echo -n "  Port $PORT: "
        if curl -sk https://localhost:$PORT/cainfo 2>/dev/null | jq -r '.result.CAName' > /dev/null 2>&1; then
            echo "✓ Running"
        else
            echo "✗ Not responding"
        fi
    done

    echo ""
    echo "=== Fix Complete ==="
    echo ""
    echo "If all CAs are running, you can continue with:"
    echo "  ./scripts/register-identities-in-containers.sh"
    echo "  ./scripts/enroll-all-identities.sh"
else
    echo "❌ Certificate regeneration failed!"
    echo ""
    echo "RECOMMENDED: Use quick setup instead:"
    echo "  docker-compose -f docker-compose-full.yml down -v"
    echo "  sudo rm -rf organizations/ fabric-ca/"
    echo "  ./scripts/quick-setup-cryptogen.sh"
    exit 1
fi
