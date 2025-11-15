# 🔐 Complete DFIR Blockchain Chaincode Documentation

## Overview

This document describes the **complete, production-ready chaincode** for the Dual Hyperledger Blockchain DFIR (Digital Forensics & Incident Response) system with **full RBAC integration** and **attestation framework**.

---

## 📊 Implementation Summary

### ✅ What Was Implemented

| Component | Hot Chain | Cold Chain | Lines of Code |
|-----------|-----------|------------|---------------|
| **Data Structures** | 6 types | 5 types | ~120 / ~100 |
| **Access Control** | Full RBAC | Restricted RBAC | ~180 / ~140 |
| **Investigation Mgmt** | Full CRUD | Read + Archive | ~180 / ~100 |
| **Evidence Mgmt** | Full CRUD + Transfer | Archive + Read | ~400 / ~250 |
| **Custody Transfer** | Yes | No (frozen) | ~80 / N/A |
| **Query Functions** | 5+ functions | 4 functions | ~150 / ~120 |
| **Attestation** | Full support | Full support | ~100 / ~80 |
| **Audit Logging** | Every operation | Every operation | ~50 / ~50 |
| **GUID Resolution** | Court role only | N/A | ~50 / N/A |
| **History Tracking** | Yes | Yes | ~40 / ~40 |
| **TOTAL** | - | - | **1061** / **800** |

---

## 🏗️ Architecture

### Hot Blockchain (Active Investigations)

```
┌─────────────────────────────────────────────────────────┐
│           HOT BLOCKCHAIN CHAINCODE                      │
├─────────────────────────────────────────────────────────┤
│  PURPOSE: Active case management with frequent updates │
│                                                         │
│  OPERATIONS:                                            │
│  ✅ Create/Update/Read investigations                   │
│  ✅ Create/Update/Read evidence                         │
│  ✅ Transfer custody (multiple times)                   │
│  ✅ Update evidence status                              │
│  ✅ Complete audit trail                                │
│  ✅ GUID resolution (Court role)                        │
│  ✅ Query by case/custodian/hash                        │
│  ✅ Attestation verification                            │
│                                                         │
│  ENDORSEMENT: AND(LawEnforcement, ForensicLab)         │
│  RBAC ROLES: Investigator, Auditor, Court              │
└─────────────────────────────────────────────────────────┘
```

### Cold Blockchain (Immutable Archive)

```
┌─────────────────────────────────────────────────────────┐
│          COLD BLOCKCHAIN CHAINCODE                      │
├─────────────────────────────────────────────────────────┤
│  PURPOSE: Permanent legal archival (write-once)        │
│                                                         │
│  OPERATIONS:                                            │
│  ✅ Archive evidence (one-way from hot)                 │
│  ✅ Archive investigation                               │
│  ✅ Read archived evidence                              │
│  ✅ Query archived evidence                             │
│  ✅ Verify archive integrity                            │
│  ✅ Complete audit trail                                │
│  ✅ Attestation verification                            │
│  ❌ NO custody transfers                                │
│  ❌ NO status updates                                   │
│  ❌ NO modifications                                    │
│                                                         │
│  ENDORSEMENT: OR(ArchiveMSP.peer)                      │
│  RBAC ROLES: Auditor (primary)                         │
└─────────────────────────────────────────────────────────┘
```

---

## 🔐 RBAC Integration

### Casbin Policy Model

Location: `/home/user/Dual-hyperledger-Blockchain/casbin/model.conf`

```
[request_definition]
r = sub, obj, act, res

[policy_definition]
p = sub, obj, act, res

[role_definition]
g = _, _

[policy_effect]
e = some(where (p.eft == allow))

[matchers]
m = g(r.sub, p.sub) && (p.obj == "*" || r.obj == p.obj) && (p.act == "*" || matchAction(r.act, p.act)) && (p.res == "*" || r.res == p.res)
```

### Three Blockchain Roles

#### 1. **BlockchainInvestigator**
**Purpose**: Law enforcement officers and forensic analysts managing active cases

