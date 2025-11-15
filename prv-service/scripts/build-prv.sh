#!/bin/bash
set -e

echo "======================================"
echo "Building PRV Service"
echo "======================================"

cd "$(dirname "$0")/.."

echo ""
echo "Step 1: Generate gRPC code..."
protoc --go_out=. --go_opt=paths=source_relative \
       --go-grpc_out=. --go-grpc_opt=paths=source_relative \
       prv.proto

echo "Step 2: Download dependencies..."
go mod download
go mod tidy

echo "Step 3: Build..."
go build -o prv-service main.go prv.pb.go prv_grpc.pb.go

echo ""
echo "✓ Build complete!"
echo "  Binary: $(pwd)/prv-service"
