#!/usr/bin/env python3
"""
Remote Attestation Verifier Service
====================================

This service acts as a REMOTE VERIFIER for enclave attestation quotes.
It simulates what an external service (like Intel IAS or DCAP) would do:

1. Receives attestation quotes from enclaves
2. Verifies quote signatures
3. Checks measurements against trusted policy
4. Returns attestation verification result

This is separate from the enclave and acts as an independent third party.
"""

import json
import hashlib
from datetime import datetime
from typing import Dict, Tuple, List
from pathlib import Path

# Trusted measurements policy
# In production, this would be maintained by the verifier operator
TRUSTED_MEASUREMENTS = {
    "allowed_mr_enclaves": [],  # Will be populated from policy file
    "allowed_mr_signers": [],   # Will be populated from policy file
    "minimum_tcb_level": "1",
    "max_quote_age_seconds": 300,  # 5 minutes
}

class AttestationVerifier:
    """Independent attestation verification service"""

    def __init__(self, policy_file: str = None):
        """Initialize verifier with policy"""
        self.policy_file = policy_file
        self.load_policy()
        print("=" * 60)
        print("ATTESTATION VERIFIER SERVICE")
        print("=" * 60)
        print(f"  Policy file: {self.policy_file}")
        print(f"  Trusted MREnclaves: {len(TRUSTED_MEASUREMENTS['allowed_mr_enclaves'])}")
        print(f"  Trusted MRSigners: {len(TRUSTED_MEASUREMENTS['allowed_mr_signers'])}")
        print(f"  Minimum TCB: {TRUSTED_MEASUREMENTS['minimum_tcb_level']}")
        print(f"  Max quote age: {TRUSTED_MEASUREMENTS['max_quote_age_seconds']}s")
        print()

    def load_policy(self):
        """Load trusted measurements policy"""
        if self.policy_file and Path(self.policy_file).exists():
            with open(self.policy_file, 'r') as f:
                policy = json.load(f)
                TRUSTED_MEASUREMENTS.update(policy)
        else:
            # Default: accept any measurements (permissive for testing)
            print("  ⚠ No policy file - using permissive mode (accepts all)")

    def add_trusted_measurement(self, mr_enclave: str, mr_signer: str):
        """Add a trusted measurement to the policy"""
        if mr_enclave not in TRUSTED_MEASUREMENTS["allowed_mr_enclaves"]:
            TRUSTED_MEASUREMENTS["allowed_mr_enclaves"].append(mr_enclave)
        if mr_signer not in TRUSTED_MEASUREMENTS["allowed_mr_signers"]:
            TRUSTED_MEASUREMENTS["allowed_mr_signers"].append(mr_signer)

    def verify_quote(self, quote: Dict) -> Dict:
        """
        Verify an attestation quote (REMOTE VERIFICATION)

        Returns a verification result with:
        - valid: bool
        - reason: str
        - details: Dict
        """
        result = {
            "valid": False,
            "reason": "",
            "timestamp": datetime.utcnow().isoformat(),
            "checks": {
                "signature_valid": False,
                "mrenclave_trusted": False,
                "mrsigner_trusted": False,
                "tcb_acceptable": False,
                "timestamp_fresh": False,
            }
        }

        # Check 1: Verify signature
        try:
            # Extract signature
            signature = quote.get("signature")
            if not signature:
                result["reason"] = "Missing signature"
                return result

            # Reconstruct quote without signature for verification
            quote_copy = quote.copy()
            quote_copy.pop("signature", None)

            # Verify signature (in real SGX, this would use Intel's public key)
            expected_signature = hashlib.sha256(
                json.dumps(quote_copy, sort_keys=True).encode()
            ).hexdigest()

            if signature != expected_signature:
                result["reason"] = "Signature verification failed"
                return result

            result["checks"]["signature_valid"] = True

        except Exception as e:
            result["reason"] = f"Signature verification error: {e}"
            return result

        # Check 2: Verify MREnclave is trusted
        mr_enclave = quote.get("mr_enclave")
        if not mr_enclave:
            result["reason"] = "Missing MREnclave"
            return result

        # In permissive mode (no policy), accept all
        if not TRUSTED_MEASUREMENTS["allowed_mr_enclaves"]:
            result["checks"]["mrenclave_trusted"] = True
        elif mr_enclave in TRUSTED_MEASUREMENTS["allowed_mr_enclaves"]:
            result["checks"]["mrenclave_trusted"] = True
        else:
            result["reason"] = f"MREnclave not in trusted policy: {mr_enclave[:32]}..."
            return result

        # Check 3: Verify MRSigner is trusted
        mr_signer = quote.get("mr_signer")
        if not mr_signer:
            result["reason"] = "Missing MRSigner"
            return result

        # In permissive mode (no policy), accept all
        if not TRUSTED_MEASUREMENTS["allowed_mr_signers"]:
            result["checks"]["mrsigner_trusted"] = True
        elif mr_signer in TRUSTED_MEASUREMENTS["allowed_mr_signers"]:
            result["checks"]["mrsigner_trusted"] = True
        else:
            result["reason"] = f"MRSigner not in trusted policy: {mr_signer[:32]}..."
            return result

        # Check 4: Verify TCB level is acceptable
        tcb_level = quote.get("tcb_level")
        if not tcb_level:
            result["reason"] = "Missing TCB level"
            return result

        # Simple string comparison (in real systems, this is more complex)
        if tcb_level >= TRUSTED_MEASUREMENTS["minimum_tcb_level"]:
            result["checks"]["tcb_acceptable"] = True
        else:
            result["reason"] = f"TCB level {tcb_level} below minimum {TRUSTED_MEASUREMENTS['minimum_tcb_level']}"
            return result

        # Check 5: Verify timestamp is fresh
        timestamp = quote.get("timestamp")
        if not timestamp:
            result["reason"] = "Missing timestamp"
            return result

        quote_time = datetime.fromtimestamp(timestamp)
        age = (datetime.utcnow() - quote_time).total_seconds()

        if age > TRUSTED_MEASUREMENTS["max_quote_age_seconds"]:
            result["reason"] = f"Quote too old: {age:.0f}s (max {TRUSTED_MEASUREMENTS['max_quote_age_seconds']}s)"
            return result

        result["checks"]["timestamp_fresh"] = True

        # All checks passed
        result["valid"] = True
        result["reason"] = "Attestation verified successfully"
        result["enclave_identity"] = {
            "mr_enclave": mr_enclave,
            "mr_signer": mr_signer,
            "tcb_level": tcb_level,
            "quote_age_seconds": age,
        }

        return result

    def verify_and_print(self, quote: Dict, enclave_name: str = "Unknown"):
        """Verify quote and print detailed results"""
        print(f"\n{'='*60}")
        print(f"REMOTE ATTESTATION VERIFICATION - {enclave_name}")
        print(f"{'='*60}")

        result = self.verify_quote(quote)

        print(f"\n  Quote Details:")
        print(f"    MREnclave: {quote.get('mr_enclave', 'N/A')[:48]}...")
        print(f"    MRSigner:  {quote.get('mr_signer', 'N/A')[:48]}...")
        print(f"    TCB Level: {quote.get('tcb_level', 'N/A')}")
        print(f"    Version:   {quote.get('version', 'N/A')}")
        print(f"    Nonce:     {quote.get('nonce', 'N/A')[:16]}...")

        print(f"\n  Verification Checks:")
        for check_name, passed in result["checks"].items():
            status = "✓" if passed else "✗"
            print(f"    {status} {check_name.replace('_', ' ').title()}")

        print(f"\n  Result: ", end="")
        if result["valid"]:
            print(f"✓ VERIFIED - {result['reason']}")
            if "enclave_identity" in result:
                print(f"\n  Enclave Identity:")
                print(f"    MREnclave: {result['enclave_identity']['mr_enclave'][:48]}...")
                print(f"    MRSigner:  {result['enclave_identity']['mr_signer'][:48]}...")
                print(f"    TCB Level: {result['enclave_identity']['tcb_level']}")
                print(f"    Quote Age: {result['enclave_identity']['quote_age_seconds']:.1f}s")
        else:
            print(f"✗ FAILED - {result['reason']}")

        print()
        return result

    def save_policy(self, output_file: str):
        """Save current policy to file"""
        with open(output_file, 'w') as f:
            json.dump(TRUSTED_MEASUREMENTS, f, indent=2)
        print(f"✓ Policy saved to: {output_file}")