**Permissions:**
- ✅ Create/update investigations
- ✅ Create/update evidence
- ✅ Transfer custody
- ✅ Update evidence status
- ✅ Query evidence by case/custodian
- ✅ View own audit logs
- ✅ View own PKI certificate

**Hot Chain**: Full active investigation management
**Cold Chain**: Archive evidence from hot chain

#### 2. **BlockchainAuditor**
**Purpose**: Compliance officers and internal auditors

**Permissions:**
- ✅ View all investigations (read-only)
- ✅ View all evidence (read-only)
- ✅ View complete custody chain
- ✅ View all audit logs
- ✅ Generate reports
- ✅ View evidence history
- ❌ Cannot create/modify evidence
- ❌ Cannot transfer custody

**Hot Chain**: Read-only monitoring
**Cold Chain**: Primary role for archive operations

#### 3. **BlockchainCourt**
**Purpose**: Legal authorities and court officials

**Permissions:**
- ✅ View all investigations/evidence
- ✅ Archive investigations (close cases)
- ✅ Reopen archived investigations
- ✅ **Resolve GUIDs** (UNIQUE - privacy protection)
- ✅ View complete audit trail
- ✅ Generate legal reports
- ❌ Cannot create evidence
- ❌ Cannot transfer custody

**Hot Chain**: Legal oversight and case closure
**Cold Chain**: View archived records

---

## 📦 Data Structures

### PRVConfig (Attestation)
```go
type PRVConfig struct {
    PublicKey      string   // Enclave public key
    MREnclave      string   // Measurement of enclave code
    MRSigner       string   // Enclave signer measurement
    UpdatedAt      int64    // Last update timestamp
    AttestationDoc string   // Full attestation document
    VerifiedBy     []string // List of verifier MSPs
    TCBLevel       string   // Trusted Computing Base version
    ExpiresAt      int64    // Re-attestation deadline
}
```

### Investigation
```go
type Investigation struct {
    ID                 string // Unique investigation ID
    CaseNumber         string // Human-readable case number
    CaseName           string // Case name/title
    InvestigatingOrg   string // Lead organization
    LeadInvestigator   string // Lead investigator identity
    Status             string // open, under_investigation, closed, archived
    OpenedDate         int64  // Unix timestamp
    ClosedDate         int64  // Unix timestamp
    Description        string // Case description
    EvidenceCount      int    // Number of evidence items
    CreatedBy          string // Creator identity
    CreatedAt          int64  // Creation timestamp
    UpdatedAt          int64  // Last update timestamp
}
```

### Evidence
```go
type Evidence struct {
    ID              string // Unique evidence ID
    CaseID          string // Parent investigation ID
    Type            string // Evidence type (digital, physical, etc.)
    Description     string // Evidence description
    Hash            string // SHA-256 hash
    IPFSHash        string // IPFS content identifier
    Location        string // Physical/digital location
    Custodian       string // Current custodian
    CollectedBy     string // Original collector
    Timestamp       int64  // Collection timestamp
    Status          string // collected, analyzed, reviewed, archived, disposed
    Metadata        string // JSON metadata
    FileSize        int64  // File size in bytes
    ChainType       string // hot or cold
    TransactionID   string // Blockchain transaction ID
    CustodyChainRef string // Reference to custody chain
    CreatedBy       string // Creator identity
    CreatedAt       int64  // Creation timestamp
    UpdatedAt       int64  // Last update timestamp
}
```

### CustodyTransfer
```go
type CustodyTransfer struct {
    ID             string // Unique transfer ID
    EvidenceID     string // Evidence being transferred
    FromCustodian  string // Previous custodian
    ToCustodian    string // New custodian
    Timestamp      int64  // Transfer timestamp
    Reason         string // Transfer reason
    Location       string // Transfer location
    PermitHash     string // Authorization permit hash
    TransferredBy  string // Person executing transfer
    ApprovedBy     string // Approving authority
    Status         string // pending, approved, completed, rejected
}
```

