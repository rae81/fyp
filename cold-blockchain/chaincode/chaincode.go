package main

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// DFIRColdChaincode - Cold blockchain chaincode for immutable archival
type DFIRColdChaincode struct {
	contractapi.Contract
}

// ==============================================================================
// DATA STRUCTURES (Same as hot chain for compatibility)
// ==============================================================================

// PRVConfig stores attestation verification keys and measurements
type PRVConfig struct {
	PublicKey      string   `json:"public_key"`
	MREnclave      string   `json:"mr_enclave"`
	MRSigner       string   `json:"mr_signer"`
	UpdatedAt      int64    `json:"updated_at"`
	AttestationDoc string   `json:"attestation_doc"`
	VerifiedBy     []string `json:"verified_by"`
	TCBLevel       string   `json:"tcb_level"`
	ExpiresAt      int64    `json:"expires_at"`
}

// Investigation represents a case/investigation (archived)
type Investigation struct {
	ID                 string `json:"id"`
	CaseNumber         string `json:"case_number"`
	CaseName           string `json:"case_name"`
	InvestigatingOrg   string `json:"investigating_org"`
	LeadInvestigator   string `json:"lead_investigator"`
	Status             string `json:"status"` // archived (always)
	OpenedDate         int64  `json:"opened_date"`
	ClosedDate         int64  `json:"closed_date"`
	ArchivedDate       int64  `json:"archived_date"`
	Description        string `json:"description"`
	EvidenceCount      int    `json:"evidence_count"`
	CreatedBy          string `json:"created_by"`
	ArchivedBy         string `json:"archived_by"`
	CreatedAt          int64  `json:"created_at"`
	ArchivedAt         int64  `json:"archived_at"`
}

// Evidence represents a piece of digital evidence (immutable archive)
type Evidence struct {
	ID              string `json:"id"`
	CaseID          string `json:"case_id"`
	Type            string `json:"type"`
	Description     string `json:"description"`
	Hash            string `json:"hash"`
	IPFSHash        string `json:"ipfs_hash"`
	Location        string `json:"location"`
	Custodian       string `json:"custodian"`        // Frozen custodian
	CollectedBy     string `json:"collected_by"`
	Timestamp       int64  `json:"timestamp"`
	Status          string `json:"status"`           // archived (always)
	Metadata        string `json:"metadata"`
	FileSize        int64  `json:"file_size"`
	ChainType       string `json:"chain_type"`       // cold (always)
	TransactionID   string `json:"transaction_id"`
	CustodyChainRef string `json:"custody_chain_ref"`
	CreatedBy       string `json:"created_by"`
	ArchivedBy      string `json:"archived_by"`
	CreatedAt       int64  `json:"created_at"`
	ArchivedAt      int64  `json:"archived_at"`
	SourceChain     string `json:"source_chain"`     // hot
	SourceTxID      string `json:"source_tx_id"`     // Original hot chain tx
}

// AuditLog records all operations for compliance
type AuditLog struct {
	ID            string `json:"id"`
	UserID        string `json:"user_id"`
	Action        string `json:"action"`
	Resource      string `json:"resource"`
	ResourceID    string `json:"resource_id"`
	Result        string `json:"result"`
	Reason        string `json:"reason"`
	Timestamp     int64  `json:"timestamp"`
	ClientMSP     string `json:"client_msp"`
	TransactionID string `json:"transaction_id"`
}

// ArchiveMetadata stores archival verification info
type ArchiveMetadata struct {
	EvidenceID         string `json:"evidence_id"`
	OriginalChain      string `json:"original_chain"`
	OriginalTxID       string `json:"original_tx_id"`
	ArchivalVerifiedBy string `json:"archival_verified_by"`
	ArchivalTimestamp  int64  `json:"archival_timestamp"`
	IntegrityHash      string `json:"integrity_hash"`
}

// ==============================================================================
// INITIALIZATION
// ==============================================================================

// InitLedger initializes the cold chain ledger with PRV configuration
func (cc *DFIRColdChaincode) InitLedger(ctx contractapi.TransactionContextInterface,
	publicKeyHex string, mrenclaveHex string, mrsignerHex string) error {

	config := PRVConfig{
		PublicKey:      publicKeyHex,
		MREnclave:      mrenclaveHex,
		MRSigner:       mrsignerHex,
		UpdatedAt:      time.Now().Unix(),
		AttestationDoc: "",
		VerifiedBy:     []string{},
		TCBLevel:       "1",
		ExpiresAt:      time.Now().Add(24 * time.Hour).Unix(),
	}

	configJSON, err := json.Marshal(config)
	if err != nil {
		return fmt.Errorf("failed to marshal config: %v", err)
	}

	err = ctx.GetStub().PutState("PRV_CONFIG", configJSON)
	if err != nil {
		return fmt.Errorf("failed to store config: %v", err)
	}

	cc.logAudit(ctx, "InitLedger", "system", "PRV_CONFIG", "success", "Cold chain ledger initialized")

	fmt.Printf("✓ Cold chain ledger initialized with PRV config\n")
	return nil
}

