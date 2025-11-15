#!/usr/bin/env python3
"""
Test Fabric Component Attestation Workflow
===========================================

This simulates how Fabric components (peers, orderers) would use
remote attestation to verify each other before establishing trust.

Scenario:
1. Orderer enclave generates attestation quote
2. Peer organization acts as verifier
3. Peer verifies orderer's enclave before accepting blocks
4. Only trusted enclaves can participate in the network
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from enclave_core import EnclaveSimulator
from attestation_verifier import AttestationVerifier

def main():
    print("\n" + "=" * 70)
    print("FABRIC ATTESTATION WORKFLOW SIMULATION")
    print("=" * 70)
    print("\nScenario: Orderer must prove its enclave integrity to peers")
    print("before peers will accept blocks from it.\n")

    # ========================================================================
    # STEP 1: Initialize Orderer Enclave
    # ========================================================================
    print("=" * 70)
    print("STEP 1: Hot Chain Orderer Initializes Enclave")
    print("=" * 70)
    orderer_enclave = EnclaveSimulator()
    print("  Orderer: orderer0.hot-chain.com initialized")

    # ========================================================================
    # STEP 2: Orderer Generates Attestation Quote
    # ========================================================================
    print("\n" + "=" * 70)
    print("STEP 2: Orderer Generates Attestation Quote")
    print("=" * 70)
    print("  Orderer generates quote to prove it's running in trusted enclave")

    # Include orderer identity in report data
    report_data = b"orderer0.hot-chain.com|block-signing-service"
    orderer_quote = orderer_enclave.generate_attestation_quote(report_data)

    print(f"  ✓ Quote generated")
    print(f"    MREnclave: {orderer_quote['mr_enclave'][:48]}...")
    print(f"    MRSigner:  {orderer_quote['mr_signer'][:48]}...")
    print(f"    Nonce:     {orderer_quote['nonce']}")

    # ========================================================================
    # STEP 3: Initialize Peer Organization's Attestation Verifier
    # ========================================================================
    print("\n" + "=" * 70)
    print("STEP 3: LawEnforcementMSP Initializes Attestation Verifier")
    print("=" * 70)
    print("  Peer organization runs independent verifier service")

    # Load policy file if it exists
    policy_file = Path(__file__).parent / "attestation_policy.json"
    law_enforcement_verifier = AttestationVerifier(policy_file=str(policy_file))

    # Add orderer's measurements to trusted policy
    print("\n  Adding orderer enclave to trusted measurements policy...")
    law_enforcement_verifier.add_trusted_measurement(
        orderer_quote["mr_enclave"],
        orderer_quote["mr_signer"]
    )
    print("  ✓ Orderer measurements added to policy")

    # ========================================================================
    # STEP 4: Peer Verifies Orderer's Attestation (REMOTE VERIFICATION)
    # ========================================================================
    print("\n" + "=" * 70)
    print("STEP 4: Peer Performs Remote Attestation Verification")
    print("=" * 70)
    print("  LawEnforcementMSP peer verifies orderer's quote...")

    result = law_enforcement_verifier.verify_and_print(
        orderer_quote,
        "orderer0.hot-chain.com"
    )

    # ========================================================================
    # STEP 5: Establish Trust Based on Attestation
    # ========================================================================
    print("=" * 70)
    print("STEP 5: Establish Trust")
    print("=" * 70)

    if result["valid"]:
        print("  ✓ ATTESTATION VERIFIED")
        print("\n  Peer decision:")
        print("    • Orderer enclave measurements match trusted policy")
        print("    • Orderer is running authentic DFIR-Fabric code")
        print("    • Orderer's block signatures can be trusted")
        print("    • Peer will accept blocks from this orderer")
        print("\n  ✓ Trust relationship established")
    else:
        print("  ✗ ATTESTATION FAILED")
        print(f"\n  Reason: {result['reason']}")
        print("\n  Peer decision:")
        print("    • Orderer enclave is NOT trusted")
        print("    • Peer will REJECT blocks from this orderer")
        print("    • Connection terminated")

    # ========================================================================
    # STEP 6: Simulate Multi-Organization Verification
    # ========================================================================
    print("\n" + "=" * 70)
    print("STEP 6: Multi-Organization Verification")
    print("=" * 70)
    print("  Other organizations also verify the orderer...")

    # ForensicLabMSP verifies
    print("\n  ForensicLabMSP:")
    forensic_verifier = AttestationVerifier(policy_file=str(policy_file))
    forensic_verifier.add_trusted_measurement(
        orderer_quote["mr_enclave"],
        orderer_quote["mr_signer"]
    )
    forensic_result = forensic_verifier.verify_quote(orderer_quote)
    status = "✓ VERIFIED" if forensic_result["valid"] else "✗ REJECTED"
    print(f"    {status} - {forensic_result['reason']}")

    # ArchiveMSP verifies (cold chain)
    print("\n  ArchiveMSP (cold chain):")
    archive_verifier = AttestationVerifier(policy_file=str(policy_file))
    archive_verifier.add_trusted_measurement(
        orderer_quote["mr_enclave"],
        orderer_quote["mr_signer"]
    )
    archive_result = archive_verifier.verify_quote(orderer_quote)
    status = "✓ VERIFIED" if archive_result["valid"] else "✗ REJECTED"
    print(f"    {status} - {archive_result['reason']}")

    # ========================================================================
    # STEP 7: Test Rogue Orderer Detection
    # ========================================================================
    print("\n" + "=" * 70)
    print("STEP 7: Rogue Orderer Detection")
    print("=" * 70)
    print("  Simulate a compromised orderer attempting to join...")

    # Create a rogue quote with different measurements (simulates different code)
    rogue_quote = orderer_quote.copy()
    rogue_quote["mr_enclave"] = "DEADBEEF" + "0" * 56  # Different enclave code
    rogue_quote["mr_signer"] = "BAADF00D" + "0" * 56   # Different signer

    # Re-sign the tampered quote (attacker tries to make it look valid)
    import json
    import hashlib
    quote_for_sig = rogue_quote.copy()
    quote_for_sig.pop("signature", None)
    rogue_quote["signature"] = hashlib.sha256(
        json.dumps(quote_for_sig, sort_keys=True).encode()
    ).hexdigest()

    print(f"\n  Rogue orderer quote:")
    print(f"    MREnclave: {rogue_quote['mr_enclave'][:48]}...")
    print(f"    MRSigner:  {rogue_quote['mr_signer'][:48]}...")

    print("\n  LawEnforcementMSP verifies rogue orderer:")
    rogue_result = law_enforcement_verifier.verify_quote(rogue_quote)

    if not rogue_result["valid"]:
        print(f"    ✓ CORRECTLY REJECTED - {rogue_result['reason']}")
        print("    • Rogue orderer measurements do NOT match policy")
        print("    • Peer refuses connection")
        print("    • Network remains secure")
    else:
        print(f"    ✗ ERROR - Rogue orderer was accepted (should not happen!)")

    # ========================================================================
    # Summary
    # ========================================================================
    print("\n" + "=" * 70)
    print("FABRIC ATTESTATION WORKFLOW SUMMARY")
    print("=" * 70)

    tests = [
        ("Orderer attestation generation", orderer_quote is not None),
        ("LawEnforcementMSP verification", result["valid"]),
        ("ForensicLabMSP verification", forensic_result["valid"]),
        ("ArchiveMSP verification", archive_result["valid"]),
        ("Rogue orderer detection", not rogue_result["valid"]),
    ]

    passed = sum(1 for _, result in tests if result)
    total = len(tests)

    print("\n  Test Results:")
    for test_name, result in tests:
        status = "✓" if result else "✗"
        print(f"    {status} {test_name}")

    print(f"\n  Total: {passed}/{total} tests passed")

    if passed == total:
        print("\n  ✓ ATTESTATION WORKFLOW FUNCTIONING CORRECTLY")
        print("\n  Key Capabilities Demonstrated:")
        print("    1. Orderer generates verifiable attestation quotes")
        print("    2. Multiple organizations independently verify quotes")
        print("    3. Signature verification prevents tampering")
        print("    4. Trusted measurements policy enforced")
        print("    5. Rogue/compromised enclaves detected and rejected")
        print("\n  The network can establish trust relationships based on")
        print("  cryptographic proof of enclave integrity.")
    else:
        print(f"\n  ✗ {total - passed} test(s) failed")

    print()
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
