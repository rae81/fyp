# DFIR Split Chaincode Architecture

## Overview

The system implements a **split smart contract** architecture where policy evaluation and decision-making happen in a private component (PRV service), while verification and storage happen on the public blockchain (chaincode).

## System Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                        JumpServer (VM)                        │
│  ┌────────────────────────────────────────────────────────┐  │
│  │              PRV Service (Port 50051)                   │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │  Policy Engine (Casbin-style RBAC)               │  │  │
│  │  │  - 12 predefined rules                           │  │  │
│  │  │  - 4 roles: admin, investigator, auditor, court  │  │  │
│  │  │  - Clearance levels 1-4                          │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │  Cryptographic Engine (ES256)                    │  │  │
│  │  │  - ECDSA P-256 key generation                    │  │  │
│  │  │  - JWS signing (RFC 7515)                        │  │  │
│  │  │  - Private key management                        │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │  Attestation Engine (Simulated)                  │  │  │
│  │  │  - MRENCLAVE generation                          │  │  │
│  │  │  - MRSIGNER generation                           │  │  │
│  │  │  - Attestation report signing                    │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
                           │
                           │ gRPC (JSON/Protobuf)
                           │
                           ▼
┌──────────────────────────────────────────────────────────────┐
│              Hyperledger Fabric Network                       │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Public Chaincode (DFIR Evidence Management)           │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │  Verification Layer                               │  │  │
│  │  │  - ES256 signature verification                   │  │  │
│  │  │  - MRENCLAVE validation                           │  │  │
│  │  │  - Nonce replay protection                        │  │  │
│  │  │  - Timestamp freshness check                      │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │  Storage Layer                                    │  │  │
│  │  │  - Evidence records                               │  │  │
│  │  │  - Custody transfer history                       │  │  │
│  │  │  - PRV configuration                              │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  World State + Blockchain                              │  │
│  │  - Immutable audit trail                               │  │
│  │  - Distributed consensus                               │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

## Data Flow: Evidence Creation

```
1. User Request
   │
   ├─→ [Client] Makes request to create evidence EVD-001
   │
2. Policy Evaluation
   │
   ├─→ [PRV Service] EvaluatePolicy(inv001, "create", "evidence/EVD-001")
   │   │
   │   ├─→ Find user role: investigator (clearance 2)
   │   ├─→ Match policy: "investigator can create evidence/* at clearance 2"
   │   └─→ Return: ALLOW
   │
3. Permit Signing
   │
   ├─→ [PRV Service] GetSignedPermit(context, nonce)
   │   │
   │   ├─→ Create JWS payload:
   │   │   {
   │   │     "sub": "inv001",
   │   │     "action": "create",
   │   │     "resource": "evidence/EVD-001",
   │   │     "decision": "allow",
   │   │     "timestamp": 1699123456,
   │   │     "nonce": "abc123...",
   │   │     "mrenclave": "3f7a21..."
   │   │   }
   │   │
   │   ├─→ Sign with ECDSA P-256 private key
   │   ├─→ Generate attestation report
   │   └─→ Return: {permit, attestation}
   │
4. Blockchain Submission
   │
   ├─→ [Client] Submit to Fabric:
   │   CreateEvidence(id, data, permit, nonce)
   │
5. Chaincode Verification
   │
   ├─→ [Chaincode] VerifyPRVPermit()
   │   │
   │   ├─→ Check subject matches caller
   │   ├─→ Check action = "create"
   │   ├─→ Check resource = "evidence/EVD-001"
   │   ├─→ Check nonce matches
   │   ├─→ Check timestamp (within 5 min)
   │   ├─→ Check decision = "allow"
   │   ├─→ Check MRENCLAVE matches trusted value
   │   ├─→ Verify ECDSA signature with public key
   │   └─→ Return: VALID
   │
6. State Update
   │
   ├─→ [Chaincode] Store evidence in world state
   ├─→ [Chaincode] Emit EvidenceCreated event
   └─→ [Blockchain] Commit to immutable ledger
```

