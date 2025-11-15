#!/bin/bash

echo "=== CA Servers Diagnostic ==="
echo ""

echo "1. Checking running containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(ca-|enclave)" || echo "No CA containers running!"
echo ""

echo "2. Checking CA container logs:"
echo ""

for CA in ca-lawenforcement ca-forensiclab ca-auditor ca-court ca-orderer-hot ca-orderer-cold; do
    echo "=== $CA Logs (last 20 lines) ==="
    docker logs $CA 2>&1 | tail -20
    echo ""
done

echo "3. Testing CA connectivity:"
echo ""

for PORT in 7054 8054 9054 10054 11054 12054; do
    echo -n "Port $PORT: "
    if curl -sk https://localhost:$PORT/cainfo 2>/dev/null | jq -r '.result.CAName' 2>/dev/null; then
        echo " ✓"
    else
        echo " ✗ NOT RESPONDING"
    fi
done

echo ""
echo "4. Checking if ports are listening:"
netstat -tuln | grep -E "(7054|8054|9054|10054|11054|12054)" || echo "No CA ports listening"

echo ""
echo "=== Diagnostic Complete ==="
