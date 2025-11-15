#!/bin/bash
set -e

echo "======================================"
echo "Packaging Chaincode for Fabric"
echo "======================================"

CHAINCODE_NAME="dfir"
CHAINCODE_VERSION="1.0"
CHAINCODE_LABEL="${CHAINCODE_NAME}_${CHAINCODE_VERSION}"

cd "$(dirname "$0")/.."

if [ ! -d "vendor" ]; then
    echo "Vendor directory not found. Running vendor script..."
    ./scripts/vendor-chaincode.sh
fi

echo "Creating package..."
peer lifecycle chaincode package ${CHAINCODE_NAME}.tar.gz \
    --path . \
    --lang golang \
    --label ${CHAINCODE_LABEL}

echo ""
echo "✓ Package created: ${CHAINCODE_NAME}.tar.gz"
ls -lh ${CHAINCODE_NAME}.tar.gz
