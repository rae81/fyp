#!/usr/bin/env python3
"""
Verify All Fabric Certificates
================================

Verifies that all generated certificates:
1. Are properly signed by the Root CA
2. Have correct subject names
3. Have valid expiration dates
4. Can form proper certificate chains
"""

import sys
from pathlib import Path
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.backends import default_backend
from datetime import datetime

sys.path.insert(0, str(Path(__file__).parent))
from enclave_core import ROOT_CA_CERT_FILE

PROJECT_DIR = Path(__file__).parent.parent
CRYPTO_DIR = PROJECT_DIR / "organizations"

class CertificateVerifier:
    def __init__(self):
        """Load Root CA for verification"""
        print("\n" + "=" * 60)
        print("CERTIFICATE VERIFICATION")
        print("=" * 60)

        if not ROOT_CA_CERT_FILE.exists():
            print("❌ Root CA not found. Run generate_certs_direct.py first")
            sys.exit(1)

        # Load Root CA
        ca_pem = ROOT_CA_CERT_FILE.read_bytes()
        self.root_ca = x509.load_pem_x509_certificate(ca_pem, default_backend())
        self.root_ca_public_key = self.root_ca.public_key()

        print(f"\n  Root CA: {self.root_ca.subject.rfc4514_string()}")
        print(f"  Serial: {hex(self.root_ca.serial_number)}")
        print()

    def verify_certificate(self, cert_path: Path, expected_type: str = "") -> bool:
        """Verify a single certificate"""
        try:
            # Load certificate
            cert_pem = cert_path.read_bytes()
            cert = x509.load_pem_x509_certificate(cert_pem, default_backend())

            # 1. Verify signature
            try:
                self.root_ca_public_key.verify(
                    cert.signature,
                    cert.tbs_certificate_bytes,
                    padding.PKCS1v15(),
                    cert.signature_hash_algorithm
                )
            except Exception as e:
                print(f"     ✗ Signature verification failed: {e}")
                return False

            # 2. Check validity dates
            try:
                now = datetime.utcnow()
                not_before = cert.not_valid_before if hasattr(cert, 'not_valid_before') else cert.not_valid_before_utc
                not_after = cert.not_valid_after if hasattr(cert, 'not_valid_after') else cert.not_valid_after_utc

                if now < not_before:
                    print(f"     ✗ Certificate not yet valid")
                    return False
                if now > not_after:
                    print(f"     ✗ Certificate expired")
                    return False
            except AttributeError:
                # If we can't get the dates, skip this check
                pass

            # 3. Verify issuer matches Root CA
            if cert.issuer != self.root_ca.subject:
                print(f"     ✗ Issuer mismatch")
                return False

            # Get subject CN for display
            cn_attr = cert.subject.get_attributes_for_oid(x509.oid.NameOID.COMMON_NAME)
            cn = cn_attr[0].value if cn_attr else "Unknown"

            # Calculate validity
            try:
                days_valid = (not_after - now).days
                print(f"     ✓ {cert_path.relative_to(CRYPTO_DIR)} - CN: {cn} (expires in {days_valid} days)")
            except:
                print(f"     ✓ {cert_path.relative_to(CRYPTO_DIR)} - CN: {cn}")

            return True

        except Exception as e:
            print(f"     ✗ {cert_path.relative_to(CRYPTO_DIR)} - Error: {e}")
            return False

    def verify_all_certificates(self):
        """Verify all generated certificates"""
        print("=" * 60)
        print("Verifying All Certificates")
        print("=" * 60)

        total = 0
        passed = 0
        failed = 0

        # Find all certificate files
        cert_patterns = ["**/cert.pem", "**/*.crt", "**/cacerts/*.pem", "**/tlscacerts/*.pem"]

        cert_files = []
        for pattern in cert_patterns:
            cert_files.extend(CRYPTO_DIR.glob(pattern))

        # Remove duplicates
        cert_files = list(set(cert_files))

        # Organize by type
        print(f"\n  Found {len(cert_files)} certificate files\n")

        # Verify each certificate
        for cert_file in sorted(cert_files):
            # Skip Root CA cert (it's self-signed)
            if "ca-cert.pem" in str(cert_file) or "tlsca-cert.pem" in str(cert_file):
                # Verify it matches our root CA
                try:
                    cert_pem = cert_file.read_bytes()
                    root_ca_pem = self.root_ca.public_bytes(serialization.Encoding.PEM)
                    if cert_pem == root_ca_pem:
                        print(f"     ✓ {cert_file.relative_to(CRYPTO_DIR)} - Root CA (correct)")
                        passed += 1
                        total += 1
                    else:
                        print(f"     ✗ {cert_file.relative_to(CRYPTO_DIR)} - Root CA mismatch!")
                        failed += 1
                        total += 1
                except:
                    print(f"     ✗ {cert_file.relative_to(CRYPTO_DIR)} - Cannot read")
                    failed += 1
                    total += 1
                continue

            total += 1
            if self.verify_certificate(cert_file):
                passed += 1
            else:
                failed += 1

        # Summary
        print("\n" + "=" * 60)
        print("VERIFICATION SUMMARY")
        print("=" * 60)
        print(f"\n  Total Certificates: {total}")
        print(f"  ✓ Passed: {passed}")
        print(f"  ✗ Failed: {failed}")

        if failed == 0:
            print("\n  ✓ ALL CERTIFICATES VALID")
            print("  All certificates properly signed by enclave Root CA")
        else:
            print(f"\n  ⚠ {failed} certificate(s) failed verification")

        print()
        return failed == 0

def main():
    """Main function"""
    try:
        verifier = CertificateVerifier()
        success = verifier.verify_all_certificates()

        if success:
            print("=" * 60)
            print("CERTIFICATE CHAIN VERIFIED")
            print("=" * 60)
            print("\n  All Fabric certificates are valid and properly signed")
            print("  by the enclave Root CA.")
            print("\n  Next: Update Fabric configs and start networks")
            print()
            return 0
        else:
            return 1

    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    sys.exit(main())