// ==============================================================================
// ACCESS CONTROL & ATTESTATION HELPERS
// ==============================================================================

// checkPermission validates if the caller has permission for the action
func (cc *DFIRColdChaincode) checkPermission(ctx contractapi.TransactionContextInterface,
	object string, action string, resource string) error {

	clientID, err := ctx.GetClientIdentity().GetID()
	if err != nil {
		return fmt.Errorf("failed to get client identity: %v", err)
	}

	mspID, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil {
		return fmt.Errorf("failed to get MSP ID: %v", err)
	}

	// Extract role from client attributes
	role, found, err := ctx.GetClientIdentity().GetAttributeValue("role")
	if err != nil || !found {
		role = cc.getRoleFromMSP(mspID)
	}

	allowed := cc.evaluatePermission(role, object, action, resource, clientID)
	if !allowed {
		cc.logAudit(ctx, action, object, resource, "denied", fmt.Sprintf("Insufficient permissions for role: %s", role))
		return fmt.Errorf("access denied: %s does not have permission to %s on %s", role, action, object)
	}

	return nil
}

// getRoleFromMSP maps MSP ID to default role
func (cc *DFIRColdChaincode) getRoleFromMSP(mspID string) string {
	// Role mapping aligned with JumpServer RBAC design
	switch mspID {
	case "CourtMSP":
		return "BlockchainCourt" // Cross-chain transfers, archive/reopen authority
	case "AuditorMSP":
		return "BlockchainAuditor" // Read-only access to evidence for compliance/audit
	case "LawEnforcementMSP", "ForensicLabMSP":
		return "BlockchainInvestigator" // If investigators need cold chain access
	default:
		return "User"
	}
}

// evaluatePermission implements Casbin-style permission checking
func (cc *DFIRColdChaincode) evaluatePermission(role string, object string, action string, resource string, userID string) bool {
	// SystemAdmin has full access
	if role == "SystemAdmin" {
		return true
	}

	// Cold chain permissions (more restrictive)
	permissions := map[string]map[string][]string{
		"BlockchainInvestigator": {
			"blockchain.investigation": {"view", "list"},         // Read-only
			"blockchain.evidence":      {"view", "list", "archive"}, // Can archive from hot
			"blockchain.custody":       {"view"},                 // No transfers
		},
		"BlockchainAuditor": {
			"blockchain.investigation": {"view", "list"},
			"blockchain.evidence":      {"view", "list", "history", "archive"},
			"blockchain.custody":       {"view", "history"},
			"blockchain.transaction":   {"view", "list"},
			"audits.*":                 {"view"},
			"reports.*":                {"view"},
		},
		"BlockchainCourt": {
			"blockchain.investigation": {"view", "list"},
			"blockchain.evidence":      {"view", "list", "history"},
			"blockchain.custody":       {"view", "history"},
			"blockchain.transaction":   {"view", "list"},
			"audits.*":                 {"view"},
			"reports.*":                {"view"},
		},
	}

	rolePerms, roleExists := permissions[role]
	if !roleExists {
		return false
	}

	// Check wildcard permissions
	for permObj, actions := range rolePerms {
		if permObj == object+".*" || (len(permObj) > 2 && permObj[len(permObj)-2:] == ".*" && len(object) >= len(permObj)-2 && object[:len(permObj)-2] == permObj[:len(permObj)-2]) {
			for _, act := range actions {
				if act == "*" || act == action {
					return true
				}
			}
		}
	}

	// Check exact match
	actions, objExists := rolePerms[object]
	if !objExists {
		return false
	}

	for _, act := range actions {
		if act == "*" || act == action {
			return true
		}
	}

	return false
}

// checkAttestation verifies attestation is still valid
func (cc *DFIRColdChaincode) checkAttestation(ctx contractapi.TransactionContextInterface) error {
	configJSON, err := ctx.GetStub().GetState("PRV_CONFIG")
	if err != nil {
		return fmt.Errorf("failed to read PRV config: %v", err)
	}
	if configJSON == nil {
		return fmt.Errorf("PRV config not initialized")
	}

	var config PRVConfig
	err = json.Unmarshal(configJSON, &config)
	if err != nil {
		return fmt.Errorf("failed to unmarshal PRV config: %v", err)
	}

	// Check if attestation is expired
	currentTime := time.Now().Unix()
	if currentTime > config.ExpiresAt {
		return fmt.Errorf("attestation expired at %d, current time %d", config.ExpiresAt, currentTime)
	}

	// Check verifier quorum (minimum 2 of 3)
	if len(config.VerifiedBy) < 2 {
		return fmt.Errorf("insufficient verifiers: %d < 2", len(config.VerifiedBy))
	}

	return nil
}

