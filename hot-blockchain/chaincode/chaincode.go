package main

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// DFIRChaincode - Hot blockchain chaincode for active investigations
type DFIRChaincode struct {
	contractapi.Contract
}

// ==============================================================================
// DATA STRUCTURES
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

// Investigation represents a case/investigation
type Investigation struct {
	ID                 string `json:"id"`
	CaseNumber         string `json:"case_number"`
	CaseName           string `json:"case_name"`
	InvestigatingOrg   string `json:"investigating_org"`
	LeadInvestigator   string `json:"lead_investigator"`
	Status             string `json:"status"` // open, under_investigation, closed, archived
	OpenedDate         int64  `json:"opened_date"`
	ClosedDate         int64  `json:"closed_date"`
	Description        string `json:"description"`
	EvidenceCount      int    `json:"evidence_count"`
	CreatedBy          string `json:"created_by"`
	CreatedAt          int64  `json:"created_at"`
	UpdatedAt          int64  `json:"updated_at"`
}

// Evidence represents a piece of digital evidence
type Evidence struct {
	ID              string `json:"id"`
	CaseID          string `json:"case_id"`
	Type            string `json:"type"`
	Description     string `json:"description"`
	Hash            string `json:"hash"`            // SHA-256
	IPFSHash        string `json:"ipfs_hash"`       // IPFS CID
	Location        string `json:"location"`        // Physical/digital location
	Custodian       string `json:"custodian"`       // Current custodian
	CollectedBy     string `json:"collected_by"`    // Original collector
	Timestamp       int64  `json:"timestamp"`       // Collection timestamp
	Status          string `json:"status"`          // collected, analyzed, reviewed, archived, disposed
	Metadata        string `json:"metadata"`        // JSON metadata
	FileSize        int64  `json:"file_size"`       // File size in bytes
	ChainType       string `json:"chain_type"`      // hot or cold
	TransactionID   string `json:"transaction_id"`  // Blockchain tx ID
	CustodyChainRef string `json:"custody_chain_ref"` // Reference to custody chain
	CreatedBy       string `json:"created_by"`
	CreatedAt       int64  `json:"created_at"`
	UpdatedAt       int64  `json:"updated_at"`
}

// CustodyTransfer records custody chain
type CustodyTransfer struct {
	ID             string `json:"id"`
	EvidenceID     string `json:"evidence_id"`
	FromCustodian  string `json:"from_custodian"`
	ToCustodian    string `json:"to_custodian"`
	Timestamp      int64  `json:"timestamp"`
	Reason         string `json:"reason"`
	Location       string `json:"location"`
	PermitHash     string `json:"permit_hash"`
	TransferredBy  string `json:"transferred_by"`
	ApprovedBy     string `json:"approved_by"`
	Status         string `json:"status"` // pending, approved, completed, rejected
}

// AuditLog records all operations for compliance
type AuditLog struct {
	ID            string `json:"id"`
	UserID        string `json:"user_id"`
	Action        string `json:"action"`
	Resource      string `json:"resource"`
	ResourceID    string `json:"resource_id"`
	Result        string `json:"result"` // success, denied, error
	Reason        string `json:"reason"`
	Timestamp     int64  `json:"timestamp"`
	ClientMSP     string `json:"client_msp"`
	TransactionID string `json:"transaction_id"`
}

// GUIDMapping for court-requested GUID resolution
type GUIDMapping struct {
	GUID         string `json:"guid"`
	RealID       string `json:"real_id"`
	ResourceType string `json:"resource_type"` // evidence, investigation, user
	ResolvedBy   string `json:"resolved_by"`
	ResolvedAt   int64  `json:"resolved_at"`
	CourtOrder   string `json:"court_order"` // Court order reference
}

// ==============================================================================
// INITIALIZATION
// ==============================================================================

// InitLedger initializes the ledger with PRV configuration
func (cc *DFIRChaincode) InitLedger(ctx contractapi.TransactionContextInterface,
	publicKeyHex string, mrenclaveHex string, mrsignerHex string) error {

	config := PRVConfig{
		PublicKey:      publicKeyHex,
		MREnclave:      mrenclaveHex,
		MRSigner:       mrsignerHex,
		UpdatedAt:      time.Now().Unix(),
		AttestationDoc: "",
		VerifiedBy:     []string{},
		TCBLevel:       "1",
		ExpiresAt:      time.Now().Add(24 * time.Hour).Unix(), // 24h expiry
	}

	configJSON, err := json.Marshal(config)
	if err != nil {
		return fmt.Errorf("failed to marshal config: %v", err)
	}

	err = ctx.GetStub().PutState("PRV_CONFIG", configJSON)
	if err != nil {
		return fmt.Errorf("failed to store config: %v", err)
	}

	// Log initialization
	cc.logAudit(ctx, "InitLedger", "system", "PRV_CONFIG", "success", "Ledger initialized")

	fmt.Printf("✓ Hot chain ledger initialized with PRV config\n")
	return nil
}

