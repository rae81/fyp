package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"net"
	"strings"
	"sync"
	"time"

	"google.golang.org/grpc"
)

// Policy rules structure
type PolicyRule struct {
	Role            string
	ResourcePattern string
	Action          string
	MinClearance    int
}

// User role assignment
type UserRole struct {
	UserID    string
	Role      string
	Clearance int
}

// PRV Service state (simulated enclave)
type PRVService struct {
	UnimplementedPRVServer
	signingKey  *ecdsa.PrivateKey
	publicKey   []byte
	policies    []PolicyRule
	users       map[string]UserRole
	mrenclave   []byte // Simulated enclave measurement
	mrsigner    []byte // Simulated signer measurement
	initialized bool
	mu          sync.RWMutex
}

// Initialize PRV with user roles
func (s *PRVService) InitPRV(req *InitRequest, stream PRV_InitPRVServer) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.initialized {
		return stream.Send(&InitResponse{
			Success: true,
			Message: "PRV already initialized",
		})
	}

	log.Println("Initializing PRV service (simulated enclave)...")

	// Generate signing key (simulating enclave key generation)
	privateKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return fmt.Errorf("failed to generate key: %v", err)
	}
	s.signingKey = privateKey

	// Export public key (uncompressed format: 0x04 + X + Y)
	pubKeyBytes := elliptic.Marshal(elliptic.P256(), privateKey.PublicKey.X, privateKey.PublicKey.Y)
	s.publicKey = pubKeyBytes

	// Generate simulated measurements (in real system, these come from platform)
	s.mrenclave = make([]byte, 32)
	s.mrsigner = make([]byte, 32)
	rand.Read(s.mrenclave)
	rand.Read(s.mrsigner)

	// Load user roles
	s.users = make(map[string]UserRole)
	for _, role := range req.Roles {
		s.users[role.UserId] = UserRole{
			UserID:    role.UserId,
			Role:      role.Role,
			Clearance: int(role.Clearance),
		}
		log.Printf("  Loaded user: %s (role=%s, clearance=%d)",
			role.UserId, role.Role, role.Clearance)
	}

	// Initialize default DFIR policies
	s.initializePolicies()

	s.initialized = true

	log.Printf("✓ PRV initialized successfully")
	log.Printf("  Users: %d", len(s.users))
	log.Printf("  Policies: %d", len(s.policies))
	log.Printf("  MRENCLAVE: %x...", s.mrenclave[:8])
	log.Printf("  Public Key: %x...", s.publicKey[:16])

	return stream.Send(&InitResponse{
		Success: true,
		Message: fmt.Sprintf("PRV initialized with %d users and %d policies", len(s.users), len(s.policies)),
	})
}

// Initialize Casbin-style RBAC policies
func (s *PRVService) initializePolicies() {
	s.policies = []PolicyRule{
		// Admin - full access
		{Role: "admin", ResourcePattern: "evidence/*", Action: "*", MinClearance: 1},
		{Role: "admin", ResourcePattern: "case/*", Action: "*", MinClearance: 1},

		// Investigator policies
		{Role: "investigator", ResourcePattern: "evidence/*", Action: "create", MinClearance: 2},
		{Role: "investigator", ResourcePattern: "evidence/*", Action: "transfer", MinClearance: 2},
		{Role: "investigator", ResourcePattern: "evidence/*", Action: "read", MinClearance: 2},
		{Role: "investigator", ResourcePattern: "case/*", Action: "read", MinClearance: 2},
		{Role: "investigator", ResourcePattern: "case/*", Action: "update", MinClearance: 2},

		// Auditor - read only
		{Role: "auditor", ResourcePattern: "evidence/*", Action: "read", MinClearance: 3},
		{Role: "auditor", ResourcePattern: "case/*", Action: "read", MinClearance: 3},
		{Role: "auditor", ResourcePattern: "audit_log/*", Action: "read", MinClearance: 3},

		// Court - read approved evidence
		{Role: "court", ResourcePattern: "evidence/*/approved", Action: "read", MinClearance: 4},
		{Role: "court", ResourcePattern: "case/*/final", Action: "read", MinClearance: 4},
	}

	log.Printf("Initialized %d policy rules", len(s.policies))
}

