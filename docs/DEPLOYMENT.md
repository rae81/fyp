# DFIR Split Chaincode - Deployment Guide

Complete guide for deploying both PRV service and public chaincode.

## Prerequisites

### JumpServer (PRV Service)
- Ubuntu 20.04+ or any Linux distribution
- Go 1.21+
- Protocol Buffers compiler (protoc)
- Network connectivity to Fabric network

### Fabric Network (Chaincode)
- Hyperledger Fabric 2.2+
- peer CLI tool configured
- Channel created and operational
- Go 1.21+

## Part 1: Deploy PRV Service (JumpServer)

### Step 1: Install Dependencies

```bash
# Install Go 1.21
wget https://go.dev/dl/go1.21.5.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin

# Install protoc
sudo apt-get update
sudo apt-get install -y protobuf-compiler

# Install Go protoc plugins
go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
export PATH=$PATH:$HOME/go/bin
```

### Step 2: Clone Repository

```bash
git clone https://github.com/rae81/Smart-contract.git
cd Smart-contract
```

### Step 3: Build PRV Service

```bash
cd prv-service
./scripts/build-prv.sh
```

Expected output:
```
======================================
Building PRV Service
======================================
✓ protoc found
✓ gRPC code generated
✓ PRV service built successfully
Binary: .../prv-service
```

### Step 4: Run PRV Service

```bash
# Run in foreground (for testing)
./prv-service
```

Or create systemd service (production):

```bash
sudo cp prv-service /usr/local/bin/

sudo tee /etc/systemd/system/dfir-prv.service > /dev/null <<SYSTEMD
[Unit]
Description=DFIR PRV Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/prv-service
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SYSTEMD

sudo systemctl daemon-reload
sudo systemctl enable dfir-prv
sudo systemctl start dfir-prv
sudo systemctl status dfir-prv
```

### Step 5: Initialize PRV

```bash
./scripts/init-prv.sh
```

This initializes PRV with default users:
- admin001 (admin, clearance 1)
- inv001-003 (investigator, clearance 2)
- aud001-002 (auditor, clearance 3)
- court001 (court, clearance 4)

### Step 6: Extract PRV Configuration

```bash
# Install grpcurl if not already installed
go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest
export PATH=$PATH:$HOME/go/bin

# Get public key
grpcurl -plaintext localhost:50051 \
    dfir.prv.PRV/GetPublicKey > prv_pubkey.json

# Get attestation report
grpcurl -plaintext -d '{"challenge":"dGVzdA=="}' \
    localhost:50051 \
    dfir.prv.PRV/GetAttestation > attestation.json

# Extract values for chaincode initialization
PUBKEY=$(jq -r '.publicKey' prv_pubkey.json | base64 -d | xxd -p | tr -d '\n')
MRENCLAVE=$(jq -r '.attestation.mrenclave' attestation.json | base64 -d | xxd -p | tr -d '\n')
MRSIGNER=$(jq -r '.attestation.mrsigner' attestation.json | base64 -d | xxd -p | tr -d '\n')

# Save for later use
echo "PUBKEY=$PUBKEY" > prv-config.env
echo "MRENCLAVE=$MRENCLAVE" >> prv-config.env
echo "MRSIGNER=$MRSIGNER" >> prv-config.env

echo "PRV configuration saved to prv-config.env"
```

## Part 2: Deploy Public Chaincode (Fabric Network)

### Step 1: Vendor Dependencies

```bash
cd ../chaincode
./scripts/vendor-chaincode.sh
```

This downloads and vendors all Fabric dependencies offline.

### Step 2: Package Chaincode

```bash
./scripts/package-chaincode.sh
```

This creates `dfir.tar.gz` containing:
- chaincode.go
- go.mod
- vendor/ (all dependencies)

### Step 3: Install on Peers