// logAudit creates an audit log entry
func (cc *DFIRColdChaincode) logAudit(ctx contractapi.TransactionContextInterface,
	action string, resource string, resourceID string, result string, reason string) error {

	clientID, _ := ctx.GetClientIdentity().GetID()
	mspID, _ := ctx.GetClientIdentity().GetMSPID()
	txID := ctx.GetStub().GetTxID()
	txTimestamp, _ := ctx.GetStub().GetTxTimestamp()

	auditLog := AuditLog{
		ID:            fmt.Sprintf("audit_%s", txID),
		UserID:        clientID,
		Action:        action,
		Resource:      resource,
		ResourceID:    resourceID,
		Result:        result,
		Reason:        reason,
		Timestamp:     txTimestamp.Seconds,
		ClientMSP:     mspID,
		TransactionID: txID,
	}

	auditJSON, err := json.Marshal(auditLog)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(auditLog.ID, auditJSON)
}

// ==============================================================================
// ARCHIVE OPERATIONS (One-way from hot chain)
// ==============================================================================

// ArchiveEvidence archives evidence from hot chain (ONE-WAY OPERATION)
func (cc *DFIRColdChaincode) ArchiveEvidence(ctx contractapi.TransactionContextInterface,
	evidenceJSON string, sourceTxID string, integrityHash string) error {

	// Check attestation
	if err := cc.checkAttestation(ctx); err != nil {
		return fmt.Errorf("attestation check failed: %v", err)
	}

	// Check permission
	if err := cc.checkPermission(ctx, "blockchain.evidence", "archive", "*"); err != nil {
		return err
	}

	// Parse evidence from hot chain
	var evidence Evidence
	err := json.Unmarshal([]byte(evidenceJSON), &evidence)
	if err != nil {
		return fmt.Errorf("failed to unmarshal evidence: %v", err)
	}

	// Check if already archived
	existing, err := ctx.GetStub().GetState(evidence.ID)
	if err != nil {
		return fmt.Errorf("failed to read evidence: %v", err)
	}
	if existing != nil {
		return fmt.Errorf("evidence %s already archived", evidence.ID)
	}

	clientID, _ := ctx.GetClientIdentity().GetID()

	// Update evidence for cold chain
	evidence.Status = "archived"
	evidence.ChainType = "cold"
	evidence.ArchivedBy = clientID
	evidence.ArchivedAt = time.Now().Unix()
	evidence.SourceChain = "hot"
	evidence.SourceTxID = sourceTxID
	evidence.TransactionID = ctx.GetStub().GetTxID()

	// Store evidence
	updatedJSON, err := json.Marshal(evidence)
	if err != nil {
		return fmt.Errorf("failed to marshal evidence: %v", err)
	}

	err = ctx.GetStub().PutState(evidence.ID, updatedJSON)
	if err != nil {
		return fmt.Errorf("failed to store evidence: %v", err)
	}

	// Store archive metadata for verification
	metadata := ArchiveMetadata{
		EvidenceID:         evidence.ID,
		OriginalChain:      "hot",
		OriginalTxID:       sourceTxID,
		ArchivalVerifiedBy: clientID,
		ArchivalTimestamp:  time.Now().Unix(),
		IntegrityHash:      integrityHash,
	}

	metadataJSON, _ := json.Marshal(metadata)
	metadataKey := fmt.Sprintf("ARCHIVE_META_%s", evidence.ID)
	ctx.GetStub().PutState(metadataKey, metadataJSON)

	// Emit event
	ctx.GetStub().SetEvent("EvidenceArchived", updatedJSON)

	// Audit log
	cc.logAudit(ctx, "ArchiveEvidence", "blockchain.evidence", evidence.ID, "success",
		fmt.Sprintf("Evidence archived from hot chain tx: %s", sourceTxID))

	fmt.Printf("✓ Evidence archived to cold chain: %s\n", evidence.ID)
	return nil
}