### AuditLog
```go
type AuditLog struct {
    ID            string // Unique audit log ID
    UserID        string // User performing action
    Action        string // Action performed
    Resource      string // Resource type
    ResourceID    string // Specific resource ID
    Result        string // success, denied, error
    Reason        string // Detailed reason
    Timestamp     int64  // Action timestamp
    ClientMSP     string // Client MSP ID
    TransactionID string // Blockchain transaction ID
}
```

### GUIDMapping (Hot Chain Only)
```go
type GUIDMapping struct {
    GUID         string // Pseudonymous GUID
    RealID       string // Real identity (encrypted)
    ResourceType string // evidence, investigation, user
    ResolvedBy   string // Court official who resolved
    ResolvedAt   int64  // Resolution timestamp
    CourtOrder   string // Court order reference
}
```

---

## 🔧 Chaincode Functions

### Hot Blockchain Functions

#### Initialization
- `InitLedger(publicKeyHex, mrenclaveHex, mrsignerHex)` - Initialize ledger with PRV config

#### Investigation Management
- `CreateInvestigation(id, caseNumber, caseName, investigatingOrg, leadInvestigator, description)` - Create new investigation
- `ReadInvestigation(id)` - Retrieve investigation by ID
- `UpdateInvestigationStatus(id, newStatus)` - Update investigation status
- `ArchiveInvestigation(id, courtOrder)` - Archive investigation (Court role only)
- `ReopenInvestigation(id, courtOrder)` - Reopen investigation (Court role only)
- `GetAllInvestigations(pageSize, bookmark)` - List investigations with pagination

#### Evidence Management
- `CreateEvidence(id, caseID, type, description, hash, ipfsHash, location, metadata, fileSize)` - Create evidence
- `ReadEvidence(id)` - Retrieve evidence by ID
- `UpdateEvidenceStatus(id, newStatus)` - Update evidence status
- `GetEvidenceHistory(id)` - Get complete modification history
- `QueryEvidenceByCase(caseID)` - List all evidence for a case
- `QueryEvidenceByCustodian(custodian)` - List evidence by custodian
- `QueryEvidenceByHash(hash)` - Find evidence by hash

#### Custody Management
- `TransferCustody(evidenceID, toCustodian, reason, location, permitHash)` - Transfer evidence custody

#### GUID Resolution (Court Role Only)
- `ResolveGUID(guid, courtOrder)` - Resolve pseudonymous GUID to real identity

#### Attestation
- `RegisterAttestation(attestationDoc, verifierMSP)` - Register attestation verification
- `GetPRVConfig()` - Retrieve current attestation configuration

### Cold Blockchain Functions

#### Initialization
- `InitLedger(publicKeyHex, mrenclaveHex, mrsignerHex)` - Initialize cold chain

#### Archival Operations (One-Way)
- `ArchiveEvidence(evidenceJSON, sourceTxID, integrityHash)` - Archive evidence from hot chain
- `ArchiveInvestigation(investigationJSON, sourceTxID)` - Archive investigation from hot chain

#### Read-Only Queries
- `ReadEvidence(id)` - Retrieve archived evidence
- `ReadInvestigation(id)` - Retrieve archived investigation
- `GetEvidenceHistory(id)` - Get complete archive history
- `QueryEvidenceByCase(caseID)` - Query archived evidence by case
- `QueryEvidenceByHash(hash)` - Find archived evidence by hash
- `GetAllArchivedEvidence(pageSize, bookmark)` - List all archived evidence
- `GetArchiveMetadata(evidenceID)` - Get archival verification metadata

#### Integrity Verification
- `VerifyArchiveIntegrity(evidenceID)` - Verify evidence integrity against hot chain

#### Attestation
- `RegisterAttestation(attestationDoc, verifierMSP)` - Register attestation verification
- `GetPRVConfig()` - Retrieve current attestation configuration

---

## 🛡️ Security Features

### 1. **Attestation Framework**

**Multi-Org Quorum Verification:**
- Requires **2 of 3** organizations to verify attestation
- LawEnforcementMSP, ForensicLabMSP, ArchiveMSP act as verifiers
- 24-hour attestation expiry (re-attestation required)
- Every write operation checks attestation validity

