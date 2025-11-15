package main

import (
	"encoding/json"
	"testing"
	"time"
)

// Test ArchiveMetadata structure
func TestArchiveMetadataMarshaling(t *testing.T) {
	metadata := ArchiveMetadata{
		EvidenceID:         "EV001",
		OriginalChain:      "hot",
		OriginalTxID:       "tx123",
		ArchivalVerifiedBy: "user1",
		ArchivalTimestamp:  time.Now().Unix(),
		IntegrityHash:      "hash456",
	}

	data, err := json.Marshal(metadata)
	if err != nil {
		t.Fatalf("Failed to marshal ArchiveMetadata: %v", err)
	}

	var decoded ArchiveMetadata
	err = json.Unmarshal(data, &decoded)
	if err != nil {
		t.Fatalf("Failed to unmarshal ArchiveMetadata: %v", err)
	}

	if decoded.OriginalChain != "hot" {
		t.Errorf("OriginalChain mismatch: got %s, want hot", decoded.OriginalChain)
	}

	if decoded.IntegrityHash != "hash456" {
		t.Errorf("IntegrityHash mismatch: got %s, want hash456", decoded.IntegrityHash)
	}
}

// Test Evidence structure with cold chain fields
func TestColdEvidenceMarshaling(t *testing.T) {
	ev := Evidence{
		ID:              "EV001",
		CaseID:          "INV001",
		Type:            "digital",
		Description:     "Archived evidence",
		Hash:            "abc123",
		IPFSHash:        "Qm...ipfs",
		Location:        "/archive",
		Custodian:       "archive_user",
		CollectedBy:     "investigator",
		Timestamp:       time.Now().Unix(),
		Status:          "archived",
		Metadata:        "{}",
		FileSize:        1048576,
		ChainType:       "cold",
		TransactionID:   "cold_tx_123",
		CustodyChainRef: "custody_EV001",
		CreatedBy:       "user1",
		ArchivedBy:      "archive_admin",
		CreatedAt:       time.Now().Unix(),
		ArchivedAt:      time.Now().Unix(),
		SourceChain:     "hot",
		SourceTxID:      "hot_tx_456",
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

	if decoded.ChainType != "cold" {
		t.Errorf("ChainType mismatch: got %s, want cold", decoded.ChainType)
	}

	if decoded.Status != "archived" {
		t.Errorf("Status mismatch: got %s, want archived", decoded.Status)
	}

	if decoded.SourceChain != "hot" {
		t.Errorf("SourceChain mismatch: got %s, want hot", decoded.SourceChain)
	}
}

// Test Investigation with archive fields
func TestColdInvestigationMarshaling(t *testing.T) {
	inv := Investigation{
		ID:               "INV001",
		CaseNumber:       "CASE-2024-001",
		CaseName:         "Archived Case",
		InvestigatingOrg: "LawEnforcement",
		LeadInvestigator: "Officer Smith",
		Status:           "archived",
		OpenedDate:       time.Now().Unix(),
		ClosedDate:       time.Now().Unix(),
		ArchivedDate:     time.Now().Unix(),
		Description:      "Archived investigation",
		EvidenceCount:    10,
		CreatedBy:        "user1",
		ArchivedBy:       "archive_admin",
		CreatedAt:        time.Now().Unix(),
		ArchivedAt:       time.Now().Unix(),
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

	if decoded.Status != "archived" {
		t.Errorf("Status mismatch: got %s, want archived", decoded.Status)
	}

	if decoded.ArchivedDate == 0 {
		t.Error("ArchivedDate should not be zero")
	}
}

// Test getRoleFromMSP for cold chain
func TestColdGetRoleFromMSP(t *testing.T) {
	cc := &DFIRColdChaincode{}

	tests := []struct {
		mspID    string
		expected string
	}{
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

// Test evaluatePermission for cold chain (more restrictive)
func TestColdEvaluatePermissionInvestigator(t *testing.T) {
	cc := &DFIRColdChaincode{}

	tests := []struct {
		object   string
		action   string
		expected bool
	}{
		{"blockchain.investigation", "view", true},
		{"blockchain.evidence", "view", true},
		{"blockchain.evidence", "archive", true},
		{"blockchain.custody", "view", true},
		{"blockchain.investigation", "create", false}, // No creation in cold chain
		{"blockchain.evidence", "update", false},      // No updates in cold chain
		{"blockchain.custody", "transfer", false},     // No transfers in cold chain
	}

	for _, tt := range tests {
		result := cc.evaluatePermission("BlockchainInvestigator", tt.object, tt.action, "*", "user1")
		if result != tt.expected {
			t.Errorf("evaluatePermission(Investigator, %s, %s) = %v, want %v",
				tt.object, tt.action, result, tt.expected)
		}
	}
}

// Test evaluatePermission for BlockchainAuditor on cold chain
func TestColdEvaluatePermissionAuditor(t *testing.T) {
	cc := &DFIRColdChaincode{}

	tests := []struct {
		object   string
		action   string
		expected bool
	}{
		{"blockchain.investigation", "view", true},
		{"blockchain.evidence", "view", true},
		{"blockchain.evidence", "history", true},
		{"blockchain.evidence", "archive", true},
		{"audits.userloginlog", "view", true}, // Wildcard match
		{"blockchain.evidence", "create", false},
		{"blockchain.evidence", "update", false},
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

// Test evaluatePermission for BlockchainCourt on cold chain (read-only)
func TestColdEvaluatePermissionCourt(t *testing.T) {
	cc := &DFIRColdChaincode{}

	tests := []struct {
		object   string
		action   string
		expected bool
	}{
		{"blockchain.investigation", "view", true},
		{"blockchain.evidence", "view", true},
		{"blockchain.evidence", "history", true},
		{"blockchain.custody", "view", true},
		{"blockchain.investigation", "archive", false}, // No archiving in cold (already archived)
		{"blockchain.investigation", "reopen", false},  // No reopening from cold
		{"blockchain.custody", "transfer", false},      // No transfers
	}

	for _, tt := range tests {
		result := cc.evaluatePermission("BlockchainCourt", tt.object, tt.action, "*", "user1")
		if result != tt.expected {
			t.Errorf("evaluatePermission(Court, %s, %s) = %v, want %v",
				tt.object, tt.action, result, tt.expected)
		}
	}
}

// Test SystemAdmin has full access on cold chain
func TestColdEvaluatePermissionSystemAdmin(t *testing.T) {
	cc := &DFIRColdChaincode{}

	tests := []struct {
		object string
		action string
	}{
		{"blockchain.investigation", "view"},
		{"blockchain.evidence", "archive"},
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
func TestColdChaincodeInstantiation(t *testing.T) {
	cc := &DFIRColdChaincode{}
	if cc == nil {
		t.Error("Failed to create DFIRColdChaincode instance")
	}
}

// Test PRVConfig compatibility between hot and cold
func TestPRVConfigCompatibility(t *testing.T) {
	config := PRVConfig{
		PublicKey:      "test_key",
		MREnclave:      "test_enclave",
		MRSigner:       "test_signer",
		UpdatedAt:      time.Now().Unix(),
		AttestationDoc: "test_doc",
		VerifiedBy:     []string{"org1", "org2", "org3"},
		TCBLevel:       "1",
		ExpiresAt:      time.Now().Add(24 * time.Hour).Unix(),
	}

	// Should work with both hot and cold chaincode
	data, err := json.Marshal(config)
	if err != nil {
		t.Fatalf("Failed to marshal PRVConfig: %v", err)
	}

	var decoded PRVConfig
	err = json.Unmarshal(data, &decoded)
	if err != nil {
		t.Fatalf("Failed to unmarshal PRVConfig: %v", err)
	}

	if len(decoded.VerifiedBy) != 3 {
		t.Errorf("VerifiedBy length mismatch: got %d, want 3", len(decoded.VerifiedBy))
	}
}

// Benchmark permission evaluation on cold chain
func BenchmarkColdEvaluatePermission(b *testing.B) {
	cc := &DFIRColdChaincode{}
	for i := 0; i < b.N; i++ {
		cc.evaluatePermission("BlockchainAuditor", "blockchain.evidence", "view", "*", "user1")
	}
}