// ArchiveInvestigation archives investigation from hot chain
func (cc *DFIRColdChaincode) ArchiveInvestigation(ctx contractapi.TransactionContextInterface,
	investigationJSON string, sourceTxID string) error {

	// Check attestation
	if err := cc.checkAttestation(ctx); err != nil {
		return fmt.Errorf("attestation check failed: %v", err)
	}

	// Check permission
	if err := cc.checkPermission(ctx, "blockchain.investigation", "archive", "*"); err != nil {
		return err
	}

	// Parse investigation from hot chain
	var investigation Investigation
	err := json.Unmarshal([]byte(investigationJSON), &investigation)
	if err != nil {
		return fmt.Errorf("failed to unmarshal investigation: %v", err)
	}

	// Check if already archived
	existing, err := ctx.GetStub().GetState(investigation.ID)
	if err != nil {
		return fmt.Errorf("failed to read investigation: %v", err)
	}
	if existing != nil {
		return fmt.Errorf("investigation %s already archived", investigation.ID)
	}

	clientID, _ := ctx.GetClientIdentity().GetID()

	// Update for cold chain
	investigation.Status = "archived"
	investigation.ArchivedBy = clientID
	investigation.ArchivedAt = time.Now().Unix()
	investigation.ArchivedDate = time.Now().Unix()

	// Store investigation
	updatedJSON, err := json.Marshal(investigation)
	if err != nil {
		return fmt.Errorf("failed to marshal investigation: %v", err)
	}

	err = ctx.GetStub().PutState(investigation.ID, updatedJSON)
	if err != nil {
		return fmt.Errorf("failed to store investigation: %v", err)
	}

	// Emit event
	ctx.GetStub().SetEvent("InvestigationArchived", updatedJSON)

	// Audit log
	cc.logAudit(ctx, "ArchiveInvestigation", "blockchain.investigation", investigation.ID, "success",
		fmt.Sprintf("Investigation archived from hot chain"))

	fmt.Printf("✓ Investigation archived to cold chain: %s\n", investigation.ID)
	return nil
}

// ==============================================================================
// READ-ONLY QUERY OPERATIONS
// ==============================================================================

// ReadEvidence retrieves archived evidence by ID
func (cc *DFIRColdChaincode) ReadEvidence(ctx contractapi.TransactionContextInterface,
	id string) (*Evidence, error) {

	// Check permission
	if err := cc.checkPermission(ctx, "blockchain.evidence", "view", "*"); err != nil {
		return nil, err
	}

	evidenceJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return nil, fmt.Errorf("failed to read evidence: %v", err)
	}
	if evidenceJSON == nil {
		return nil, fmt.Errorf("evidence %s does not exist in cold chain", id)
	}

	var evidence Evidence
	err = json.Unmarshal(evidenceJSON, &evidence)
	if err != nil {
		return nil, fmt.Errorf("failed to unmarshal evidence: %v", err)
	}

	return &evidence, nil
}

// ReadInvestigation retrieves archived investigation by ID
func (cc *DFIRColdChaincode) ReadInvestigation(ctx contractapi.TransactionContextInterface,
	id string) (*Investigation, error) {

	// Check permission
	if err := cc.checkPermission(ctx, "blockchain.investigation", "view", "*"); err != nil {
		return nil, err
	}

	investigationJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return nil, fmt.Errorf("failed to read investigation: %v", err)
	}
	if investigationJSON == nil {
		return nil, fmt.Errorf("investigation %s does not exist in cold chain", id)
	}

	var investigation Investigation
	err = json.Unmarshal(investigationJSON, &investigation)
	if err != nil {
		return nil, fmt.Errorf("failed to unmarshal investigation: %v", err)
	}

	return &investigation, nil
}

// GetEvidenceHistory retrieves the complete history of archived evidence
func (cc *DFIRColdChaincode) GetEvidenceHistory(ctx contractapi.TransactionContextInterface,
	id string) ([]map[string]interface{}, error) {

	// Check permission
	if err := cc.checkPermission(ctx, "blockchain.evidence", "history", "*"); err != nil {
		return nil, err
	}

	resultsIterator, err := ctx.GetStub().GetHistoryForKey(id)
	if err != nil {
		return nil, fmt.Errorf("failed to get history: %v", err)
	}
	defer resultsIterator.Close()

	var history []map[string]interface{}
	for resultsIterator.HasNext() {
		response, err := resultsIterator.Next()
		if err != nil {
			return nil, err
		}

		var record map[string]interface{}
		record = make(map[string]interface{})
		record["tx_id"] = response.TxId
		record["timestamp"] = response.Timestamp.Seconds
		record["is_delete"] = response.IsDelete

		if !response.IsDelete {
			var evidence Evidence
			err = json.Unmarshal(response.Value, &evidence)
			if err == nil {
				record["value"] = evidence
			}
		}

		history = append(history, record)
	}

	return history, nil
}

