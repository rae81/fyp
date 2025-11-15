#!/bin/bash
set -e

echo "======================================"
echo "Vendoring Chaincode Dependencies"
echo "======================================"

cd "$(dirname "$0")/.."

echo "Step 1: Download dependencies..."
go mod download
go mod tidy

echo "Step 2: Vendor all dependencies..."
go mod vendor

echo ""
echo "✓ Vendoring complete!"
echo "  Vendor size: $(du -sh vendor/ | cut -f1)"
