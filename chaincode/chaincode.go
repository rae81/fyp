package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math/big"
	"strings"
	"time"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// DFIRChaincode - Public chaincode for evidence management
type DFIRChaincode struct {
	contractapi.Contract
}

// PRVConfig stores PRV verification keys and measurements
type PRVConfig struct {
	PublicKey  string `json:"public_key"`  // Hex-encoded ECDSA public key
	MREnclave  string `json:"mr_enclave"`  // Hex-encoded enclave measurement
	MRSigner   string `json:"mr_signer"`   // Hex-encoded signer measurement
	UpdatedAt  int64  `json:"updated_at"`
}

// Evidence represents a piece of digital evidence
type Evidence struct {
	ID          string `json:"id"`
	CaseID      string `json:"case_id"`
	Type        string `json:"type"`
	Description string `json:"description"`
	Hash        string `json:"hash"`
	Location    string `json:"location"`
	Custodian   string `json:"custodian"`
	Timestamp   int64  `json:"timestamp"`
	Status      string `json:"status"`
	Metadata    string `json:"metadata"`
}

// CustodyTransfer records custody chain
type CustodyTransfer struct {
	EvidenceID    string `json:"evidence_id"`
	FromCustodian string `json:"from_custodian"`
	ToCustodian   string `json:"to_custodian"`
	Timestamp     int64  `json:"timestamp"`
	Reason        string `json:"reason"`
	Location      string `json:"location"`
	PermitHash    string `json:"permit_hash"`
}

// JWSPermit from PRV service
type JWSPermit struct {
	Header    string `json:"header"`
	Payload   string `json:"payload"`
	Signature string `json:"signature"` // Hex-encoded
}

// PermitPayload decoded from JWS
type PermitPayload struct {
	Sub       string `json:"sub"`
	Action    string `json:"action"`
	Resource  string `json:"resource"`
	Clearance int    `json:"clearance"`
	Decision  string `json:"decision"`
	Timestamp int64  `json:"timestamp"`
	Nonce     string `json:"nonce"`
	MREnclave string `json:"mrenclave"`
}

// InitLedger initializes the ledger with PRV configuration
func (cc *DFIRChaincode) InitLedger(ctx contractapi.TransactionContextInterface,
	publicKeyHex string, mrenclaveHex string, mrsignerHex string) error {

	config := PRVConfig{
		PublicKey: publicKeyHex,
		MREnclave: mrenclaveHex,
		MRSigner:  mrsignerHex,
		UpdatedAt: time.Now().Unix(),
	}

	configJSON, err := json.Marshal(config)
	if err != nil {
		return fmt.Errorf("failed to marshal config: %v", err)
	}

	err = ctx.GetStub().PutState("PRV_CONFIG", configJSON)
	if err != nil {
		return fmt.Errorf("failed to store config: %v", err)
	}

	fmt.Printf("✓ Ledger initialized with PRV config\n")
	fmt.Printf("  MRENCLAVE: %s\n", mrenclaveHex[:16])
	fmt.Printf("  Public Key: %s\n", publicKeyHex[:32])

	return nil
}

// UpdatePRVConfig updates PRV configuration (admin only)
func (cc *DFIRChaincode) UpdatePRVConfig(ctx contractapi.TransactionContextInterface,
	publicKeyHex string, mrenclaveHex string, mrsignerHex string) error {

	// In production, check if caller is admin via MSP attributes
	clientID, _ := ctx.GetClientIdentity().GetID()

	config := PRVConfig{
		PublicKey: publicKeyHex,
		MREnclave: mrenclaveHex,
		MRSigner:  mrsignerHex,
		UpdatedAt: time.Now().Unix(),
	}

	configJSON, err := json.Marshal(config)
	if err != nil {
		return fmt.Errorf("failed to marshal config: %v", err)
	}

	err = ctx.GetStub().PutState("PRV_CONFIG", configJSON)
	if err != nil {
		return fmt.Errorf("failed to update config: %v", err)
	}

	// Emit event
	ctx.GetStub().SetEvent("PRVConfigUpdated", configJSON)

	fmt.Printf("✓ PRV config updated by %s\n", clientID)
	return nil
}