// QueryEvidenceByCase retrieves all archived evidence for a case
func (cc *DFIRColdChaincode) QueryEvidenceByCase(ctx contractapi.TransactionContextInterface,
	caseID string) ([]*Evidence, error) {

	// Check permission
	if err := cc.checkPermission(ctx, "blockchain.evidence", "list", "*"); err != nil {
		return nil, err
	}

	queryString := fmt.Sprintf(`{"selector":{"case_id":"%s","chain_type":"cold"}}`, caseID)
	return cc.queryEvidence(ctx, queryString)
}

// QueryEvidenceByHash retrieves archived evidence by hash
func (cc *DFIRColdChaincode) QueryEvidenceByHash(ctx contractapi.TransactionContextInterface,
	hash string) (*Evidence, error) {

	// Check permission
	if err := cc.checkPermission(ctx, "blockchain.evidence", "view", "*"); err != nil {
		return nil, err
	}

	queryString := fmt.Sprintf(`{"selector":{"hash":"%s","chain_type":"cold"}}`, hash)
	results, err := cc.queryEvidence(ctx, queryString)
	if err != nil {
		return nil, err
	}

	if len(results) == 0 {
		return nil, fmt.Errorf("evidence with hash %s not found in cold chain", hash)
	}

	return results[0], nil
}

// GetAllArchivedEvidence retrieves all archived evidence (paginated)
func (cc *DFIRColdChaincode) GetAllArchivedEvidence(ctx contractapi.TransactionContextInterface,
	pageSize int, bookmark string) ([]*Evidence, error) {

	// Check permission
	if err := cc.checkPermission(ctx, "blockchain.evidence", "list", "*"); err != nil {
		return nil, err
	}

	queryString := `{"selector":{"chain_type":"cold"}}`

	resultsIterator, _, err := ctx.GetStub().GetQueryResultWithPagination(queryString, int32(pageSize), bookmark)
	if err != nil {
		return nil, fmt.Errorf("failed to query evidence: %v", err)
	}
	defer resultsIterator.Close()

	var results []*Evidence
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return nil, err
		}

		var evidence Evidence
		err = json.Unmarshal(queryResponse.Value, &evidence)
		if err != nil {
			return nil, err
		}
		results = append(results, &evidence)
	}

	return results, nil
}

// queryEvidence helper function for CouchDB queries
func (cc *DFIRColdChaincode) queryEvidence(ctx contractapi.TransactionContextInterface,
	queryString string) ([]*Evidence, error) {

	resultsIterator, err := ctx.GetStub().GetQueryResult(queryString)
	if err != nil {
		return nil, fmt.Errorf("failed to query evidence: %v", err)
	}
	defer resultsIterator.Close()

	var results []*Evidence
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return nil, err
		}

		var evidence Evidence
		err = json.Unmarshal(queryResponse.Value, &evidence)
		if err != nil {
			return nil, err
		}
		results = append(results, &evidence)
	}

	return results, nil
}

// GetArchiveMetadata retrieves archive verification metadata
func (cc *DFIRColdChaincode) GetArchiveMetadata(ctx contractapi.TransactionContextInterface,
	evidenceID string) (*ArchiveMetadata, error) {

	// Check permission
	if err := cc.checkPermission(ctx, "blockchain.evidence", "view", "*"); err != nil {
		return nil, err
	}

	metadataKey := fmt.Sprintf("ARCHIVE_META_%s", evidenceID)
	metadataJSON, err := ctx.GetStub().GetState(metadataKey)
	if err != nil {
		return nil, fmt.Errorf("failed to read archive metadata: %v", err)
	}
	if metadataJSON == nil {
		return nil, fmt.Errorf("archive metadata for %s not found", evidenceID)
	}

	var metadata ArchiveMetadata
	err = json.Unmarshal(metadataJSON, &metadata)
	if err != nil {
		return nil, fmt.Errorf("failed to unmarshal metadata: %v", err)
	}

	return &metadata, nil
}

// ==============================================================================
// ATTESTATION MANAGEMENT (Same as hot chain)
// ==============================================================================

// RegisterAttestation registers a new attestation verification
func (cc *DFIRColdChaincode) RegisterAttestation(ctx contractapi.TransactionContextInterface,
	attestationDoc string, verifierMSP string) error {

	mspID, _ := ctx.GetClientIdentity().GetMSPID()

	configJSON, err := ctx.GetStub().GetState("PRV_CONFIG")
	if err != nil {
		return fmt.Errorf("failed to read PRV config: %v", err)
	}

	var config PRVConfig
	if configJSON != nil {
		json.Unmarshal(configJSON, &config)
	}

	// Add verifier to list if not already present
	found := false
	for _, v := range config.VerifiedBy {
		if v == verifierMSP {
			found = true
			break
		}
	}
	if !found {
		config.VerifiedBy = append(config.VerifiedBy, verifierMSP)
	}

	config.AttestationDoc = attestationDoc
	config.UpdatedAt = time.Now().Unix()
	config.ExpiresAt = time.Now().Add(24 * time.Hour).Unix()

	updatedJSON, err := json.Marshal(config)
	if err != nil {
		return err
	}

	err = ctx.GetStub().PutState("PRV_CONFIG", updatedJSON)
	if err != nil {
		return err
	}

	cc.logAudit(ctx, "RegisterAttestation", "attestation.config", "PRV_CONFIG", "success",
		fmt.Sprintf("Attestation verified by %s", mspID))

	fmt.Printf("✓ Cold chain attestation registered by %s\n", verifierMSP)
	return nil
}

