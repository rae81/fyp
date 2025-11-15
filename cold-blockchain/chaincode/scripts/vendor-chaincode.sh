#!/bin/bash
set -e

echo "======================================"
echo "Vendoring Chaincode Dependencies"
echo "======================================"

cd ~/Desktop/Smart-contract-main/chaincode

echo "Step 1: Download dependencies..."
go mod download
go mod tidy

echo "Step 2: Vendor all dependencies..."
go mod vendor

echo ""
echo "✓ Vendoring complete!"
echo "  Vendor size: $(du -sh vendor/ 2>/dev/null | cut -f1 || echo 'N/A')"