// VerifyPRVPermit verifies JWS signature and attestation from PRV
func (cc *DFIRChaincode) VerifyPRVPermit(ctx contractapi.TransactionContextInterface,
	permitJSON string, expectedSubject string, expectedAction string,
	expectedResource string, nonce string) (bool, error) {

	// Load PRV config
	configJSON, err := ctx.GetStub().GetState("PRV_CONFIG")
	if err != nil {
		return false, fmt.Errorf("failed to read config: %v", err)
	}
	if configJSON == nil {
		return false, fmt.Errorf("PRV config not initialized - call InitLedger first")
	}

	var config PRVConfig
	err = json.Unmarshal(configJSON, &config)
	if err != nil {
		return false, fmt.Errorf("failed to unmarshal config: %v", err)
	}

	// Parse permit
	var permit JWSPermit
	err = json.Unmarshal([]byte(permitJSON), &permit)
	if err != nil {
		return false, fmt.Errorf("failed to unmarshal permit: %v", err)
	}

	// Decode payload
	payloadBytes, err := base64.RawURLEncoding.DecodeString(permit.Payload)
	if err != nil {
		return false, fmt.Errorf("failed to decode payload: %v", err)
	}

	var payload PermitPayload
	err = json.Unmarshal(payloadBytes, &payload)
	if err != nil {
		return false, fmt.Errorf("failed to unmarshal payload: %v", err)
	}

	// Verify payload matches expected transaction
	if payload.Sub != expectedSubject {
		return false, fmt.Errorf("subject mismatch: expected %s, got %s",
			expectedSubject, payload.Sub)
	}
	if payload.Action != expectedAction {
		return false, fmt.Errorf("action mismatch: expected %s, got %s",
			expectedAction, payload.Action)
	}
	if payload.Resource != expectedResource {
		return false, fmt.Errorf("resource mismatch: expected %s, got %s",
			expectedResource, payload.Resource)
	}
	if payload.Nonce != nonce {
		return false, fmt.Errorf("nonce mismatch: replay attack detected")
	}

	// Check timestamp freshness (within 5 minutes)
	now := time.Now().Unix()
	if now > payload.Timestamp+300 || now < payload.Timestamp-300 {
		return false, fmt.Errorf("permit expired (timestamp: %d, now: %d)",
			payload.Timestamp, now)
	}

	// Verify decision is "allow"
	if payload.Decision != "allow" {
		return false, fmt.Errorf("permit decision is deny")
	}

	// Verify MRENCLAVE matches trusted enclave
	if !strings.HasPrefix(config.MREnclave, payload.MREnclave) {
		return false, fmt.Errorf("mrenclave mismatch: untrusted PRV enclave")
	}

	// Verify ECDSA signature
	signData := permit.Header + "." + permit.Payload
	hash := sha256.Sum256([]byte(signData))

	// Decode public key from hex
	pubKeyBytes, err := hex.DecodeString(config.PublicKey)
	if err != nil {
		return false, fmt.Errorf("failed to decode public key: %v", err)
	}

	// Parse uncompressed public key (0x04 + X + Y)
	x, y := elliptic.Unmarshal(elliptic.P256(), pubKeyBytes)
	if x == nil {
		return false, fmt.Errorf("invalid public key format")
	}

	pubKey := &ecdsa.PublicKey{
		Curve: elliptic.P256(),
		X:     x,
		Y:     y,
	}

	// Decode signature from hex
	sigBytes, err := hex.DecodeString(permit.Signature)
	if err != nil {
		return false, fmt.Errorf("failed to decode signature: %v", err)
	}

	if len(sigBytes) != 64 {
		return false, fmt.Errorf("invalid signature length: %d", len(sigBytes))
	}

	// Extract R and S
	r := new(big.Int).SetBytes(sigBytes[:32])
	s := new(big.Int).SetBytes(sigBytes[32:])

	// Verify ECDSA signature
	valid := ecdsa.Verify(pubKey, hash[:], r, s)
	if !valid {
		return false, fmt.Errorf("invalid PRV signature")
	}

	fmt.Printf("✓ PRV permit verified: subject=%s action=%s resource=%s\n",
		expectedSubject, expectedAction, expectedResource)

	return true, nil
}

