package main

import (
	"encoding/json"
	"testing"
	"time"
)

// Test PRVConfig structure
func TestPRVConfigMarshaling(t *testing.T) {
	config := PRVConfig{
		PublicKey:      "test_pubkey",
		MREnclave:      "test_mrenclave",
		MRSigner:       "test_mrsigner",
		UpdatedAt:      time.Now().Unix(),
		AttestationDoc: "test_doc",
		VerifiedBy:     []string{"org1", "org2"},
		TCBLevel:       "1",
		ExpiresAt:      time.Now().Add(24 * time.Hour).Unix(),
	}

	// Marshal and unmarshal
	data, err := json.Marshal(config)
	if err != nil {
		t.Fatalf("Failed to marshal PRVConfig: %v", err)
	}

	var decoded PRVConfig
	err = json.Unmarshal(data, &decoded)
	if err != nil {
		t.Fatalf("Failed to unmarshal PRVConfig: %v", err)
	}

	if decoded.PublicKey != config.PublicKey {
		t.Errorf("PublicKey mismatch: got %s, want %s", decoded.PublicKey, config.PublicKey)
	}

	if len(decoded.VerifiedBy) != 2 {
		t.Errorf("VerifiedBy length mismatch: got %d, want 2", len(decoded.VerifiedBy))
	}
}

// Test Investigation structure
func TestInvestigationMarshaling(t *testing.T) {
	inv := Investigation{
		ID:               "INV001",
		CaseNumber:       "CASE-2024-001",
		CaseName:         "Test Case",
		InvestigatingOrg: "LawEnforcement",
		LeadInvestigator: "Officer Smith",
		Status:           "open",
		OpenedDate:       time.Now().Unix(),
		Description:      "Test investigation",
		EvidenceCount:    5,
		CreatedBy:        "user1",
		CreatedAt:        time.Now().Unix(),
		UpdatedAt:        time.Now().Unix(),
	}

	data, err := json.Marshal(inv)
	if err != nil {
		t.Fatalf("Failed to marshal Investigation: %v", err)
	}

	var decoded Investigation
	err = json.Unmarshal(data, &decoded)
	if err != nil {
		t.Fatalf("Failed to unmarshal Investigation: %v", err)
	}

	if decoded.CaseNumber != inv.CaseNumber {
		t.Errorf("CaseNumber mismatch: got %s, want %s", decoded.CaseNumber, inv.CaseNumber)
	}

	if decoded.EvidenceCount != 5 {
		t.Errorf("EvidenceCount mismatch: got %d, want 5", decoded.EvidenceCount)
	}
}

// Test Evidence structure
func TestEvidenceMarshaling(t *testing.T) {
	ev := Evidence{
		ID:              "EV001",
		CaseID:          "INV001",
		Type:            "digital",
		Description:     "Hard drive image",
		Hash:            "abc123hash",
		IPFSHash:        "Qm...ipfshash",
		Location:        "/evidence/storage",
		Custodian:       "user1",
		CollectedBy:     "user1",
		Timestamp:       time.Now().Unix(),
		Status:          "collected",
		Metadata:        "{}",
		FileSize:        1048576,
		ChainType:       "hot",
		TransactionID:   "tx123",
		CustodyChainRef: "custody_EV001",
		CreatedBy:       "user1",
		CreatedAt:       time.Now().Unix(),
		UpdatedAt:       time.Now().Unix(),
	}

	data, err := json.Marshal(ev)
	if err != nil {
		t.Fatalf("Failed to marshal Evidence: %v", err)
	}

	var decoded Evidence
	err = json.Unmarshal(data, &decoded)
	if err != nil {
		t.Fatalf("Failed to unmarshal Evidence: %v", err)
	}

	if decoded.Hash != ev.Hash {
		t.Errorf("Hash mismatch: got %s, want %s", decoded.Hash, ev.Hash)
	}

	if decoded.FileSize != 1048576 {
		t.Errorf("FileSize mismatch: got %d, want 1048576", decoded.FileSize)
	}

	if decoded.ChainType != "hot" {
		t.Errorf("ChainType mismatch: got %s, want hot", decoded.ChainType)
	}
}