## Security Model

### What PRV Service Hides (Private)

1. **Policy Rules**
   - RBAC rule definitions
   - Role-to-permission mappings
   - Clearance level requirements

2. **Private Key**
   - ECDSA P-256 private signing key
   - Key generation parameters
   - Key storage location

3. **User Assignments**
   - User-to-role mappings
   - Clearance level assignments
   - Internal user database

4. **Policy Evaluation Logic**
   - Pattern matching algorithms
   - Policy evaluation steps
   - Internal decision process

### What Public Chaincode Exposes

1. **Public Key**
   - ECDSA P-256 public key (for verification)
   - Key format: Uncompressed (0x04 + X + Y)

2. **Measurements**
   - MRENCLAVE (enclave code hash)
   - MRSIGNER (signer identity hash)

3. **Signed Decisions**
   - JWS permits with policy decisions
   - Allow/deny outcomes only
   - No internal policy details

4. **Evidence Data**
   - Evidence metadata
   - Custody chain records
   - Timestamps and locations

## Component Interaction

### 1. Initialization Flow

```
[Admin] Initialize PRV Service
   │
   ├─→ Send user role assignments
   │   {
   │     "inv001": {role: "investigator", clearance: 2},
   │     "aud001": {role: "auditor", clearance: 3}
   │   }
   │
   ├─→ PRV generates ECDSA key pair
   ├─→ PRV generates MRENCLAVE/MRSIGNER
   ├─→ PRV loads default policies
   │
   ├─→ [Admin] Extract PRV public key
   ├─→ [Admin] Extract attestation measurements
   │
   └─→ [Admin] Initialize Chaincode
       InitLedger(publicKey, MRENCLAVE, MRSIGNER)
```

### 2. Authorization Flow

```
[User] Request Action
   │
   ├─→ [PRV] Evaluate against policies
   │   - Load user role
   │   - Match policy rules
   │   - Check clearance level
   │   - Return decision
   │
   ├─→ [PRV] Sign decision (if allow)
   │   - Create JWS payload
   │   - Sign with private key
   │   - Generate attestation
   │
   ├─→ [User] Submit to blockchain
   │   - Include signed permit
   │   - Include unique nonce
   │
   ├─→ [Chaincode] Verify permit
   │   - Verify signature
   │   - Validate attestation
   │   - Check nonce
   │   - Check timestamp
   │
   └─→ [Chaincode] Execute if valid
       - Update world state
       - Emit event
       - Return success
```

## Policy Engine (Casbin-style)

### Policy Rules Structure

```go
{
  Role: "investigator",
  ResourcePattern: "evidence/*",
  Action: "create",
  MinClearance: 2
}
```

### Evaluation Algorithm

```
1. Load user profile:
   - user_id → role, clearance

2. For each policy rule:
   a. Match role
   b. Match resource pattern (wildcard support)
   c. Match action
   d. Check clearance >= min_clearance
   
3. If any rule matches:
   - Return ALLOW
   
4. If no rules match:
   - Return DENY
```

### Default Policies (12 rules)