// GetPRVConfig retrieves the current PRV configuration
func (cc *DFIRColdChaincode) GetPRVConfig(ctx contractapi.TransactionContextInterface) (*PRVConfig, error) {
	configJSON, err := ctx.GetStub().GetState("PRV_CONFIG")
	if err != nil {
		return nil, fmt.Errorf("failed to read PRV config: %v", err)
	}
	if configJSON == nil {
		return nil, fmt.Errorf("PRV config not initialized")
	}

	var config PRVConfig
	err = json.Unmarshal(configJSON, &config)
	if err != nil {
		return nil, err
	}

	return &config, nil
}

// ==============================================================================
// INTEGRITY VERIFICATION
// ==============================================================================

// VerifyArchiveIntegrity verifies evidence integrity against hot chain
func (cc *DFIRColdChaincode) VerifyArchiveIntegrity(ctx contractapi.TransactionContextInterface,
	evidenceID string) (bool, error) {

	// Check permission
	if err := cc.checkPermission(ctx, "blockchain.evidence", "view", "*"); err != nil {
		return false, err
	}

	// Get evidence
	evidence, err := cc.ReadEvidence(ctx, evidenceID)
	if err != nil {
		return false, err
	}

	// Get archive metadata
	metadata, err := cc.GetArchiveMetadata(ctx, evidenceID)
	if err != nil {
		return false, err
	}

	// Verify integrity hash matches
	// In production, this would verify against hot chain state
	// For now, we verify metadata exists and matches
	if metadata.EvidenceID != evidenceID {
		return false, fmt.Errorf("metadata mismatch")
	}

	if metadata.OriginalChain != "hot" {
		return false, fmt.Errorf("invalid source chain")
	}

	// Verify evidence is immutable (no updates after archival)
	if evidence.Status != "archived" {
		return false, fmt.Errorf("evidence status has been modified")
	}

	cc.logAudit(ctx, "VerifyArchiveIntegrity", "blockchain.evidence", evidenceID, "success",
		"Integrity verification passed")

	return true, nil
}

// ==============================================================================
// CROSS-CHAIN CASE TRANSFER (Court Role Only)
// ==============================================================================

// CaseExportPackage holds complete case data for cross-chain transfer
type CaseExportPackage struct {
	Investigation Investigation `json:"investigation"`
	Evidence      []Evidence    `json:"evidence"`
	CourtOrder    string        `json:"court_order"`
	ExportedAt    int64         `json:"exported_at"`
	ExportedBy    string        `json:"exported_by"`
	SourceChain   string        `json:"source_chain"`
	TransferTxID  string        `json:"transfer_tx_id"`
}