// Test CustodyTransfer structure
func TestCustodyTransferMarshaling(t *testing.T) {
	transfer := CustodyTransfer{
		ID:            "transfer_001",
		EvidenceID:    "EV001",
		FromCustodian: "user1",
		ToCustodian:   "user2",
		Timestamp:     time.Now().Unix(),
		Reason:        "Chain of custody",
		Location:      "Lab Room 5",
		PermitHash:    "permit123",
		TransferredBy: "user1",
		ApprovedBy:    "supervisor",
		Status:        "completed",
	}

	data, err := json.Marshal(transfer)
	if err != nil {
		t.Fatalf("Failed to marshal CustodyTransfer: %v", err)
	}

	var decoded CustodyTransfer
	err = json.Unmarshal(data, &decoded)
	if err != nil {
		t.Fatalf("Failed to unmarshal CustodyTransfer: %v", err)
	}

	if decoded.FromCustodian != transfer.FromCustodian {
		t.Errorf("FromCustodian mismatch: got %s, want %s", decoded.FromCustodian, transfer.FromCustodian)
	}

	if decoded.Status != "completed" {
		t.Errorf("Status mismatch: got %s, want completed", decoded.Status)
	}
}

// Test AuditLog structure
func TestAuditLogMarshaling(t *testing.T) {
	log := AuditLog{
		ID:            "audit_001",
		UserID:        "user1",
		Action:        "CreateEvidence",
		Resource:      "blockchain.evidence",
		ResourceID:    "EV001",
		Result:        "success",
		Reason:        "Evidence created",
		Timestamp:     time.Now().Unix(),
		ClientMSP:     "LawEnforcementMSP",
		TransactionID: "tx123",
	}

	data, err := json.Marshal(log)
	if err != nil {
		t.Fatalf("Failed to marshal AuditLog: %v", err)
	}

	var decoded AuditLog
	err = json.Unmarshal(data, &decoded)
	if err != nil {
		t.Fatalf("Failed to unmarshal AuditLog: %v", err)
	}

	if decoded.Action != log.Action {
		t.Errorf("Action mismatch: got %s, want %s", decoded.Action, log.Action)
	}

	if decoded.Result != "success" {
		t.Errorf("Result mismatch: got %s, want success", decoded.Result)
	}
}

// Test GUIDMapping structure
func TestGUIDMappingMarshaling(t *testing.T) {
	mapping := GUIDMapping{
		GUID:         "guid_123",
		RealID:       "real_user_id",
		ResourceType: "evidence",
		ResolvedBy:   "court_official",
		ResolvedAt:   time.Now().Unix(),
		CourtOrder:   "CO-2024-001",
	}

	data, err := json.Marshal(mapping)
	if err != nil {
		t.Fatalf("Failed to marshal GUIDMapping: %v", err)
	}

	var decoded GUIDMapping
	err = json.Unmarshal(data, &decoded)
	if err != nil {
		t.Fatalf("Failed to unmarshal GUIDMapping: %v", err)
	}

	if decoded.GUID != mapping.GUID {
		t.Errorf("GUID mismatch: got %s, want %s", decoded.GUID, mapping.GUID)
	}

	if decoded.CourtOrder != "CO-2024-001" {
		t.Errorf("CourtOrder mismatch: got %s, want CO-2024-001", decoded.CourtOrder)
	}
}

// Test getRoleFromMSP logic
func TestGetRoleFromMSP(t *testing.T) {
	cc := &DFIRChaincode{}

	tests := []struct {
		mspID    string
		expected string
	}{
		{"LawEnforcementMSP", "BlockchainInvestigator"},
		{"ForensicLabMSP", "BlockchainInvestigator"},
		{"ArchiveMSP", "BlockchainAuditor"},
		{"UnknownMSP", "User"},
	}

	for _, tt := range tests {
		result := cc.getRoleFromMSP(tt.mspID)
		if result != tt.expected {
			t.Errorf("getRoleFromMSP(%s) = %s, want %s", tt.mspID, result, tt.expected)
		}
	}
}