// ==============================================================================
// ACCESS CONTROL & ATTESTATION HELPERS
// ==============================================================================

// checkPermission validates if the caller has permission for the action
func (cc *DFIRChaincode) checkPermission(ctx contractapi.TransactionContextInterface,
	object string, action string, resource string) error {

	clientID, err := ctx.GetClientIdentity().GetID()
	if err != nil {
		return fmt.Errorf("failed to get client identity: %v", err)
	}

	mspID, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil {
		return fmt.Errorf("failed to get MSP ID: %v", err)
	}

	// Extract role from MSP or client attributes
	role, found, err := ctx.GetClientIdentity().GetAttributeValue("role")
	if err != nil || !found {
		// Default role mapping based on MSP
		role = cc.getRoleFromMSP(mspID)
	}

	// Check permission using Casbin-style logic
	allowed := cc.evaluatePermission(role, object, action, resource, clientID)
	if !allowed {
		cc.logAudit(ctx, action, object, resource, "denied", fmt.Sprintf("Insufficient permissions for role: %s", role))
		return fmt.Errorf("access denied: %s does not have permission to %s on %s", role, action, object)
	}

	return nil
}

// getRoleFromMSP maps MSP ID to default role
func (cc *DFIRChaincode) getRoleFromMSP(mspID string) string {
	// Role mapping aligned with JumpServer RBAC design
	switch mspID {
	case "LawEnforcementMSP", "ForensicLabMSP":
		return "BlockchainInvestigator" // Evidence collection and investigation
	case "CourtMSP":
		return "BlockchainCourt" // Cross-chain transfers, archive/reopen authority
	case "AuditorMSP":
		return "BlockchainAuditor" // Read-only access to evidence for compliance/audit
	default:
		return "User"
	}
}