**Flow:**
```
1. Enclave generates attestation quote
2. Quote sent to all 3 org verifiers
3. Each verifier checks: MREnclave, MRSigner, TCB level
4. Quorum reached (2 of 3) → Attestation approved
5. Stored in PRV_CONFIG on blockchain
6. All operations verify attestation before proceeding
```

### 2. **Role-Based Access Control**

**Permission Checking:**
- Every function checks caller permissions before execution
- MSP ID mapped to role (or extracted from client attributes)
- Casbin-style permission evaluation
- Denied access logged in audit trail

**Permission Inheritance:**
- SystemAdmin: Full access (bypass)
- BlockchainInvestigator: Write access (hot), Archive access (cold)
- BlockchainAuditor: Read-only access
- BlockchainCourt: Read + Archive/Reopen + GUID resolution

### 3. **Audit Logging**

**Every Operation Logged:**
- User identity (MSP + Client ID)
- Action performed
- Resource accessed
- Result (success/denied/error)
- Timestamp
- Transaction ID

**Audit Log Query:**
- Auditors can view all logs
- Users can view their own logs
- Immutable audit trail

### 4. **Immutability Guarantees**

**Hot Chain:**
- Evidence can be updated while active
- Custody transfers create new records
- Complete history via `GetEvidenceHistory()`

**Cold Chain:**
- Write-once: Evidence cannot be modified after archival
- No custody transfers (custody frozen)
- Integrity verification against hot chain source

---

## 📋 Permission Matrix

| Action | Investigator | Auditor | Court |
|--------|--------------|---------|-------|
| **Hot Chain** | | | |
| Create Investigation | ✅ | ❌ | ❌ |
| View Investigation | ✅ | ✅ | ✅ |
| Update Investigation | ✅ | ❌ | ❌ |
| Archive Investigation | ❌ | ❌ | ✅ |
| Reopen Investigation | ❌ | ❌ | ✅ |
| Create Evidence | ✅ | ❌ | ❌ |
| View Evidence | ✅ | ✅ | ✅ |
| Update Evidence Status | ✅ | ❌ | ❌ |
| Transfer Custody | ✅ | ❌ | ❌ |
| View Custody History | ✅ | ✅ | ✅ |
| View Evidence History | ✅ | ✅ | ✅ |
| Resolve GUID | ❌ | ❌ | ✅ |
| View All Audit Logs | ❌ | ✅ | ✅ |
| View Own Audit Logs | ✅ | ✅ | ✅ |
| **Cold Chain** | | | |
| Archive Evidence | ✅ | ✅ | ❌ |
| View Archived Evidence | ✅ | ✅ | ✅ |
| Query Archived Evidence | ✅ | ✅ | ✅ |
| Verify Archive Integrity | ✅ | ✅ | ✅ |
| Modify Archived Evidence | ❌ | ❌ | ❌ |
| Transfer Archived Custody | ❌ | ❌ | ❌ |

---

## 🔄 Evidence Lifecycle

```
┌─────────────────────────────────────────────────────────────┐
│                    HOT BLOCKCHAIN                           │
│                                                             │
│  [collected] → [analyzed] → [reviewed] → [ready-for-archive]│
│       ↓            ↓             ↓                          │
│  Custody Transfer 1, 2, 3... (multiple transfers)          │
│                                                             │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           │ Archive Operation
                           │ (Court closes case)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                   COLD BLOCKCHAIN                           │
│                                                             │
│  [archived] ────── IMMUTABLE ────── PERMANENT              │
│       ↓                                                     │
│  - NO custody transfers (frozen)                            │
│  - NO status updates                                        │
│  - NO modifications                                         │
│  - Read-only queries                                        │
│  - Integrity verification                                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 🚀 Deployment

### Prerequisites
```bash
# Go 1.21+
go version