// Test evaluatePermission logic for BlockchainInvestigator
func TestEvaluatePermissionInvestigator(t *testing.T) {
	cc := &DFIRChaincode{}

	tests := []struct {
		object   string
		action   string
		expected bool
	}{
		{"blockchain.investigation", "create", true},
		{"blockchain.investigation", "view", true},
		{"blockchain.evidence", "create", true},
		{"blockchain.evidence", "update", true},
		{"blockchain.custody", "transfer", true},
		{"blockchain.guidmapping", "resolve_guid", false}, // Investigator cannot resolve GUID
		{"blockchain.evidence", "delete", false},          // Not in permission list
	}

	for _, tt := range tests {
		result := cc.evaluatePermission("BlockchainInvestigator", tt.object, tt.action, "*", "user1")
		if result != tt.expected {
			t.Errorf("evaluatePermission(Investigator, %s, %s) = %v, want %v",
				tt.object, tt.action, result, tt.expected)
		}
	}
}

// Test evaluatePermission logic for BlockchainAuditor
func TestEvaluatePermissionAuditor(t *testing.T) {
	cc := &DFIRChaincode{}

	tests := []struct {
		object   string
		action   string
		expected bool
	}{
		{"blockchain.investigation", "view", true},
		{"blockchain.evidence", "view", true},
		{"blockchain.evidence", "history", true},
		{"audits.userloginlog", "view", true}, // Wildcard match
		{"audits.operatelog", "view", true},   // Wildcard match
		{"blockchain.evidence", "create", false},
		{"blockchain.custody", "transfer", false},
	}

	for _, tt := range tests {
		result := cc.evaluatePermission("BlockchainAuditor", tt.object, tt.action, "*", "user1")
		if result != tt.expected {
			t.Errorf("evaluatePermission(Auditor, %s, %s) = %v, want %v",
				tt.object, tt.action, result, tt.expected)
		}
	}
}

// Test evaluatePermission logic for BlockchainCourt
func TestEvaluatePermissionCourt(t *testing.T) {
	cc := &DFIRChaincode{}

	tests := []struct {
		object   string
		action   string
		expected bool
	}{
		{"blockchain.investigation", "archive", true},
		{"blockchain.investigation", "reopen", true},
		{"blockchain.guidmapping", "resolve_guid", true}, // ONLY Court can do this
		{"blockchain.evidence", "view", true},
		{"blockchain.evidence", "create", false},
		{"blockchain.custody", "transfer", false},
	}

	for _, tt := range tests {
		result := cc.evaluatePermission("BlockchainCourt", tt.object, tt.action, "*", "user1")
		if result != tt.expected {
			t.Errorf("evaluatePermission(Court, %s, %s) = %v, want %v",
				tt.object, tt.action, result, tt.expected)
		}
	}
}

// Test SystemAdmin has full access
func TestEvaluatePermissionSystemAdmin(t *testing.T) {
	cc := &DFIRChaincode{}

	// SystemAdmin should have access to everything
	tests := []struct {
		object string
		action string
	}{
		{"blockchain.investigation", "create"},
		{"blockchain.evidence", "delete"},
		{"blockchain.guidmapping", "resolve_guid"},
		{"anything", "anything"},
	}

	for _, tt := range tests {
		result := cc.evaluatePermission("SystemAdmin", tt.object, tt.action, "*", "admin")
		if !result {
			t.Errorf("evaluatePermission(SystemAdmin, %s, %s) = false, want true",
				tt.object, tt.action)
		}
	}
}

// Test chaincode instantiation
func TestChaincodeInstantiation(t *testing.T) {
	cc := &DFIRChaincode{}
	if cc == nil {
		t.Error("Failed to create DFIRChaincode instance")
	}
}

// Benchmark permission evaluation
func BenchmarkEvaluatePermission(b *testing.B) {
	cc := &DFIRChaincode{}
	for i := 0; i < b.N; i++ {
		cc.evaluatePermission("BlockchainInvestigator", "blockchain.evidence", "create", "*", "user1")
	}
}