// CreateEvidence creates new evidence entry
func (cc *DFIRChaincode) CreateEvidence(ctx contractapi.TransactionContextInterface,
	id string, caseID string, evidenceType string, description string,
	hash string, location string, metadata string,
	permitJSON string, nonce string) error {

	// Get caller identity
	clientID, err := ctx.GetClientIdentity().GetID()
	if err != nil {
		return fmt.Errorf("failed to get client identity: %v", err)
	}

	// Verify PRV permit
	resource := fmt.Sprintf("evidence/%s", id)
	valid, err := cc.VerifyPRVPermit(ctx, permitJSON, clientID, "create", resource, nonce)
	if err != nil || !valid {
		return fmt.Errorf("PRV permit verification failed: %v", err)
	}

	// Check if evidence already exists
	existing, err := ctx.GetStub().GetState(id)
	if err != nil {
		return fmt.Errorf("failed to read evidence: %v", err)
	}
	if existing != nil {
		return fmt.Errorf("evidence %s already exists", id)
	}

	// Create evidence
	evidence := Evidence{
		ID:          id,
		CaseID:      caseID,
		Type:        evidenceType,
		Description: description,
		Hash:        hash,
		Location:    location,
		Custodian:   clientID,
		Timestamp:   time.Now().Unix(),
		Status:      "collected",
		Metadata:    metadata,
	}

	evidenceJSON, err := json.Marshal(evidence)
	if err != nil {
		return fmt.Errorf("failed to marshal evidence: %v", err)
	}

	err = ctx.GetStub().PutState(id, evidenceJSON)
	if err != nil {
		return fmt.Errorf("failed to store evidence: %v", err)
	}

	// Emit event
	ctx.GetStub().SetEvent("EvidenceCreated", evidenceJSON)

	fmt.Printf("✓ Evidence created: %s by %s\n", id, clientID)
	return nil
}

// TransferCustody transfers evidence custody
func (cc *DFIRChaincode) TransferCustody(ctx contractapi.TransactionContextInterface,
	evidenceID string, toCustodian string, reason string, newLocation string,
	permitJSON string, nonce string) error {

	// Get caller identity
	clientID, err := ctx.GetClientIdentity().GetID()
	if err != nil {
		return fmt.Errorf("failed to get client identity: %v", err)
	}

	// Verify PRV permit
	resource := fmt.Sprintf("evidence/%s", evidenceID)
	valid, err := cc.VerifyPRVPermit(ctx, permitJSON, clientID, "transfer", resource, nonce)
	if err != nil || !valid {
		return fmt.Errorf("PRV permit verification failed: %v", err)
	}

	// Get evidence
	evidenceJSON, err := ctx.GetStub().GetState(evidenceID)
	if err != nil {
		return fmt.Errorf("failed to read evidence: %v", err)
	}
	if evidenceJSON == nil {
		return fmt.Errorf("evidence %s does not exist", evidenceID)
	}

	var evidence Evidence
	err = json.Unmarshal(evidenceJSON, &evidence)
	if err != nil {
		return fmt.Errorf("failed to unmarshal evidence: %v", err)
	}

	// Verify current custodian
	if evidence.Custodian != clientID {
		return fmt.Errorf("caller %s is not current custodian %s",
			clientID, evidence.Custodian)
	}

	// Create custody transfer record
	transfer := CustodyTransfer{
		EvidenceID:    evidenceID,
		FromCustodian: clientID,
		ToCustodian:   toCustodian,
		Timestamp:     time.Now().Unix(),
		Reason:        reason,
		Location:      newLocation,
		PermitHash:    hashString(permitJSON),
	}

	transferJSON, err := json.Marshal(transfer)
	if err != nil {
		return fmt.Errorf("failed to marshal transfer: %v", err)
	}

	// Store transfer record
	transferKey := fmt.Sprintf("TRANSFER_%s_%d", evidenceID, time.Now().Unix())
	err = ctx.GetStub().PutState(transferKey, transferJSON)
	if err != nil {
		return fmt.Errorf("failed to store transfer: %v", err)
	}

	// Update evidence
	evidence.Custodian = toCustodian
	evidence.Location = newLocation
	evidence.Timestamp = time.Now().Unix()

	evidenceJSON, err = json.Marshal(evidence)
	if err != nil {
		return fmt.Errorf("failed to marshal evidence: %v", err)
	}

	err = ctx.GetStub().PutState(evidenceID, evidenceJSON)
	if err != nil {
		return fmt.Errorf("failed to update evidence: %v", err)
	}

	// Emit event
	ctx.GetStub().SetEvent("CustodyTransferred", transferJSON)

	fmt.Printf("✓ Custody transferred: %s from %s to %s\n",
		evidenceID, clientID, toCustodian)
	return nil
}

