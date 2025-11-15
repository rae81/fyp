# PRV Service (Private Contract - Simulated Enclave)

The PRV (Policy Reasoning and Verification) service is the private component of the split smart contract. It simulates a secure enclave that evaluates policies and signs permits.

## What It Does

- **Policy Evaluation**: Uses Casbin-style RBAC to evaluate access requests
- **Permit Signing**: Signs permits with ES256 (ECDSA P-256) digital signatures  
- **Attestation**: Generates simulated attestation reports (MRENCLAVE/MRSIGNER)
- **Key Management**: Manages private signing key in simulated enclave

## Architecture

```
┌──────────────────────────────────────┐
│     PRV Service (main.go)            │
│  ┌────────────────────────────────┐  │
│  │  Policy Engine (Casbin)        │  │
│  │  - 12 default RBAC rules       │  │
│  │  - 4 roles: admin, inv, aud... │  │
│  └────────────────────────────────┘  │
│  ┌────────────────────────────────┐  │
│  │  Crypto Engine (ES256)         │  │
│  │  - ECDSA P-256 key pair        │  │
│  │  - JWS signing                 │  │
│  └────────────────────────────────┘  │
│  ┌────────────────────────────────┐  │
│  │  Attestation (Simulated)       │  │
│  │  - MRENCLAVE measurement       │  │
│  │  - MRSIGNER measurement        │  │
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘
              │ gRPC :50051
              ▼
       Client Applications
```

## Building

```bash
./scripts/build-prv.sh
```

This will:
1. Generate gRPC code from prv.proto
2. Download Go dependencies
3. Build the prv-service binary

## Running

```bash
# Start the service
./prv-service

# In another terminal, initialize with user roles
./scripts/init-prv.sh
```

## API Methods

### 1. InitPRV
Initialize PRV with user role assignments.

```bash
grpcurl -plaintext -d '{
  "roles": [
    {"user_id": "inv001", "role": "investigator", "clearance": 2}
  ]
}' localhost:50051 dfir.prv.PRV/InitPRV
```

### 2. EvaluatePolicy
Check if a user can perform an action.

```bash
grpcurl -plaintext -d '{
  "subject": "inv001",
  "action": "create",
  "resource": "evidence/EVD-001",
  "clearance": 2
}' localhost:50051 dfir.prv.PRV/EvaluatePolicy
```

### 3. GetSignedPermit
Get a signed permit with attestation.

```bash
NONCE=$(openssl rand -base64 32)

grpcurl -plaintext -d "{
  \"subject\": \"inv001\",
  \"action\": \"create\",
  \"resource\": \"evidence/EVD-001\",
  \"clearance\": 2,
  \"allow\": true,
  \"nonce\": \"$NONCE\"
}" localhost:50051 dfir.prv.PRV/GetSignedPermit
```

### 4. GetAttestation
Generate an attestation report.

```bash
grpcurl -plaintext -d '{
  "challenge": "dGVzdGNoYWxsZW5nZQ=="
}' localhost:50051 dfir.prv.PRV/GetAttestation
```

### 5. GetPublicKey
Get the public key for chaincode initialization.

```bash
grpcurl -plaintext localhost:50051 dfir.prv.PRV/GetPublicKey
```

## Default Policies

The service initializes with 12 default RBAC policies:

| Role          | Resource         | Action          | Min Clearance |
|---------------|------------------|-----------------|---------------|
| admin         | evidence/*       | *               | 1             |
| admin         | case/*           | *               | 1             |
| investigator  | evidence/*       | create          | 2             |
| investigator  | evidence/*       | transfer        | 2             |
| investigator  | evidence/*       | read            | 2             |
| investigator  | case/*           | read/update     | 2             |
| auditor       | evidence/*       | read            | 3             |
| auditor       | case/*           | read            | 3             |
| auditor       | audit_log/*      | read            | 3             |
| court         | evidence/*/approved | read         | 4             |
| court         | case/*/final     | read            | 4             |

## Outputs

When you get a signed permit, you receive:

1. **JWS Permit**: 
   - Header (Base64URL encoded)
   - Payload (Base64URL encoded with policy decision)
   - Signature (ECDSA R||S format, 64 bytes)

2. **Attestation Report**:
   - MRENCLAVE (32 bytes) - simulated enclave code measurement
   - MRSIGNER (32 bytes) - simulated signer measurement
   - Timestamp
   - Nonce
   - Signature (64 bytes) - simulated platform signature

These are sent to the public chaincode for verification.

## Security Model

### What's Hidden (Private):
- Private signing key
- Policy rules and logic
- User role assignments
- Policy evaluation process

### What's Exposed (Public):
- Public key (for signature verification)
- MRENCLAVE/MRSIGNER (for attestation validation)
- Signed permits (decisions only)
- Attestation reports

## Simulation vs. Real Enclave

This is a **simulated** enclave for development/testing:

| Feature | Simulated | Real Enclave |
|---------|-----------|--------------|
| Code Isolation | ❌ No | ✅ Yes (TrustZone/SGX) |
| Memory Encryption | ❌ No | ✅ Yes |
| MRENCLAVE | ✅ Random | ✅ Platform measured |
| Attestation | ✅ Simulated | ✅ Platform signed |
| Key Storage | ❌ In-memory | ✅ Sealed storage |

For production, replace with real ARM TrustZone or Intel SGX implementation.

## Requirements

- Go 1.21+
- protoc (Protocol Buffers compiler)
- grpcurl (for testing)

## Troubleshooting

**Service won't start:**
```bash
# Check if port is in use
lsof -i :50051

# Check logs
journalctl -u dfir-prv -f
```

**gRPC generation fails:**
```bash
# Install protoc plugins
go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
export PATH=$PATH:$HOME/go/bin
```

**Policy denies access:**
```bash
# Check user exists and has correct role
# Check clearance level matches policy requirements
# Review policy rules in main.go initializePolicies()
```