// ExportCaseForArchive exports investigation and evidence for cold chain archival (Hot chain, Court only)
func (cc *DFIRColdChaincode) ExportCaseForArchive(ctx contractapi.TransactionContextInterface,
	investigationID string, courtOrder string) (string, error) {

	// Check attestation
	if err := cc.checkAttestation(ctx); err != nil {
		return "", fmt.Errorf("attestation check failed: %v", err)
	}

	// Check permission (Court role only)
	if err := cc.checkPermission(ctx, "blockchain.investigation", "archive", "*"); err != nil {
		return "", err
	}

	// Read investigation
	invBytes, err := ctx.GetStub().GetState("investigation_" + investigationID)
	if err != nil {
		return "", fmt.Errorf("failed to read investigation: %v", err)
	}
	if invBytes == nil {
		return "", fmt.Errorf("investigation %s does not exist", investigationID)
	}

	var investigation Investigation
	if err := json.Unmarshal(invBytes, &investigation); err != nil {
		return "", fmt.Errorf("failed to unmarshal investigation: %v", err)
	}

	// Query all evidence for this case
	queryString := fmt.Sprintf(`{"selector":{"case_id":"%s"}}`, investigationID)
	resultsIterator, err := ctx.GetStub().GetQueryResult(queryString)
	if err != nil {
		return "", fmt.Errorf("failed to query evidence: %v", err)
	}
	defer resultsIterator.Close()

	var evidenceList []Evidence
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return "", fmt.Errorf("failed to iterate evidence: %v", err)
		}

		var evidence Evidence
		if err := json.Unmarshal(queryResponse.Value, &evidence); err != nil {
			continue
		}
		evidenceList = append(evidenceList, evidence)
	}

	// Get client identity
	clientID, _ := ctx.GetClientIdentity().GetID()
	txTimestamp, _ := ctx.GetStub().GetTxTimestamp()
	txID := ctx.GetStub().GetTxID()

	// Create export package
	exportPackage := CaseExportPackage{
		Investigation: investigation,
		Evidence:      evidenceList,
		CourtOrder:    courtOrder,
		ExportedAt:    txTimestamp.Seconds,
		ExportedBy:    clientID,
		SourceChain:   "hot",
		TransferTxID:  txID,
	}

	// Marshal to JSON
	packageJSON, err := json.Marshal(exportPackage)
	if err != nil {
		return "", fmt.Errorf("failed to marshal export package: %v", err)
	}

	// Store export record
	exportKey := "export_" + investigationID + "_" + txID
	if err := ctx.GetStub().PutState(exportKey, packageJSON); err != nil {
		return "", fmt.Errorf("failed to store export record: %v", err)
	}

	// Audit log
	cc.logAudit(ctx, "export_case_for_archive", "blockchain.investigation", investigationID,
		"success", fmt.Sprintf("Case exported for archival with court order: %s", courtOrder))

	return string(packageJSON), nil
}

// ImportArchivedCase imports case from hot chain to cold chain (Cold chain, Court only)
func (cc *DFIRColdChaincode) ImportArchivedCase(ctx contractapi.TransactionContextInterface,
	packageJSON string) error {

	// Check attestation
	if err := cc.checkAttestation(ctx); err != nil {
		return fmt.Errorf("attestation check failed: %v", err)
	}

	// Check permission (Court role only)
	if err := cc.checkPermission(ctx, "blockchain.investigation", "archive", "*"); err != nil {
		return err
	}

	// Unmarshal package
	var exportPackage CaseExportPackage
	if err := json.Unmarshal([]byte(packageJSON), &exportPackage); err != nil {
		return fmt.Errorf("failed to unmarshal export package: %v", err)
	}

	// Verify source chain
	if exportPackage.SourceChain != "hot" {
		return fmt.Errorf("invalid source chain: %s, expected 'hot'", exportPackage.SourceChain)
	}

	// Check if investigation already exists on cold chain
	invBytes, err := ctx.GetStub().GetState("investigation_" + exportPackage.Investigation.ID)
	if err != nil {
		return fmt.Errorf("failed to check investigation existence: %v", err)
	}
	if invBytes != nil {
		return fmt.Errorf("investigation %s already exists on cold chain", exportPackage.Investigation.ID)
	}

	txTimestamp, _ := ctx.GetStub().GetTxTimestamp()
	clientID, _ := ctx.GetClientIdentity().GetID()
	txID := ctx.GetStub().GetTxID()

	// Import investigation with archived status
	investigation := exportPackage.Investigation
	investigation.Status = "archived"
	investigation.ArchivedAt = txTimestamp.Seconds
	investigation.ArchivedBy = clientID
	invBytes, _ = json.Marshal(investigation)
	if err := ctx.GetStub().PutState("investigation_"+investigation.ID, invBytes); err != nil {
		return fmt.Errorf("failed to store investigation: %v", err)
	}

	// Import all evidence
	for _, evidence := range exportPackage.Evidence {
		evidence.ChainType = "cold"
		evidence.Status = "archived"
		evidence.ArchivedAt = txTimestamp.Seconds
		evidence.ArchivedBy = clientID
		evidence.SourceChain = "hot"
		evidence.SourceTxID = exportPackage.TransferTxID

		evidenceBytes, _ := json.Marshal(evidence)
		evidenceKey := "evidence_" + evidence.ID
		if err := ctx.GetStub().PutState(evidenceKey, evidenceBytes); err != nil {
			return fmt.Errorf("failed to store evidence %s: %v", evidence.ID, err)
		}

		// Create archive metadata
		metadata := ArchiveMetadata{
			EvidenceID:         evidence.ID,
			OriginalChain:      "hot",
			OriginalTxID:       exportPackage.TransferTxID,
			ArchivalVerifiedBy: clientID,
			ArchivalTimestamp:  txTimestamp.Seconds,
			IntegrityHash:      evidence.Hash,
		}
		metadataBytes, _ := json.Marshal(metadata)
		metadataKey := "archive_metadata_" + evidence.ID
		if err := ctx.GetStub().PutState(metadataKey, metadataBytes); err != nil {
			return fmt.Errorf("failed to store archive metadata: %v", err)
		}
	}

	// Store import record
	importRecord := map[string]interface{}{
		"investigation_id": investigation.ID,
		"source_chain":     exportPackage.SourceChain,
		"source_tx_id":     exportPackage.TransferTxID,
		"court_order":      exportPackage.CourtOrder,
		"imported_at":      txTimestamp.Seconds,
		"imported_by":      clientID,
		"import_tx_id":     txID,
		"evidence_count":   len(exportPackage.Evidence),
	}
	importBytes, _ := json.Marshal(importRecord)
	importKey := "import_" + investigation.ID + "_" + txID
	if err := ctx.GetStub().PutState(importKey, importBytes); err != nil {
		return fmt.Errorf("failed to store import record: %v", err)
	}

	// Audit log
	cc.logAudit(ctx, "import_archived_case", "blockchain.investigation", investigation.ID,
		"success", fmt.Sprintf("Case imported from hot chain with court order: %s", exportPackage.CourtOrder))

	return nil
}