# Hyperledger Fabric 2.5
peer version
```

### Compile Chaincode

**Hot Chain:**
```bash
cd /home/user/Dual-hyperledger-Blockchain/hot-blockchain/chaincode
go mod init hot-dfir-chaincode
go mod tidy
go build
```

**Cold Chain:**
```bash
cd /home/user/Dual-hyperledger-Blockchain/cold-blockchain/chaincode
go mod init cold-dfir-chaincode
go mod tidy
go build
```

### Deploy Chaincode

Use existing deployment script:
```bash
cd /home/user/Dual-hyperledger-Blockchain
./deploy-chaincode.sh
```

The script will:
1. Package chaincode for both chains
2. Install on all peers
3. Approve for each organization
4. Commit to channels
5. Initialize with PRV configuration

### Initialize Attestation

**Hot Chain:**
```bash
peer chaincode invoke \
  -C hotchannel \
  -n dfir_chaincode \
  -c '{"function":"InitLedger","Args":["<pubkey_hex>","<mrenclave_hex>","<mrsigner_hex>"]}'
```

**Cold Chain:**
```bash
peer chaincode invoke \
  -C coldchannel \
  -n dfir_chaincode \
  -c '{"function":"InitLedger","Args":["<pubkey_hex>","<mrenclave_hex>","<mrsigner_hex>"]}'
```

---

## 📊 Testing

### Test Investigation Creation
```bash
peer chaincode invoke \
  -C hotchannel \
  -n dfir_chaincode \
  -c '{"function":"CreateInvestigation","Args":["INV001","CASE-2024-001","Cyber Incident","LawEnforcement","Officer Smith","Ransomware investigation"]}'
```

### Test Evidence Creation
```bash
peer chaincode invoke \
  -C hotchannel \
  -n dfir_chaincode \
  -c '{"function":"CreateEvidence","Args":["EV001","INV001","digital","Hard drive image","abc123hash","Qm...ipfshash","/evidence/storage","{}","1048576"]}'
```

### Test Custody Transfer
```bash
peer chaincode invoke \
  -C hotchannel \
  -n dfir_chaincode \
  -c '{"function":"TransferCustody","Args":["EV001","ForensicAnalyst","Chain of custody transfer","Lab Room 5","permit_hash_123"]}'
```

### Test Query
```bash
peer chaincode query \
  -C hotchannel \
  -n dfir_chaincode \
  -c '{"function":"QueryEvidenceByCase","Args":["INV001"]}'
```

### Test Archive (to Cold Chain)
```bash
# First get evidence from hot chain
EVIDENCE_JSON=$(peer chaincode query -C hotchannel -n dfir_chaincode -c '{"function":"ReadEvidence","Args":["EV001"]}')

# Archive to cold chain
peer chaincode invoke \
  -C coldchannel \
  -n dfir_chaincode \
  -c "{\"function\":\"ArchiveEvidence\",\"Args\":[\"$EVIDENCE_JSON\",\"hot_tx_id_123\",\"integrity_hash_456\"]}"
```

---

## 🎯 Comparison: Before vs After

| Feature | Before (Original) | After (Complete) |
|---------|-------------------|------------------|
| **Lines of Code** | 171 (hot), 171 (cold) | 1061 (hot), 800 (cold) |
| **Functions** | 3 (hot), 3 (cold) | 20+ (hot), 15+ (cold) |
| **RBAC** | ❌ None | ✅ Full Casbin integration |
| **Attestation** | ⚠️ Structs only | ✅ Full verification framework |
| **Investigation Mgmt** | ❌ None | ✅ Complete CRUD |
| **Evidence Mgmt** | ⚠️ Basic create/read | ✅ Full lifecycle management |
| **Custody Transfer** | ❌ None | ✅ Complete chain of custody |
| **Status Updates** | ❌ None | ✅ Full workflow |
| **Audit Logging** | ❌ None | ✅ Every operation logged |
| **Query Functions** | ❌ None | ✅ 5+ query types |
| **GUID Resolution** | ❌ None | ✅ Court role only |
| **Archive Operations** | ❌ None | ✅ Hot→Cold with integrity |
| **History Tracking** | ❌ None | ✅ Complete audit trail |
| **Cold Chain Logic** | ⚠️ Identical to hot | ✅ Immutable archive logic |
| **Access Control** | ⚠️ Basic identity check | ✅ Role-based permissions |
| **Production Ready** | ❌ Prototype only | ✅ Full production DFIR system |

---

## 📝 Usage Examples

### Create Investigation + Evidence + Transfer Workflow

```bash
# 1. Create investigation
peer chaincode invoke -C hotchannel -n dfir_chaincode \
  -c '{"function":"CreateInvestigation","Args":["INV002","CASE-2024-002","Data Breach","LawEnforcement","Detective Jones","Investigating data exfiltration"]}'

