#!/bin/bash

echo "=== Orderer Diagnostic Script ==="
echo ""

echo "1. Checking all running containers:"
docker ps --format "table {{.Names}}\t{{.Status}}"
echo ""

echo "2. Checking specifically for orderers:"
docker ps | grep orderer
echo ""

echo "3. Checking if orderer.hot.coc.com is in docker ps output:"
if docker ps | grep -q "orderer.hot.coc.com"; then
    echo "✅ orderer.hot.coc.com FOUND in docker ps"
else
    echo "❌ orderer.hot.coc.com NOT FOUND in docker ps"
fi
echo ""

echo "4. Checking if orderer.cold.coc.com is in docker ps output:"
if docker ps | grep -q "orderer.cold.coc.com"; then
    echo "✅ orderer.cold.coc.com FOUND in docker ps"
else
    echo "❌ orderer.cold.coc.com NOT FOUND in docker ps"
fi
echo ""

echo "5. Checking orderer container logs (hot):"
docker logs orderer.hot.coc.com 2>&1 | tail -20
echo ""

echo "6. Checking orderer container logs (cold):"
docker logs orderer.cold.coc.com 2>&1 | tail -20
echo ""

echo "7. Checking if CLI containers are accessible:"
docker exec cli echo "✅ CLI container is accessible" || echo "❌ CLI container not accessible"
docker exec cli-cold echo "✅ CLI-COLD container is accessible" || echo "❌ CLI-COLD container not accessible"
echo ""

echo "=== Diagnostic Complete ==="