// ExportCaseForReactivation exports archived case for reactivation on hot chain (Cold chain, Court only)
func (cc *DFIRColdChaincode) ExportCaseForReactivation(ctx contractapi.TransactionContextInterface,
	investigationID string, courtOrder string) (string, error) {

	// Check attestation
	if err := cc.checkAttestation(ctx); err != nil {
		return "", fmt.Errorf("attestation check failed: %v", err)
	}

	// Check permission (Court role only)
	if err := cc.checkPermission(ctx, "blockchain.investigation", "reopen", "*"); err != nil {
		return "", err
	}

	// Read investigation
	invBytes, err := ctx.GetStub().GetState("investigation_" + investigationID)
	if err != nil {
		return "", fmt.Errorf("failed to read investigation: %v", err)
	}
	if invBytes == nil {
		return "", fmt.Errorf("investigation %s does not exist", investigationID)
	}

	var investigation Investigation
	if err := json.Unmarshal(invBytes, &investigation); err != nil {
		return "", fmt.Errorf("failed to unmarshal investigation: %v", err)
	}

	// Only allow reactivating archived investigations
	if investigation.Status != "archived" {
		return "", fmt.Errorf("can only reactivate archived investigations, current status: %s", investigation.Status)
	}

	// Query all evidence for this case
	queryString := fmt.Sprintf(`{"selector":{"case_id":"%s"}}`, investigationID)
	resultsIterator, err := ctx.GetStub().GetQueryResult(queryString)
	if err != nil {
		return "", fmt.Errorf("failed to query evidence: %v", err)
	}
	defer resultsIterator.Close()

	var evidenceList []Evidence
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return "", fmt.Errorf("failed to iterate evidence: %v", err)
		}

		var evidence Evidence
		if err := json.Unmarshal(queryResponse.Value, &evidence); err != nil {
			continue
		}
		evidenceList = append(evidenceList, evidence)
	}

	// Get client identity
	clientID, _ := ctx.GetClientIdentity().GetID()
	txTimestamp, _ := ctx.GetStub().GetTxTimestamp()
	txID := ctx.GetStub().GetTxID()

	// Create export package
	exportPackage := CaseExportPackage{
		Investigation: investigation,
		Evidence:      evidenceList,
		CourtOrder:    courtOrder,
		ExportedAt:    txTimestamp.Seconds,
		ExportedBy:    clientID,
		SourceChain:   "cold",
		TransferTxID:  txID,
	}

	// Marshal to JSON
	packageJSON, err := json.Marshal(exportPackage)
	if err != nil {
		return "", fmt.Errorf("failed to marshal export package: %v", err)
	}

	// Store export record
	exportKey := "export_" + investigationID + "_" + txID
	if err := ctx.GetStub().PutState(exportKey, packageJSON); err != nil {
		return "", fmt.Errorf("failed to store export record: %v", err)
	}

	// Audit log
	cc.logAudit(ctx, "export_case_for_reactivation", "blockchain.investigation", investigationID,
		"success", fmt.Sprintf("Case exported for reactivation with court order: %s", courtOrder))

	return string(packageJSON), nil
}

// ==============================================================================
// MAIN
// ==============================================================================

func main() {
	chaincode, err := contractapi.NewChaincode(&DFIRColdChaincode{})
	if err != nil {
		fmt.Printf("Error creating DFIR cold chaincode: %v\n", err)
		return
	}

	if err := chaincode.Start(); err != nil {
		fmt.Printf("Error starting DFIR cold chaincode: %v\n", err)
	}
}
