#!/bin/bash
set -e

echo "======================================"
echo "Packaging Chaincode"
echo "======================================"

cd ~/Desktop/Smart-contract-main/chaincode

# Vendor dependencies
echo "Step 1: Vendoring dependencies..."
go mod tidy
go mod vendor
echo "✓ Dependencies vendored"

# Package
echo "Step 2: Packaging..."
cd ~/Desktop/Smart-contract-main

peer lifecycle chaincode package dfir.tar.gz \
    --path ./chaincode \
    --lang golang \
    --label dfir_1.0

echo "✓ Chaincode packaged: dfir.tar.gz"
ls -lh dfir.tar.gz