```bash
# Install on each peer in your network
peer lifecycle chaincode install dfir.tar.gz

# Query installed chaincodes
peer lifecycle chaincode queryinstalled

# Save package ID
export PACKAGE_ID=$(peer lifecycle chaincode queryinstalled | grep dfir_1.0 | awk '{print $3}' | sed 's/,$//')
echo "Package ID: $PACKAGE_ID"
```

### Step 4: Approve Chaincode

```bash
# Approve for your organization
peer lifecycle chaincode approveformyorg \
    -o orderer.example.com:7050 \
    --tls --cafile $ORDERER_CA \
    --channelID mychannel \
    --name dfir \
    --version 1.0 \
    --package-id $PACKAGE_ID \
    --sequence 1

# Check commit readiness
peer lifecycle chaincode checkcommitreadiness \
    --channelID mychannel \
    --name dfir \
    --version 1.0 \
    --sequence 1
```

### Step 5: Commit Chaincode

```bash
# After all required orgs have approved
peer lifecycle chaincode commit \
    -o orderer.example.com:7050 \
    --tls --cafile $ORDERER_CA \
    --channelID mychannel \
    --name dfir \
    --version 1.0 \
    --sequence 1 \
    --peerAddresses peer0.org1.example.com:7051 \
    --tlsRootCertFiles /path/to/org1/tls/ca.crt \
    --peerAddresses peer0.org2.example.com:7051 \
    --tlsRootCertFiles /path/to/org2/tls/ca.crt

# Verify committed
peer lifecycle chaincode querycommitted \
    --channelID mychannel \
    --name dfir
```

### Step 6: Initialize Chaincode

```bash
# Load PRV configuration
source ../prv-service/prv-config.env

# Initialize ledger with PRV config
peer chaincode invoke \
    -o orderer.example.com:7050 \
    --tls --cafile $ORDERER_CA \
    -C mychannel \
    -n dfir \
    -c "{\"function\":\"InitLedger\",\"Args\":[
        \"$PUBKEY\",
        \"$MRENCLAVE\",
        \"$MRSIGNER\"
    ]}"
```

## Part 3: Test End-to-End

### Test 1: Policy Evaluation

```bash
grpcurl -plaintext -d '{
  "subject": "inv001",
  "action": "create",
  "resource": "evidence/EVD-TEST-001",
  "clearance": 2
}' localhost:50051 dfir.prv.PRV/EvaluatePolicy
```

Expected: `{"allow": true, "reason": "Access allowed by policy"}`

### Test 2: Get Signed Permit

```bash
NONCE=$(openssl rand -base64 32)

grpcurl -plaintext -d "{
  \"subject\": \"inv001\",
  \"action\": \"create\",
  \"resource\": \"evidence/EVD-TEST-001\",
  \"clearance\": 2,
  \"allow\": true,
  \"nonce\": \"$NONCE\"
}" localhost:50051 dfir.prv.PRV/GetSignedPermit > permit.json

echo "Permit saved to permit.json"
```

### Test 3: Create Evidence on Blockchain

```bash
PERMIT=$(cat permit.json | jq -c '.permit')

peer chaincode invoke \
    -o orderer.example.com:7050 \
    --tls --cafile $ORDERER_CA \
    -C mychannel \
    -n dfir \
    -c "{\"function\":\"CreateEvidence\",\"Args\":[
        \"EVD-TEST-001\",
        \"CASE-TEST-001\",
        \"digital\",
        \"Test laptop hard drive\",
        \"sha256:test123hash\",
        \"Evidence Lab A\",
        \"{\\\"collected_by\\\": \\\"Officer Smith\\\"}\",
        \"$PERMIT\",
        \"$NONCE\"
    ]}"
```

Expected: `status:200` - Evidence created successfully

### Test 4: Transfer Custody