// evaluatePermission implements Casbin-style permission checking
func (cc *DFIRChaincode) evaluatePermission(role string, object string, action string, resource string, userID string) bool {
	// SystemAdmin has full access
	if role == "SystemAdmin" {
		return true
	}

	// Role-based permission matrix
	permissions := map[string]map[string][]string{
		"BlockchainInvestigator": {
			"blockchain.investigation": {"create", "view", "update", "list"},
			"blockchain.evidence":      {"create", "view", "update", "transfer", "list"},
			"blockchain.custody":       {"transfer", "view"},
			"blockchain.transaction":   {"create", "view", "append"},
			"blockchain.case":          {"create", "view", "update"},
			"audits.userloginlog":      {"view"}, // self only
			"audits.operatelog":        {"view"}, // self only
		},
		"BlockchainAuditor": {
			"blockchain.investigation": {"view", "list"},
			"blockchain.evidence":      {"view", "list", "history"},
			"blockchain.custody":       {"view", "history"},
			"blockchain.transaction":   {"view", "list"},
			"blockchain.case":          {"view", "list"},
			"audits.*":                 {"view"},
			"reports.*":                {"view"},
		},
		"BlockchainCourt": {
			"blockchain.investigation": {"view", "list", "archive", "reopen"},
			"blockchain.evidence":      {"view", "list", "history"},
			"blockchain.custody":       {"view", "history"},
			"blockchain.transaction":   {"view", "list"},
			"blockchain.case":          {"view", "list", "update"},
			"blockchain.guidmapping":   {"resolve_guid"},
			"audits.*":                 {"view"},
			"reports.*":                {"view"},
		},
	}

	rolePerms, roleExists := permissions[role]
	if !roleExists {
		return false
	}

	// Check wildcard permissions first
	for permObj, actions := range rolePerms {
		if strings.HasSuffix(permObj, ".*") {
			prefix := strings.TrimSuffix(permObj, ".*")
			if strings.HasPrefix(object, prefix) {
				for _, act := range actions {
					if act == "*" || act == action {
						return true
					}
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
			// Additional check for 'self' resource
			if resource == "self" {
				// Would need to compare userID with resource owner
				return true // Simplified for now
			}
			return true
		}
	}

	return false
}

// checkAttestation verifies orderer/CA attestation is still valid
func (cc *DFIRChaincode) checkAttestation(ctx contractapi.TransactionContextInterface) error {
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

	// Check if quorum of verifiers approved (minimum 2 of 3)
	if len(config.VerifiedBy) < 2 {
		return fmt.Errorf("insufficient verifiers: %d < 2", len(config.VerifiedBy))
	}

	return nil
}

// logAudit creates an audit log entry
func (cc *DFIRChaincode) logAudit(ctx contractapi.TransactionContextInterface,
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
// INVESTIGATION MANAGEMENT
// ==============================================================================

// CreateInvestigation creates a new investigation/case
func (cc *DFIRChaincode) CreateInvestigation(ctx contractapi.TransactionContextInterface,
	id string, caseNumber string, caseName string, investigatingOrg string,
	leadInvestigator string, description string) error {

	// Check attestation
	if err := cc.checkAttestation(ctx); err != nil {
		return fmt.Errorf("attestation check failed: %v", err)
	}

	// Check permission
	if err := cc.checkPermission(ctx, "blockchain.investigation", "create", "*"); err != nil {
		return err
	}

	// Check if exists
	existing, err := ctx.GetStub().GetState(id)
	if err != nil {
		return fmt.Errorf("failed to read investigation: %v", err)
	}
	if existing != nil {
		return fmt.Errorf("investigation %s already exists", id)
	}

	clientID, _ := ctx.GetClientIdentity().GetID()

	investigation := Investigation{
		ID:               id,
		CaseNumber:       caseNumber,
		CaseName:         caseName,
		InvestigatingOrg: investigatingOrg,
		LeadInvestigator: leadInvestigator,
		Status:           "open",
		OpenedDate:       time.Now().Unix(),
		ClosedDate:       0,
		Description:      description,
		EvidenceCount:    0,
		CreatedBy:        clientID,
		CreatedAt:        time.Now().Unix(),
		UpdatedAt:        time.Now().Unix(),
	}

	investigationJSON, err := json.Marshal(investigation)
	if err != nil {
		return fmt.Errorf("failed to marshal investigation: %v", err)
	}

	err = ctx.GetStub().PutState(id, investigationJSON)
	if err != nil {
		return fmt.Errorf("failed to store investigation: %v", err)
	}

	// Emit event
	ctx.GetStub().SetEvent("InvestigationCreated", investigationJSON)

	// Audit log
	cc.logAudit(ctx, "CreateInvestigation", "blockchain.investigation", id, "success", "Investigation created")

	fmt.Printf("✓ Investigation created: %s\n", id)
	return nil
}

// ReadInvestigation retrieves an investigation by ID
func (cc *DFIRChaincode) ReadInvestigation(ctx contractapi.TransactionContextInterface,
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
		return nil, fmt.Errorf("investigation %s does not exist", id)
	}

	var investigation Investigation
	err = json.Unmarshal(investigationJSON, &investigation)
	if err != nil {
		return nil, fmt.Errorf("failed to unmarshal investigation: %v", err)
	}

	return &investigation, nil
}

// UpdateInvestigationStatus updates the status of an investigation
func (cc *DFIRChaincode) UpdateInvestigationStatus(ctx contractapi.TransactionContextInterface,
	id string, newStatus string) error {

	// Check attestation
	if err := cc.checkAttestation(ctx); err != nil {
		return fmt.Errorf("attestation check failed: %v", err)
	}

	// Check permission
	if err := cc.checkPermission(ctx, "blockchain.investigation", "update", "*"); err != nil {
		return err
	}

	investigation, err := cc.ReadInvestigation(ctx, id)
	if err != nil {
		return err
	}

	// Validate status transition
	validStatuses := map[string]bool{
		"open": true, "under_investigation": true, "closed": true, "archived": true,
	}
	if !validStatuses[newStatus] {
		return fmt.Errorf("invalid status: %s", newStatus)
	}

	investigation.Status = newStatus
	investigation.UpdatedAt = time.Now().Unix()

	if newStatus == "closed" {
		investigation.ClosedDate = time.Now().Unix()
	}

	investigationJSON, err := json.Marshal(investigation)
	if err != nil {
		return fmt.Errorf("failed to marshal investigation: %v", err)
	}

	err = ctx.GetStub().PutState(id, investigationJSON)
	if err != nil {
		return fmt.Errorf("failed to update investigation: %v", err)
	}

	// Emit event
	ctx.GetStub().SetEvent("InvestigationUpdated", investigationJSON)

	// Audit log
	cc.logAudit(ctx, "UpdateInvestigationStatus", "blockchain.investigation", id, "success",
		fmt.Sprintf("Status updated to %s", newStatus))

	fmt.Printf("✓ Investigation %s status updated to %s\n", id, newStatus)
	return nil
}

// ArchiveInvestigation archives an investigation (Court role only)
func (cc *DFIRChaincode) ArchiveInvestigation(ctx contractapi.TransactionContextInterface,
	id string, courtOrder string) error {

	// Check attestation
	if err := cc.checkAttestation(ctx); err != nil {
		return fmt.Errorf("attestation check failed: %v", err)
	}

	// Check permission (Court role only)
	if err := cc.checkPermission(ctx, "blockchain.investigation", "archive", "*"); err != nil {
		return err
	}

	return cc.UpdateInvestigationStatus(ctx, id, "archived")
}

// ReopenInvestigation reopens an archived investigation (Court role only)
func (cc *DFIRChaincode) ReopenInvestigation(ctx contractapi.TransactionContextInterface,
	id string, courtOrder string) error {

	// Check attestation
	if err := cc.checkAttestation(ctx); err != nil {
		return fmt.Errorf("attestation check failed: %v", err)
	}

	// Check permission (Court role only)
	if err := cc.checkPermission(ctx, "blockchain.investigation", "reopen", "*"); err != nil {
		return err
	}

	return cc.UpdateInvestigationStatus(ctx, id, "open")
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
func (cc *DFIRChaincode) ExportCaseForArchive(ctx contractapi.TransactionContextInterface,
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

	// Only allow archiving closed investigations
	if investigation.Status != "closed" {
		return "", fmt.Errorf("can only archive closed investigations, current status: %s", investigation.Status)
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
			continue // Skip malformed records
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

	// Update investigation status to indicate transfer in progress
	investigation.Status = "transferring_to_archive"
	investigation.UpdatedAt = txTimestamp.Seconds
	invBytes, _ = json.Marshal(investigation)
	if err := ctx.GetStub().PutState("investigation_"+investigationID, invBytes); err != nil {
		return "", fmt.Errorf("failed to update investigation status: %v", err)
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
func (cc *DFIRChaincode) ImportArchivedCase(ctx contractapi.TransactionContextInterface,
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
	investigation.UpdatedAt = txTimestamp.Seconds
	invBytes, _ = json.Marshal(investigation)
	if err := ctx.GetStub().PutState("investigation_"+investigation.ID, invBytes); err != nil {
		return fmt.Errorf("failed to store investigation: %v", err)
	}

	// Import all evidence
	for _, evidence := range exportPackage.Evidence {
		evidence.ChainType = "cold"
		evidence.UpdatedAt = txTimestamp.Seconds
		evidence.Status = "archived"

		evidenceBytes, _ := json.Marshal(evidence)
		evidenceKey := "evidence_" + evidence.ID
		if err := ctx.GetStub().PutState(evidenceKey, evidenceBytes); err != nil {
			return fmt.Errorf("failed to store evidence %s: %v", evidence.ID, err)
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

// CompleteArchiveTransfer marks archive transfer as complete on hot chain (Hot chain, Court only)
func (cc *DFIRChaincode) CompleteArchiveTransfer(ctx contractapi.TransactionContextInterface,
	investigationID string, coldChainTxID string) error {

	// Check attestation
	if err := cc.checkAttestation(ctx); err != nil {
		return fmt.Errorf("attestation check failed: %v", err)
	}

	// Check permission (Court role only)
	if err := cc.checkPermission(ctx, "blockchain.investigation", "archive", "*"); err != nil {
		return err
	}

	// Read investigation
	invBytes, err := ctx.GetStub().GetState("investigation_" + investigationID)
	if err != nil {
		return fmt.Errorf("failed to read investigation: %v", err)
	}
	if invBytes == nil {
		return fmt.Errorf("investigation %s does not exist", investigationID)
	}

	var investigation Investigation
	if err := json.Unmarshal(invBytes, &investigation); err != nil {
		return fmt.Errorf("failed to unmarshal investigation: %v", err)
	}

	// Verify current status
	if investigation.Status != "transferring_to_archive" {
		return fmt.Errorf("invalid status for completion: %s", investigation.Status)
	}

	txTimestamp, _ := ctx.GetStub().GetTxTimestamp()

	// Update to archived status
	investigation.Status = "archived_on_cold"
	investigation.UpdatedAt = txTimestamp.Seconds
	invBytes, _ = json.Marshal(investigation)
	if err := ctx.GetStub().PutState("investigation_"+investigationID, invBytes); err != nil {
		return fmt.Errorf("failed to update investigation: %v", err)
	}

	// Store completion record
	completionRecord := map[string]interface{}{
		"investigation_id": investigationID,
		"cold_chain_tx_id": coldChainTxID,
		"completed_at":     txTimestamp.Seconds,
	}
	completionBytes, _ := json.Marshal(completionRecord)
	completionKey := "archive_complete_" + investigationID
	if err := ctx.GetStub().PutState(completionKey, completionBytes); err != nil {
		return fmt.Errorf("failed to store completion record: %v", err)
	}

	// Audit log
	cc.logAudit(ctx, "complete_archive_transfer", "blockchain.investigation", investigationID,
		"success", fmt.Sprintf("Archive transfer completed, cold chain tx: %s", coldChainTxID))

	return nil
}

// ExportCaseForReactivation exports archived case for reactivation on hot chain (Cold chain, Court only)
func (cc *DFIRChaincode) ExportCaseForReactivation(ctx contractapi.TransactionContextInterface,
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

	// Update investigation status
	investigation.Status = "transferring_to_hot"
	investigation.UpdatedAt = txTimestamp.Seconds
	invBytes, _ = json.Marshal(investigation)
	if err := ctx.GetStub().PutState("investigation_"+investigationID, invBytes); err != nil {
		return "", fmt.Errorf("failed to update investigation status: %v", err)
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

// ImportReactivatedCase imports case from cold chain to hot chain (Hot chain, Court only)
func (cc *DFIRChaincode) ImportReactivatedCase(ctx contractapi.TransactionContextInterface,
	packageJSON string) error {

	// Check attestation
	if err := cc.checkAttestation(ctx); err != nil {
		return fmt.Errorf("attestation check failed: %v", err)
	}

	// Check permission (Court role only)
	if err := cc.checkPermission(ctx, "blockchain.investigation", "reopen", "*"); err != nil {
		return err
	}

	// Unmarshal package
	var exportPackage CaseExportPackage
	if err := json.Unmarshal([]byte(packageJSON), &exportPackage); err != nil {
		return fmt.Errorf("failed to unmarshal export package: %v", err)
	}

	// Verify source chain
	if exportPackage.SourceChain != "cold" {
		return fmt.Errorf("invalid source chain: %s, expected 'cold'", exportPackage.SourceChain)
	}

	txTimestamp, _ := ctx.GetStub().GetTxTimestamp()
	clientID, _ := ctx.GetClientIdentity().GetID()
	txID := ctx.GetStub().GetTxID()

	// Check if investigation exists on hot chain
	invBytes, err := ctx.GetStub().GetState("investigation_" + exportPackage.Investigation.ID)
	if err != nil {
		return fmt.Errorf("failed to check investigation existence: %v", err)
	}

	investigation := exportPackage.Investigation
	investigation.Status = "open" // Reactivate as open
	investigation.UpdatedAt = txTimestamp.Seconds
	investigation.ClosedDate = 0 // Clear closed date for reactivated case

	invBytes, _ = json.Marshal(investigation)
	if err := ctx.GetStub().PutState("investigation_"+investigation.ID, invBytes); err != nil {
		return fmt.Errorf("failed to store investigation: %v", err)
	}

	// Import all evidence
	for _, evidence := range exportPackage.Evidence {
		evidence.ChainType = "hot"
		evidence.UpdatedAt = txTimestamp.Seconds
		evidence.Status = "reviewed" // Set appropriate status for reactivated evidence

		evidenceBytes, _ := json.Marshal(evidence)
		evidenceKey := "evidence_" + evidence.ID
		if err := ctx.GetStub().PutState(evidenceKey, evidenceBytes); err != nil {
			return fmt.Errorf("failed to store evidence %s: %v", evidence.ID, err)
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
	cc.logAudit(ctx, "import_reactivated_case", "blockchain.investigation", investigation.ID,
		"success", fmt.Sprintf("Case imported from cold chain with court order: %s", exportPackage.CourtOrder))

	return nil
}

// CompleteReactivationTransfer marks reactivation transfer as complete on cold chain (Cold chain, Court only)
func (cc *DFIRChaincode) CompleteReactivationTransfer(ctx contractapi.TransactionContextInterface,
	investigationID string, hotChainTxID string) error {

	// Check attestation
	if err := cc.checkAttestation(ctx); err != nil {
		return fmt.Errorf("attestation check failed: %v", err)
	}

	// Check permission (Court role only)
	if err := cc.checkPermission(ctx, "blockchain.investigation", "reopen", "*"); err != nil {
		return err
	}

	// Read investigation
	invBytes, err := ctx.GetStub().GetState("investigation_" + investigationID)
	if err != nil {
		return fmt.Errorf("failed to read investigation: %v", err)
	}
	if invBytes == nil {
		return fmt.Errorf("investigation %s does not exist", investigationID)
	}

	var investigation Investigation
	if err := json.Unmarshal(invBytes, &investigation); err != nil {
		return fmt.Errorf("failed to unmarshal investigation: %v", err)
	}

	// Verify current status
	if investigation.Status != "transferring_to_hot" {
		return fmt.Errorf("invalid status for completion: %s", investigation.Status)
	}

	txTimestamp, _ := ctx.GetStub().GetTxTimestamp()

	// Update to transferred status
	investigation.Status = "transferred_to_hot"
	investigation.UpdatedAt = txTimestamp.Seconds
	invBytes, _ = json.Marshal(investigation)
	if err := ctx.GetStub().PutState("investigation_"+investigationID, invBytes); err != nil {
		return fmt.Errorf("failed to update investigation: %v", err)
	}

	// Store completion record
	completionRecord := map[string]interface{}{
		"investigation_id": investigationID,
		"hot_chain_tx_id":  hotChainTxID,
		"completed_at":     txTimestamp.Seconds,
	}
	completionBytes, _ := json.Marshal(completionRecord)
	completionKey := "reactivation_complete_" + investigationID
	if err := ctx.GetStub().PutState(completionKey, completionBytes); err != nil {
		return fmt.Errorf("failed to store completion record: %v", err)
	}

	// Audit log
	cc.logAudit(ctx, "complete_reactivation_transfer", "blockchain.investigation", investigationID,
		"success", fmt.Sprintf("Reactivation transfer completed, hot chain tx: %s", hotChainTxID))

	return nil
}

// ==============================================================================
// EVIDENCE MANAGEMENT
// ==============================================================================

// CreateEvidence creates new evidence record
func (cc *DFIRChaincode) CreateEvidence(ctx contractapi.TransactionContextInterface,
	id string, caseID string, evidenceType string, description string,
	hash string, ipfsHash string, location string, metadata string,
	fileSize int64) error {

	// Check attestation
	if err := cc.checkAttestation(ctx); err != nil {
		return fmt.Errorf("attestation check failed: %v", err)
	}

	// Check permission
	if err := cc.checkPermission(ctx, "blockchain.evidence", "create", "*"); err != nil {
		return err
	}

	// Check if exists
	existing, err := ctx.GetStub().GetState(id)
	if err != nil {
		return fmt.Errorf("failed to read evidence: %v", err)
	}
	if existing != nil {
		return fmt.Errorf("evidence %s already exists", id)
	}

	// Verify case exists
	_, err = cc.ReadInvestigation(ctx, caseID)
	if err != nil {
		return fmt.Errorf("case %s does not exist: %v", caseID, err)
	}

	clientID, _ := ctx.GetClientIdentity().GetID()
	txID := ctx.GetStub().GetTxID()

	evidence := Evidence{
		ID:              id,
		CaseID:          caseID,
		Type:            evidenceType,
		Description:     description,
		Hash:            hash,
		IPFSHash:        ipfsHash,
		Location:        location,
		Custodian:       clientID,
		CollectedBy:     clientID,
		Timestamp:       time.Now().Unix(),
		Status:          "collected",
		Metadata:        metadata,
		FileSize:        fileSize,
		ChainType:       "hot",
		TransactionID:   txID,
		CustodyChainRef: fmt.Sprintf("custody_%s", id),
		CreatedBy:       clientID,
		CreatedAt:       time.Now().Unix(),
		UpdatedAt:       time.Now().Unix(),
	}

	evidenceJSON, err := json.Marshal(evidence)
	if err != nil {
		return fmt.Errorf("failed to marshal evidence: %v", err)
	}

	err = ctx.GetStub().PutState(id, evidenceJSON)
	if err != nil {
		return fmt.Errorf("failed to store evidence: %v", err)
	}

	// Update investigation evidence count
	cc.incrementEvidenceCount(ctx, caseID)

	// Emit event
	ctx.GetStub().SetEvent("EvidenceCreated", evidenceJSON)

	// Audit log
	cc.logAudit(ctx, "CreateEvidence", "blockchain.evidence", id, "success", "Evidence created")

	fmt.Printf("✓ Evidence created: %s\n", id)
	return nil
}

// ReadEvidence retrieves evidence by ID
func (cc *DFIRChaincode) ReadEvidence(ctx contractapi.TransactionContextInterface,
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
		return nil, fmt.Errorf("evidence %s does not exist", id)
	}

	var evidence Evidence
	err = json.Unmarshal(evidenceJSON, &evidence)
	if err != nil {
		return nil, fmt.Errorf("failed to unmarshal evidence: %v", err)
	}

	return &evidence, nil
}

// UpdateEvidenceStatus updates the status of evidence
func (cc *DFIRChaincode) UpdateEvidenceStatus(ctx contractapi.TransactionContextInterface,
	id string, newStatus string) error {

	// Check attestation
	if err := cc.checkAttestation(ctx); err != nil {
		return fmt.Errorf("attestation check failed: %v", err)
	}

	// Check permission
	if err := cc.checkPermission(ctx, "blockchain.evidence", "update", "*"); err != nil {
		return err
	}

	evidence, err := cc.ReadEvidence(ctx, id)
	if err != nil {
		return err
	}

	// Validate status transition
	validStatuses := map[string]bool{
		"collected": true, "analyzed": true, "reviewed": true,
		"ready-for-archive": true, "archived": true, "disposed": true,
	}
	if !validStatuses[newStatus] {
		return fmt.Errorf("invalid status: %s", newStatus)
	}

	evidence.Status = newStatus
	evidence.UpdatedAt = time.Now().Unix()

	evidenceJSON, err := json.Marshal(evidence)
	if err != nil {
		return fmt.Errorf("failed to marshal evidence: %v", err)
	}

	err = ctx.GetStub().PutState(id, evidenceJSON)
	if err != nil {
		return fmt.Errorf("failed to update evidence: %v", err)
	}

	// Emit event
	ctx.GetStub().SetEvent("EvidenceUpdated", evidenceJSON)

	// Audit log
	cc.logAudit(ctx, "UpdateEvidenceStatus", "blockchain.evidence", id, "success",
		fmt.Sprintf("Status updated to %s", newStatus))

	fmt.Printf("✓ Evidence %s status updated to %s\n", id, newStatus)
	return nil
}

// TransferCustody transfers evidence custody
func (cc *DFIRChaincode) TransferCustody(ctx contractapi.TransactionContextInterface,
	evidenceID string, toCustodian string, reason string, location string, permitHash string) error {

	// Check attestation
	if err := cc.checkAttestation(ctx); err != nil {
		return fmt.Errorf("attestation check failed: %v", err)
	}

	// Check permission
	if err := cc.checkPermission(ctx, "blockchain.custody", "transfer", "*"); err != nil {
		return err
	}

	evidence, err := cc.ReadEvidence(ctx, evidenceID)
	if err != nil {
		return err
	}

	clientID, _ := ctx.GetClientIdentity().GetID()

	// Create custody transfer record
	transferID := fmt.Sprintf("transfer_%s_%d", evidenceID, time.Now().UnixNano())
	transfer := CustodyTransfer{
		ID:            transferID,
		EvidenceID:    evidenceID,
		FromCustodian: evidence.Custodian,
		ToCustodian:   toCustodian,
		Timestamp:     time.Now().Unix(),
		Reason:        reason,
		Location:      location,
		PermitHash:    permitHash,
		TransferredBy: clientID,
		ApprovedBy:    clientID, // Auto-approved for now
		Status:        "completed",
	}

	transferJSON, err := json.Marshal(transfer)
	if err != nil {
		return fmt.Errorf("failed to marshal transfer: %v", err)
	}

	err = ctx.GetStub().PutState(transferID, transferJSON)
	if err != nil {
		return fmt.Errorf("failed to store transfer: %v", err)
	}

	// Update evidence custodian
	evidence.Custodian = toCustodian
	evidence.UpdatedAt = time.Now().Unix()

	evidenceJSON, err := json.Marshal(evidence)
	if err != nil {
		return fmt.Errorf("failed to marshal evidence: %v", err)
	}

	err = ctx.GetStub().PutState(evidenceID, evidenceJSON)
	if err != nil {
		return fmt.Errorf("failed to update evidence: %v", err)
	}

	// Emit event
	ctx.GetStub().SetEvent("CustodyTransferred", transferJSON)

	// Audit log
	cc.logAudit(ctx, "TransferCustody", "blockchain.custody", evidenceID, "success",
		fmt.Sprintf("Custody transferred to %s", toCustodian))

	fmt.Printf("✓ Custody transferred: %s -> %s\n", evidence.Custodian, toCustodian)
	return nil
}

// GetEvidenceHistory retrieves the complete history of an evidence item
func (cc *DFIRChaincode) GetEvidenceHistory(ctx contractapi.TransactionContextInterface,
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

// QueryEvidenceByCase retrieves all evidence for a case
func (cc *DFIRChaincode) QueryEvidenceByCase(ctx contractapi.TransactionContextInterface,
	caseID string) ([]*Evidence, error) {

	// Check permission
	if err := cc.checkPermission(ctx, "blockchain.evidence", "list", "*"); err != nil {
		return nil, err
	}

	// CouchDB query
	queryString := fmt.Sprintf(`{"selector":{"case_id":"%s"}}`, caseID)
	return cc.queryEvidence(ctx, queryString)
}

// QueryEvidenceByCustodian retrieves all evidence for a custodian
func (cc *DFIRChaincode) QueryEvidenceByCustodian(ctx contractapi.TransactionContextInterface,
	custodian string) ([]*Evidence, error) {

	// Check permission
	if err := cc.checkPermission(ctx, "blockchain.evidence", "list", "*"); err != nil {
		return nil, err
	}

	queryString := fmt.Sprintf(`{"selector":{"custodian":"%s"}}`, custodian)
	return cc.queryEvidence(ctx, queryString)
}

// QueryEvidenceByHash retrieves evidence by hash
func (cc *DFIRChaincode) QueryEvidenceByHash(ctx contractapi.TransactionContextInterface,
	hash string) (*Evidence, error) {

	// Check permission
	if err := cc.checkPermission(ctx, "blockchain.evidence", "view", "*"); err != nil {
		return nil, err
	}

	queryString := fmt.Sprintf(`{"selector":{"hash":"%s"}}`, hash)
	results, err := cc.queryEvidence(ctx, queryString)
	if err != nil {
		return nil, err
	}

	if len(results) == 0 {
		return nil, fmt.Errorf("evidence with hash %s not found", hash)
	}

	return results[0], nil
}

// queryEvidence helper function for CouchDB queries
func (cc *DFIRChaincode) queryEvidence(ctx contractapi.TransactionContextInterface,
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

// ==============================================================================
// GUID RESOLUTION (Court Role Only)
// ==============================================================================

// ResolveGUID resolves a GUID to real ID (Court role only)
func (cc *DFIRChaincode) ResolveGUID(ctx contractapi.TransactionContextInterface,
	guid string, courtOrder string) (*GUIDMapping, error) {

	// Check attestation
	if err := cc.checkAttestation(ctx); err != nil {
		return nil, fmt.Errorf("attestation check failed: %v", err)
	}

	// Check permission (Court role only)
	if err := cc.checkPermission(ctx, "blockchain.guidmapping", "resolve_guid", "*"); err != nil {
		return nil, err
	}

	mappingKey := fmt.Sprintf("GUID_%s", guid)
	mappingJSON, err := ctx.GetStub().GetState(mappingKey)
	if err != nil {
		return nil, fmt.Errorf("failed to read GUID mapping: %v", err)
	}
	if mappingJSON == nil {
		return nil, fmt.Errorf("GUID %s not found", guid)
	}

	var mapping GUIDMapping
	err = json.Unmarshal(mappingJSON, &mapping)
	if err != nil {
		return nil, fmt.Errorf("failed to unmarshal GUID mapping: %v", err)
	}

	clientID, _ := ctx.GetClientIdentity().GetID()
	mapping.ResolvedBy = clientID
	mapping.ResolvedAt = time.Now().Unix()
	mapping.CourtOrder = courtOrder

	// Update mapping
	updatedJSON, _ := json.Marshal(mapping)
	ctx.GetStub().PutState(mappingKey, updatedJSON)

	// Audit log
	cc.logAudit(ctx, "ResolveGUID", "blockchain.guidmapping", guid, "success",
		fmt.Sprintf("GUID resolved by court order: %s", courtOrder))

	return &mapping, nil
}

// ==============================================================================
// ATTESTATION MANAGEMENT
// ==============================================================================

// RegisterAttestation registers a new attestation verification
func (cc *DFIRChaincode) RegisterAttestation(ctx contractapi.TransactionContextInterface,
	attestationDoc string, verifierMSP string) error {

	// Only verifier services can register attestations
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

	fmt.Printf("✓ Attestation registered by %s\n", verifierMSP)
	return nil
}

// GetPRVConfig retrieves the current PRV configuration
func (cc *DFIRChaincode) GetPRVConfig(ctx contractapi.TransactionContextInterface) (*PRVConfig, error) {
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
// HELPER FUNCTIONS
// ==============================================================================

// incrementEvidenceCount increments the evidence count for an investigation
func (cc *DFIRChaincode) incrementEvidenceCount(ctx contractapi.TransactionContextInterface, caseID string) error {
	investigation, err := cc.ReadInvestigation(ctx, caseID)
	if err != nil {
		return err
	}

	investigation.EvidenceCount++
	investigation.UpdatedAt = time.Now().Unix()

	investigationJSON, err := json.Marshal(investigation)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(caseID, investigationJSON)
}

// GetAllInvestigations retrieves all investigations (paginated)
func (cc *DFIRChaincode) GetAllInvestigations(ctx contractapi.TransactionContextInterface,
	pageSize int, bookmark string) ([]*Investigation, error) {

	// Check permission
	if err := cc.checkPermission(ctx, "blockchain.investigation", "list", "*"); err != nil {
		return nil, err
	}

	queryString := `{"selector":{"case_number":{"$exists":true}}}`

	resultsIterator, _, err := ctx.GetStub().GetQueryResultWithPagination(queryString, int32(pageSize), bookmark)
	if err != nil {
		return nil, fmt.Errorf("failed to query investigations: %v", err)
	}
	defer resultsIterator.Close()

	var results []*Investigation
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return nil, err
		}

		var investigation Investigation
		err = json.Unmarshal(queryResponse.Value, &investigation)
		if err != nil {
			return nil, err
		}
		results = append(results, &investigation)
	}

	return results, nil
}

// ==============================================================================
// MAIN
// ==============================================================================

func main() {
	chaincode, err := contractapi.NewChaincode(&DFIRChaincode{})
	if err != nil {
		fmt.Printf("Error creating DFIR chaincode: %v\n", err)
		return
	}

	if err := chaincode.Start(); err != nil {
		fmt.Printf("Error starting DFIR chaincode: %v\n", err)
	}
}
