#!/bin/bash

echo "========================================"
echo "Starting Hyperledger Explorers"
echo "========================================"
echo ""

# Check if blockchains are running
if ! docker ps | grep -q "peer0.lawenforcement.hot.coc.com"; then
    echo "❌ Error: Hot blockchain is not running!"
    echo "   Please run ./restart-blockchain.sh first"
    exit 1
fi

if ! docker ps | grep -q "peer0.archive.cold.coc.com"; then
    echo "❌ Error: Cold blockchain is not running!"
    echo "   Please run ./restart-blockchain.sh first"
    exit 1
fi

echo "✓ Blockchains are running"
echo ""

# Stop any existing explorers
echo "Stopping any existing explorer containers..."
docker-compose -f docker-compose-explorers.yml down 2>/dev/null

# Start explorer databases first
echo "Starting explorer databases..."
docker-compose -f docker-compose-explorers.yml up -d explorerdb-hot explorerdb-cold

echo ""
echo "Waiting for databases to be healthy (30 seconds)..."
sleep 30

# Check database health
echo "Checking database health..."
if docker ps | grep -q "explorerdb-hot.*healthy"; then
    echo "✓ Hot database is healthy"
else
    echo "⚠️  Hot database not healthy yet, waiting 10 more seconds..."
    sleep 10
fi

if docker ps | grep -q "explorerdb-cold.*healthy"; then
    echo "✓ Cold database is healthy"
else
    echo "⚠️  Cold database not healthy yet, waiting 10 more seconds..."
    sleep 10
fi

# Start explorer web interfaces
echo ""
echo "Starting explorer web interfaces..."
docker-compose -f docker-compose-explorers.yml up -d explorer-hot explorer-cold

echo ""
echo "Waiting for explorers to initialize (20 seconds)..."
sleep 20

# Verify explorers are running
echo ""
echo "Checking explorer status..."
if docker ps | grep -q "explorer-hot"; then
    echo "✓ Hot Chain Explorer is running"
else
    echo "❌ Hot Chain Explorer failed to start"
    echo "   Check logs: docker logs explorer-hot"
fi

if docker ps | grep -q "explorer-cold"; then
    echo "✓ Cold Chain Explorer is running"
else
    echo "❌ Cold Chain Explorer failed to start"
    echo "   Check logs: docker logs explorer-cold"
fi

echo ""
echo "========================================"
echo "✅ Explorers Started!"
echo "========================================"
echo ""
echo "Access the explorers at:"
echo ""
echo "  🔥 Hot Chain Explorer:  http://localhost:8090"
echo "  ❄️  Cold Chain Explorer: http://localhost:8091"
echo ""
echo "Login credentials:"
echo "  Username: exploreradmin"
echo "  Password: exploreradminpw"
echo ""
echo "Note: First-time startup may take 1-2 minutes to sync"
echo "      If explorers don't load, check logs with:"
echo "        docker logs explorer-hot"
echo "        docker logs explorer-cold"
echo "========================================"