// ReadEvidence reads evidence with permit verification
func (cc *DFIRChaincode) ReadEvidence(ctx contractapi.TransactionContextInterface,
	id string, permitJSON string, nonce string) (*Evidence, error) {

	// Get caller identity
	clientID, err := ctx.GetClientIdentity().GetID()
	if err != nil {
		return nil, fmt.Errorf("failed to get client identity: %v", err)
	}

	// Verify PRV permit
	resource := fmt.Sprintf("evidence/%s", id)
	valid, err := cc.VerifyPRVPermit(ctx, permitJSON, clientID, "read", resource, nonce)
	if err != nil || !valid {
		return nil, fmt.Errorf("PRV permit verification failed: %v", err)
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

// UpdateEvidenceStatus updates evidence status
func (cc *DFIRChaincode) UpdateEvidenceStatus(ctx contractapi.TransactionContextInterface,
	id string, status string, permitJSON string, nonce string) error {

	// Get caller identity
	clientID, err := ctx.GetClientIdentity().GetID()
	if err != nil {
		return fmt.Errorf("failed to get client identity: %v", err)
	}

	// Verify PRV permit
	resource := fmt.Sprintf("evidence/%s", id)
	valid, err := cc.VerifyPRVPermit(ctx, permitJSON, clientID, "update", resource, nonce)
	if err != nil || !valid {
		return fmt.Errorf("PRV permit verification failed: %v", err)
	}

	evidenceJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return fmt.Errorf("failed to read evidence: %v", err)
	}
	if evidenceJSON == nil {
		return fmt.Errorf("evidence %s does not exist", id)
	}

	var evidence Evidence
	err = json.Unmarshal(evidenceJSON, &evidence)
	if err != nil {
		return fmt.Errorf("failed to unmarshal evidence: %v", err)
	}

	// Update status
	evidence.Status = status
	evidence.Timestamp = time.Now().Unix()

	evidenceJSON, err = json.Marshal(evidence)
	if err != nil {
		return fmt.Errorf("failed to marshal evidence: %v", err)
	}

	err = ctx.GetStub().PutState(id, evidenceJSON)
	if err != nil {
		return fmt.Errorf("failed to update evidence: %v", err)
	}

	// Emit event
	ctx.GetStub().SetEvent("EvidenceUpdated", evidenceJSON)

	fmt.Printf("✓ Evidence status updated: %s to %s by %s\n", id, status, clientID)
	return nil
}

// GetCustodyHistory queries custody transfer history
func (cc *DFIRChaincode) GetCustodyHistory(ctx contractapi.TransactionContextInterface,
	evidenceID string) ([]*CustodyTransfer, error) {

	// Query using key prefix
	resultsIterator, err := ctx.GetStub().GetStateByRange(
		fmt.Sprintf("TRANSFER_%s_", evidenceID),
		fmt.Sprintf("TRANSFER_%s_~", evidenceID),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to query transfers: %v", err)
	}
	defer resultsIterator.Close()

	var transfers []*CustodyTransfer
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return nil, fmt.Errorf("failed to iterate: %v", err)
		}

		var transfer CustodyTransfer
		err = json.Unmarshal(queryResponse.Value, &transfer)
		if err != nil {
			return nil, fmt.Errorf("failed to unmarshal transfer: %v", err)
		}

		transfers = append(transfers, &transfer)
	}

	return transfers, nil
}

// Helper: hash string to hex
func hashString(s string) string {
	hash := sha256.Sum256([]byte(s))
	return hex.EncodeToString(hash[:])
}

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