| # | Role          | Resource             | Action          | Min Clearance |
|---|---------------|----------------------|-----------------|---------------|
| 1 | admin         | evidence/*           | *               | 1             |
| 2 | admin         | case/*               | *               | 1             |
| 3 | investigator  | evidence/*           | create          | 2             |
| 4 | investigator  | evidence/*           | transfer        | 2             |
| 5 | investigator  | evidence/*           | read            | 2             |
| 6 | investigator  | case/*               | read            | 2             |
| 7 | investigator  | case/*               | update          | 2             |
| 8 | auditor       | evidence/*           | read            | 3             |
| 9 | auditor       | case/*               | read            | 3             |
|10 | auditor       | audit_log/*          | read            | 3             |
|11 | court         | evidence/*/approved  | read            | 4             |
|12 | court         | case/*/final         | read            | 4             |

## Cryptographic Operations

### JWS Signing (ES256)

```
1. Create header:
   {"alg": "ES256", "typ": "JWT"}
   → Base64URL encode

2. Create payload:
   {
     "sub": "user_id",
     "action": "create",
     "resource": "evidence/001",
     "decision": "allow",
     "timestamp": 1699123456,
     "nonce": "...",
     "mrenclave": "..."
   }
   → Base64URL encode

3. Sign:
   message = header + "." + payload
   hash = SHA256(message)
   signature = ECDSA_Sign(hash, private_key)
   → R||S format (64 bytes)

4. Result:
   {
     "header": "eyJhbGc...",
     "payload": "eyJzdWI...",
     "signature": "3f7a21..."
   }
```

### Signature Verification (Chaincode)

```
1. Decode header and payload (Base64URL)

2. Verify payload content:
   - subject matches caller
   - action matches function
   - resource matches parameter
   - nonce matches
   - timestamp fresh
   - decision = "allow"
   - mrenclave matches config

3. Verify signature:
   message = header + "." + payload
   hash = SHA256(message)
   valid = ECDSA_Verify(hash, signature, public_key)

4. Return valid/invalid
```

## Attestation (Simulated)

### Attestation Report Structure

```go
{
  mrenclave: [32]byte,  // SHA256 of enclave code
  mrsigner:  [32]byte,  // SHA256 of signer identity
  timestamp: uint64,     // Unix timestamp
  nonce:     [32]byte,   // Challenge from verifier
  signature: [64]byte    // Platform signature
}
```

### Real vs. Simulated

| Aspect | Simulated | Real (ARM TrustZone) |
|--------|-----------|----------------------|
| MRENCLAVE | Random bytes | Platform measured |
| MRSIGNER | Random bytes | Signer cert hash |
| Signature | Random bytes | PSA token signature |
| Security | ❌ No isolation | ✅ Hardware isolated |

## State Management

### PRV Service State

```
- In-memory only (simulated)
- Lost on restart
- No persistent storage

Real enclave would use:
- Sealed storage
- Persistent key storage
- Encrypted state
```

### Chaincode State (World State)

```
Key-Value Store:

"PRV_CONFIG" → {publicKey, mrenclave, mrsigner}
"EVD-001"    → {id, caseID, type, custodian, ...}
"TRANSFER_EVD-001_1699123456" → {from, to, timestamp, ...}
```

## Network Communication

### gRPC (PRV Service)

- Protocol: HTTP/2
- Serialization: Protocol Buffers
- Port: 50051
- Security: None (simulated) / mTLS (production)

### Fabric SDK (Chaincode)

- Protocol: gRPC
- Serialization: Protocol Buffers
- Security: mTLS (required)
- Identity: X.509 certificates

## Scalability Considerations

### PRV Service

- Single instance (simulated)
- No state replication
- Potential bottleneck

**Production improvements:**
- Multiple PRV instances
- Load balancing
- State synchronization

### Chaincode

- Runs on all endorsing peers
- Highly available
- Scales with network

## Upgradeability

### PRV Service

- Hot reload: Stop/restart service
- Config changes: Re-initialize
- Policy updates: Rebuild policies

### Chaincode

- Fabric lifecycle management
- Version increments
- Approval + commit process

## Monitoring Points

### PRV Service

1. Policy evaluation count
2. Permit signing rate
3. Error rate
4. Response time

### Chaincode

1. Transaction throughput
2. Verification failures
3. State updates
4. Event emissions

## References

- [Casbin](https://casbin.org/) - RBAC framework
- [JWS RFC 7515](https://tools.ietf.org/html/rfc7515) - JSON Web Signature
- [ECDSA](https://en.wikipedia.org/wiki/Elliptic_Curve_Digital_Signature_Algorithm) - Signature algorithm
- [ARM TrustZone](https://developer.arm.com/ip-products/security-ip/trustzone) - Real enclave platform