def main():
    """Test the verifier with sample quotes"""
    import sys
    sys.path.insert(0, str(Path(__file__).parent))
    from enclave_core import EnclaveSimulator

    print("\n" + "=" * 60)
    print("REMOTE ATTESTATION VERIFICATION TEST")
    print("=" * 60)
    print("\nThis test simulates proper remote attestation where:")
    print("  1. Enclave (attester) generates a quote")
    print("  2. Remote verifier independently verifies the quote")
    print("  3. Verifier checks against trusted measurement policy")
    print()

    # Initialize enclave (attester)
    print("=" * 60)
    print("STEP 1: Initialize Enclave (Attester)")
    print("=" * 60)
    enclave = EnclaveSimulator()

    # Generate attestation quote
    print("\n" + "=" * 60)
    print("STEP 2: Generate Attestation Quote")
    print("=" * 60)
    report_data = b"fabric-orderer-block-12345"
    quote = enclave.generate_attestation_quote(report_data)
    print(f"✓ Quote generated with {len(json.dumps(quote))} bytes")
    print(f"  MREnclave: {quote['mr_enclave'][:48]}...")
    print(f"  MRSigner:  {quote['mr_signer'][:48]}...")
    print(f"  Nonce:     {quote['nonce']}")

    # Initialize remote verifier (separate service)
    print("\n" + "=" * 60)
    print("STEP 3: Initialize Remote Verifier (Separate Service)")
    print("=" * 60)
    verifier = AttestationVerifier()

    # Test 1: Verify with permissive policy (should pass)
    print("\n" + "=" * 60)
    print("TEST 1: Verification with Permissive Policy")
    print("=" * 60)
    result1 = verifier.verify_and_print(quote, "Test Enclave #1")

    # Test 2: Add enclave to trusted policy and verify again
    print("\n" + "=" * 60)
    print("TEST 2: Add to Trusted Policy and Re-verify")
    print("=" * 60)
    verifier.add_trusted_measurement(quote["mr_enclave"], quote["mr_signer"])
    print(f"✓ Added enclave measurements to trusted policy")
    result2 = verifier.verify_and_print(quote, "Test Enclave #1")

    # Test 3: Verify invalid quote (tampered)
    print("\n" + "=" * 60)
    print("TEST 3: Verify Tampered Quote (Should Fail)")
    print("=" * 60)
    tampered_quote = quote.copy()
    tampered_quote["mr_enclave"] = "0" * 64  # Tamper with measurement
    result3 = verifier.verify_and_print(tampered_quote, "Tampered Enclave")

    # Test 4: Verify quote with invalid signature
    print("\n" + "=" * 60)
    print("TEST 4: Verify Quote with Invalid Signature (Should Fail)")
    print("=" * 60)
    bad_sig_quote = quote.copy()
    bad_sig_quote["signature"] = "0" * 64  # Invalid signature
    result4 = verifier.verify_and_print(bad_sig_quote, "Bad Signature")

    # Summary
    print("\n" + "=" * 60)
    print("REMOTE ATTESTATION TEST SUMMARY")
    print("=" * 60)
    tests = [
        ("Permissive policy verification", result1["valid"]),
        ("Trusted policy verification", result2["valid"]),
        ("Tampered quote rejection", not result3["valid"]),
        ("Invalid signature rejection", not result4["valid"]),
    ]

    passed = sum(1 for _, result in tests if result)
    total = len(tests)

    for test_name, result in tests:
        status = "✓" if result else "✗"
        print(f"  {status} {test_name}")

    print(f"\n  Results: {passed}/{total} tests passed")

    if passed == total:
        print("\n  ✓ ALL REMOTE ATTESTATION TESTS PASSED")
        print("\n  The verifier correctly:")
        print("    • Verifies valid quotes")
        print("    • Checks signatures")
        print("    • Validates measurements against policy")
        print("    • Rejects tampered quotes")
        print("    • Rejects invalid signatures")
    else:
        print(f"\n  ✗ {total - passed} test(s) failed")

    # Save policy
    policy_file = Path(__file__).parent / "attestation_policy.json"
    verifier.save_policy(str(policy_file))
    print()

    return 0 if passed == total else 1


if __name__ == "__main__":
    import sys
    sys.exit(main())