// Evaluate policy using Casbin-style matching
func (s *PRVService) EvaluatePolicy(req *PolicyRequest, stream PRV_EvaluatePolicyServer) error {
	s.mu.RLock()
	defer s.mu.RUnlock()

	if !s.initialized {
		return fmt.Errorf("PRV not initialized")
	}

	// Get user role
	user, exists := s.users[req.Subject]
	if !exists {
		log.Printf("Policy DENY: user %s not found", req.Subject)
		return stream.Send(&PolicyResponse{
			Allow:  false,
			Reason: fmt.Sprintf("User %s not found in role assignments", req.Subject),
		})
	}

	// Evaluate against policies
	for _, policy := range s.policies {
		// Check role match
		if policy.Role != user.Role {
			continue
		}

		// Check resource pattern
		if !matchPattern(policy.ResourcePattern, req.Resource) {
			continue
		}

		// Check action (wildcard or exact match)
		if policy.Action != "*" && policy.Action != req.Action {
			continue
		}

		// Check clearance level
		if user.Clearance < policy.MinClearance {
			log.Printf("Policy DENY: user %s clearance too low (has %d, needs %d)",
				req.Subject, user.Clearance, policy.MinClearance)
			continue
		}

		// All checks passed - ALLOW
		log.Printf("Policy ALLOW: user=%s role=%s action=%s resource=%s",
			req.Subject, user.Role, req.Action, req.Resource)

		return stream.Send(&PolicyResponse{
			Allow:  true,
			Reason: fmt.Sprintf("Access allowed by policy: %s can %s %s", user.Role, req.Action, req.Resource),
		})
	}

	// No matching policy found - DENY
	log.Printf("Policy DENY: user=%s action=%s resource=%s (no matching policy)",
		req.Subject, req.Action, req.Resource)

	return stream.Send(&PolicyResponse{
		Allow:  false,
		Reason: "No matching policy found for this action",
	})
}

// Get signed permit with attestation
func (s *PRVService) GetSignedPermit(req *PermitRequest, stream PRV_GetSignedPermitServer) error {
	s.mu.RLock()
	defer s.mu.RUnlock()

	if !s.initialized {
		return fmt.Errorf("PRV not initialized")
	}

	log.Printf("Signing permit: subject=%s action=%s resource=%s decision=%s",
		req.Subject, req.Action, req.Resource, boolToDecision(req.Allow))

	// Create permit payload
	payload := map[string]interface{}{
		"sub":       req.Subject,
		"action":    req.Action,
		"resource":  req.Resource,
		"clearance": req.Clearance,
		"decision":  boolToDecision(req.Allow),
		"timestamp": time.Now().Unix(),
		"nonce":     base64.StdEncoding.EncodeToString(req.Nonce),
		"mrenclave": fmt.Sprintf("%x", s.mrenclave[:8]), // First 8 bytes as hex
	}

	payloadJSON, _ := json.Marshal(payload)
	payloadB64 := base64.RawURLEncoding.EncodeToString(payloadJSON)

	// Create JWS header
	header := map[string]string{"alg": "ES256", "typ": "JWT"}
	headerJSON, _ := json.Marshal(header)
	headerB64 := base64.RawURLEncoding.EncodeToString(headerJSON)

	// Sign: SHA256(header.payload)
	signData := headerB64 + "." + payloadB64
	hash := sha256.Sum256([]byte(signData))

	r, sigS, err := ecdsa.Sign(rand.Reader, s.signingKey, hash[:])
	if err != nil {
		return fmt.Errorf("signing failed: %v", err)
	}

	// Encode signature as R||S (64 bytes total, 32 each)
	signature := make([]byte, 64)
	rBytes := r.Bytes()
	sBytes := sigS.Bytes()

	// Pad R to 32 bytes
	copy(signature[32-len(rBytes):32], rBytes)
	// Pad S to 32 bytes
	copy(signature[64-len(sBytes):64], sBytes)

	// Create attestation report (simulated)
	attestation := &AttestationReport{
		Mrenclave: s.mrenclave,
		Mrsigner:  s.mrsigner,
		Timestamp: uint64(time.Now().Unix()),
		Nonce:     req.Nonce,
		Signature: make([]byte, 64), // In real system, signed by platform
	}
	rand.Read(attestation.Signature) // Simulated platform signature

	permit := &JWSPermit{
		Header:    headerB64,
		Payload:   payloadB64,
		Signature: signature,
	}

	log.Printf("✓ Permit signed successfully")

	return stream.Send(&PermitResponse{
		Permit:      permit,
		Attestation: attestation,
	})
}

