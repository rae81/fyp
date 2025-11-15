#!/bin/bash

echo "=========================================="
echo "  Explorer Diagnostic Script"
echo "=========================================="
echo ""

echo "1. Checking if explorer containers exist..."
echo ""
docker ps -a | grep explorer

echo ""
echo "2. Checking explorer-hot logs..."
echo ""
docker logs explorer-hot 2>&1 | tail -30

echo ""
echo "3. Checking explorer-cold logs..."
echo ""
docker logs explorer-cold 2>&1 | tail -30

echo ""
echo "4. Checking if explorer images are pulled..."
echo ""
docker images | grep explorer

echo ""
echo "5. Checking network connectivity..."
echo ""
docker network ls | grep chain

echo ""
echo "=========================================="
echo "  Diagnostic complete"
echo "=========================================="
