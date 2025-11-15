#!/bin/bash

echo "========================================"
echo "Stopping Hyperledger Explorers"
echo "========================================"
echo ""

docker-compose -f docker-compose-explorers.yml down

echo ""
echo "✅ Explorers stopped successfully"
echo "========================================"