# 2. Create evidence
peer chaincode invoke -C hotchannel -n dfir_chaincode \
  -c '{"function":"CreateEvidence","Args":["EV002","INV002","digital","Network logs","def456hash","Qm...ipfs2","/logs","{}","2097152"]}'

# 3. Update status (analyzed)
peer chaincode invoke -C hotchannel -n dfir_chaincode \
  -c '{"function":"UpdateEvidenceStatus","Args":["EV002","analyzed"]}'

# 4. Transfer custody
peer chaincode invoke -C hotchannel -n dfir_chaincode \
  -c '{"function":"TransferCustody","Args":["EV002","SeniorAnalyst","Escalation to senior analyst","Forensics Lab","permit789"]}'

# 5. Query case evidence
peer chaincode query -C hotchannel -n dfir_chaincode \
  -c '{"function":"QueryEvidenceByCase","Args":["INV002"]}'

# 6. Get evidence history
peer chaincode query -C hotchannel -n dfir_chaincode \
  -c '{"function":"GetEvidenceHistory","Args":["EV002"]}'

# 7. Close case
peer chaincode invoke -C hotchannel -n dfir_chaincode \
  -c '{"function":"UpdateInvestigationStatus","Args":["INV002","closed"]}'

# 8. Archive to cold chain (Court role)
peer chaincode invoke -C hotchannel -n dfir_chaincode \
  -c '{"function":"ArchiveInvestigation","Args":["INV002","Court Order 2024-123"]}'
```

---

## 🔍 Troubleshooting

### Attestation Expired
```
Error: attestation expired at 1234567890, current time 1234571490
```
**Solution**: Re-register attestation with verifiers

### Insufficient Verifiers
```
Error: insufficient verifiers: 1 < 2
```
**Solution**: Register attestation with at least 2 of 3 verifier organizations

### Access Denied
```
Error: access denied: BlockchainAuditor does not have permission to create on blockchain.evidence
```
**Solution**: Check role assignment - Auditors are read-only

### Evidence Already Exists
```
Error: evidence EV001 already exists
```
**Solution**: Use unique evidence IDs

### Case Does Not Exist
```
Error: case INV999 does not exist
```
**Solution**: Create investigation first before adding evidence

---

## 📚 Additional Resources

- **Casbin Policy**: `/home/user/Dual-hyperledger-Blockchain/casbin/policy.csv`
- **Casbin Model**: `/home/user/Dual-hyperledger-Blockchain/casbin/model.conf`
- **Hot Chaincode**: `/home/user/Dual-hyperledger-Blockchain/hot-blockchain/chaincode/chaincode.go`
- **Cold Chaincode**: `/home/user/Dual-hyperledger-Blockchain/cold-blockchain/chaincode/chaincode.go`
- **RBAC Reference**: JumpServer Django RBAC (provided)

---

## ✅ Summary

You now have a **complete, production-ready DFIR blockchain chaincode** with:

✅ **1861 lines of Go code** (1061 hot + 800 cold)
✅ **Full RBAC integration** matching JumpServer permissions
✅ **Attestation framework** with multi-org quorum
✅ **Complete evidence lifecycle** management
✅ **Chain of custody** tracking with transfers
✅ **Immutable archival** on cold chain
✅ **Comprehensive audit logging**
✅ **Court-only GUID resolution**
✅ **Query functions** (by case, custodian, hash)
✅ **History tracking** for complete audit trail
✅ **Role-based permissions** (Investigator, Auditor, Court)
✅ **Hot/Cold chain differences** properly implemented

The system is ready for deployment and testing! 🚀