// Get attestation report
func (s *PRVService) GetAttestation(req *AttestationRequest, stream PRV_GetAttestationServer) error {
	s.mu.RLock()
	defer s.mu.RUnlock()

	if !s.initialized {
		return fmt.Errorf("PRV not initialized")
	}

	log.Printf("Generating attestation report")

	// Create attestation report
	attestation := &AttestationReport{
		Mrenclave: s.mrenclave,
		Mrsigner:  s.mrsigner,
		Timestamp: uint64(time.Now().Unix()),
		Nonce:     req.Challenge,
		Signature: make([]byte, 64), // Simulated platform signature
	}

	// In real system, this would be signed by platform attestation service (ARM PSA, Intel IAS, etc.)
	rand.Read(attestation.Signature)

	log.Printf("✓ Attestation generated: mrenclave=%x...", s.mrenclave[:8])

	return stream.Send(&AttestationResponse{
		Attestation: attestation,
	})
}

// Get public key for verification
func (s *PRVService) GetPublicKey(req *PublicKeyRequest, stream PRV_GetPublicKeyServer) error {
	s.mu.RLock()
	defer s.mu.RUnlock()

	if !s.initialized {
		return fmt.Errorf("PRV not initialized")
	}

	log.Printf("Providing public key for chaincode initialization")

	return stream.Send(&PublicKeyResponse{
		PublicKey: s.publicKey,
		KeyType:   "ES256",
	})
}

// Helper: simple wildcard pattern matching
func matchPattern(pattern, resource string) bool {
	if pattern == resource {
		return true
	}

	// Handle wildcard at end: "evidence/*"
	if strings.HasSuffix(pattern, "/*") {
		prefix := strings.TrimSuffix(pattern, "/*")
		return strings.HasPrefix(resource, prefix+"/")
	}

	// Handle wildcard in middle: "evidence/*/approved"
	if strings.Contains(pattern, "/*") {
		parts := strings.Split(pattern, "/*")
		if len(parts) == 2 {
			return strings.HasPrefix(resource, parts[0]+"/") &&
				strings.HasSuffix(resource, "/"+parts[1])
		}
	}

	return false
}

// Helper: convert bool to decision string
func boolToDecision(b bool) string {
	if b {
		return "allow"
	}
	return "deny"
}

func main() {
	listener, err := net.Listen("tcp", ":50051")
	if err != nil {
		log.Fatalf("Failed to listen on :50051: %v", err)
	}

	grpcServer := grpc.NewServer()
	prvService := &PRVService{}

	RegisterPRVServer(grpcServer, prvService)

	log.Println("=====================================================")
	log.Println("  DFIR PRV Service (Simulated Enclave)")
	log.Println("=====================================================")
	log.Println("Starting gRPC server on :50051")
	log.Println("Waiting for InitPRV call to initialize...")
	log.Println("")

	if err := grpcServer.Serve(listener); err != nil {
		log.Fatalf("Failed to serve: %v", err)
	}
}