```bash
# Get new nonce and permit
NONCE=$(openssl rand -base64 32)

grpcurl -plaintext -d "{
  \"subject\": \"inv001\",
  \"action\": \"transfer\",
  \"resource\": \"evidence/EVD-TEST-001\",
  \"clearance\": 2,
  \"allow\": true,
  \"nonce\": \"$NONCE\"
}" localhost:50051 dfir.prv.PRV/GetSignedPermit > permit_transfer.json

PERMIT=$(cat permit_transfer.json | jq -c '.permit')

# Transfer custody
peer chaincode invoke \
    -o orderer.example.com:7050 \
    --tls --cafile $ORDERER_CA \
    -C mychannel \
    -n dfir \
    -c "{\"function\":\"TransferCustody\",\"Args\":[
        \"EVD-TEST-001\",
        \"inv002\",
        \"Transfer for forensic analysis\",
        \"Analysis Lab B\",
        \"$PERMIT\",
        \"$NONCE\"
    ]}"
```

### Test 5: Query Custody History

```bash
peer chaincode query \
    -C mychannel \
    -n dfir \
    -c '{"function":"GetCustodyHistory","Args":["EVD-TEST-001"]}'
```

Expected: JSON array of custody transfers

## Troubleshooting

### PRV Service Issues

**Service won't start:**
```bash
# Check if port 50051 is in use
lsof -i :50051

# Check service logs
journalctl -u dfir-prv -f

# Kill conflicting process
kill -9 $(lsof -t -i:50051)
```

**gRPC generation fails:**
```bash
# Ensure protoc plugins are installed
go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
export PATH=$PATH:$HOME/go/bin

# Verify installation
which protoc-gen-go
which protoc-gen-go-grpc
```

### Chaincode Issues

**Vendoring fails:**
```bash
# Clear Go cache
go clean -modcache

# Remove vendor directory
rm -rf vendor/

# Try again
./scripts/vendor-chaincode.sh
```

**Signature verification fails:**
```bash
# Verify public key matches
peer chaincode query -C mychannel -n dfir \
    -c '{"function":"GetPRVConfig"}' | jq .public_key

# Compare with PRV key
grpcurl -plaintext localhost:50051 dfir.prv.PRV/GetPublicKey

# If mismatch, update chaincode config
peer chaincode invoke -C mychannel -n dfir \
    -c '{"function":"UpdatePRVConfig","Args":["<new_pubkey>","..."]}'
```

**Policy denies access:**
```bash
# Check user exists in role assignments
# Review PRV logs for policy evaluation details
journalctl -u dfir-prv -f | grep "Policy"

# Test policy directly
grpcurl -plaintext -d '{...}' localhost:50051 dfir.prv.PRV/EvaluatePolicy
```

## Monitoring

### PRV Service

```bash
# Watch service status
watch -n 2 'systemctl status dfir-prv | tail -20'

# Monitor gRPC calls
journalctl -u dfir-prv -f | grep -E "Policy|Permit|Attestation"

# Check active connections
lsof -i :50051
```

### Chaincode

```bash
# Monitor peer logs
docker logs -f peer0.org1.example.com

# Query chaincode state
peer chaincode query -C mychannel -n dfir \
    -c '{"function":"GetState","Args":["PRV_CONFIG"]}'

# Watch events
peer chaincode invoke -C mychannel -n dfir --waitForEvent
```

## Success Criteria

✅ PRV service running and responding  
✅ Policy evaluations working correctly  
✅ Signed permits generated with attestation  
✅ Chaincode installed and committed  
✅ Chaincode verifies signatures successfully  
✅ Evidence created on blockchain  
✅ Custody transfers recorded  
✅ Custody history queryable  

## Next Steps

1. Configure production TLS certificates
2. Set up log aggregation and monitoring
3. Configure backup and recovery procedures
4. Train users on workflows
5. Perform security audit
6. Plan key rotation schedule

## Support

- Documentation: [docs/](.)
- Issues: [GitHub Issues](https://github.com/rae81/Smart-contract/issues)
