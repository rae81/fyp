#!/usr/bin/env python3
"""
Generate Fabric Certificates Directly using Enclave Core
==========================================================

This script generates x.509 certificates for all Hyperledger Fabric components
using the enclave simulator directly (no Flask API required).
"""

import os
import sys
from pathlib import Path
from cryptography import x509
from cryptography.x509.oid import NameOID, ExtensionOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.backends import default_backend

# Add enclave to path
sys.path.insert(0, str(Path(__file__).parent))
from enclave_core import EnclaveSimulator, ENCLAVE_DATA_DIR, ROOT_CA_CERT_FILE

PROJECT_DIR = Path(__file__).parent.parent
CRYPTO_DIR = PROJECT_DIR / "organizations"

class FabricCertGenerator:
    def __init__(self):
        """Initialize generator with enclave"""
        print("\n" + "=" * 60)
        print("FABRIC CERTIFICATE GENERATION (via Enclave)")
        print("=" * 60)

        # Initialize or load enclave
        self.enclave = EnclaveSimulator()

        # Check if Root CA exists, if not create it
        if not ROOT_CA_CERT_FILE.exists():
            print("\n  Creating Root CA in enclave...")
            self.enclave.generate_root_ca()
        else:
            print("\n  Loading existing Root CA from enclave...")
            self.enclave.load_root_ca()
            print("  ✓ Root CA loaded")

        # Get Root CA cert for distribution
        self.root_ca_cert = self.enclave.ca_cert
        print(f"\n  Root CA Subject: {self.root_ca_cert.subject.rfc4514_string()}")
        print(f"  Serial: {hex(self.root_ca_cert.serial_number)}")
        print()

    def generate_key(self) -> rsa.RSAPrivateKey:
        """Generate RSA private key"""
        return rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
            backend=default_backend()
        )

    def create_csr(self, private_key: rsa.RSAPrivateKey, common_name: str,
                   org: str = "DFIR-Fabric", country: str = "US") -> x509.CertificateSigningRequest:
        """Create a certificate signing request"""
        subject_name = x509.Name([
            x509.NameAttribute(NameOID.COUNTRY_NAME, country),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, org),
            x509.NameAttribute(NameOID.COMMON_NAME, common_name),
        ])

        csr = x509.CertificateSigningRequestBuilder().subject_name(
            subject_name
        ).sign(private_key, hashes.SHA256(), default_backend())

        return csr

    def get_ski_filename(self, cert_pem: bytes) -> str:
        """Extract SKI from certificate and return proper key filename"""
        cert = x509.load_pem_x509_certificate(cert_pem, default_backend())
        ski_ext = cert.extensions.get_extension_for_oid(ExtensionOID.SUBJECT_KEY_IDENTIFIER)
        ski_bytes = ski_ext.value.digest
        ski_hex = ski_bytes.hex()
        return f"{ski_hex}_sk"

    def create_msp_config(self, msp_dir: Path, node_ou_enabled: bool = True):
        """Create config.yaml for MSP directory"""
        config_content = f"""NodeOUs:
  Enable: {str(node_ou_enabled).lower()}
  ClientOUIdentifier:
    Certificate: cacerts/ca-cert.pem
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: cacerts/ca-cert.pem
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: cacerts/ca-cert.pem
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: cacerts/ca-cert.pem
    OrganizationalUnitIdentifier: orderer
"""
        (msp_dir / "config.yaml").write_text(config_content)

    def save_crypto_material(self, base_path: Path, key: rsa.RSAPrivateKey,
                            cert: bytes, name: str = ""):
        """Save private key and certificate"""
        base_path.mkdir(parents=True, exist_ok=True)

        # Save private key
        key_file = base_path / f"{name}key.pem" if name else base_path / "priv_sk"
        key_pem = key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption()
        )
        key_file.write_bytes(key_pem)

        # Save certificate
        cert_file = base_path / f"{name}cert.pem" if name else base_path / "cert.pem"
        cert_file.write_bytes(cert)

        # Copy Root CA cert to cacerts
        cacerts_dir = base_path.parent / "cacerts"
        cacerts_dir.mkdir(parents=True, exist_ok=True)
        root_ca_pem = self.root_ca_cert.public_bytes(serialization.Encoding.PEM)
        (cacerts_dir / "ca-cert.pem").write_bytes(root_ca_pem)

    def generate_orderer_certs(self, chain_type: str):
        """Generate orderer certificates (signing and TLS)"""
        print(f"\n{'='*60}")
        print(f"Generating Orderer Certificates - {chain_type.upper()} Chain")
        print(f"{'='*60}")

        orderer_name = f"orderer0.{chain_type}-chain.com"
        orderer_dir = CRYPTO_DIR / "ordererOrganizations" / f"{chain_type}-chain.com"

        # --- Signing Certificate ---
        print(f"\n  1. Orderer Signing Certificate: {orderer_name}")
        signing_key = self.generate_key()
        signing_csr = self.create_csr(signing_key, orderer_name, f"{chain_type.title()}ChainOrderer")
        signing_csr_pem = signing_csr.public_bytes(serialization.Encoding.PEM)

        # Sign with enclave
        signing_cert_pem = self.enclave.sign_certificate(signing_csr_pem, "orderer")

        # Save certificate to signcerts (NOT the key)
        signcerts_dir = orderer_dir / "orderers" / orderer_name / "msp" / "signcerts"
        signcerts_dir.mkdir(parents=True, exist_ok=True)
        (signcerts_dir / "cert.pem").write_bytes(signing_cert_pem)
        print(f"     ✓ Signing cert saved to: {signcerts_dir}")

        # Save private key to keystore with SKI-based filename
        keystore_dir = orderer_dir / "orderers" / orderer_name / "msp" / "keystore"
        keystore_dir.mkdir(parents=True, exist_ok=True)
        signing_key_pem = signing_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption()
        )
        # Use SKI-based filename for Fabric compatibility
        key_filename = self.get_ski_filename(signing_cert_pem)
        (keystore_dir / key_filename).write_bytes(signing_key_pem)

        # Store orderer signing key in enclave for block signing
        print(f"     ✓ Storing orderer key in enclave for block signing...")
        self.enclave.store_orderer_key(signing_key_pem)

        # --- TLS Certificate ---
        print(f"\n  2. Orderer TLS Certificate: {orderer_name}")
        tls_key = self.generate_key()
        tls_csr = self.create_csr(tls_key, orderer_name, f"{chain_type.title()}ChainOrderer")
        tls_csr_pem = tls_csr.public_bytes(serialization.Encoding.PEM)

        # Sign with enclave
        tls_cert_pem = self.enclave.sign_certificate(tls_csr_pem, "orderer")

        # Save
        tls_dir = orderer_dir / "orderers" / orderer_name / "tls"
        self.save_crypto_material(tls_dir, tls_key, tls_cert_pem, "")
        # Rename for Fabric convention
        (tls_dir / "cert.pem").rename(tls_dir / "server.crt")
        (tls_dir / "priv_sk").rename(tls_dir / "server.key")
        # Copy CA cert
        root_ca_pem = self.root_ca_cert.public_bytes(serialization.Encoding.PEM)
        (tls_dir / "ca.crt").write_bytes(root_ca_pem)
        print(f"     ✓ TLS cert saved to: {tls_dir}")

        # Copy Root CA to MSP cacerts
        cacerts_dir = orderer_dir / "orderers" / orderer_name / "msp" / "cacerts"
        cacerts_dir.mkdir(parents=True, exist_ok=True)
        (cacerts_dir / "ca-cert.pem").write_bytes(root_ca_pem)

        # Copy Root CA to MSP tlscacerts
        tlscacerts_dir = orderer_dir / "orderers" / orderer_name / "msp" / "tlscacerts"
        tlscacerts_dir.mkdir(parents=True, exist_ok=True)
        (tlscacerts_dir / "tlsca-cert.pem").write_bytes(root_ca_pem)

        # Create MSP config.yaml
        msp_base_dir = orderer_dir / "orderers" / orderer_name / "msp"
        self.create_msp_config(msp_base_dir)

        print(f"\n  ✓ Orderer certificates generated for {chain_type} chain")

    def generate_peer_certs(self, org_name: str, domain: str, chain_type: str):
        """Generate peer certificates (signing and TLS)"""
        print(f"\n{'='*60}")
        print(f"Generating Peer Certificates - {org_name}")
        print(f"{'='*60}")

        peer_name = f"peer0.{domain}"
        peer_dir = CRYPTO_DIR / "peerOrganizations" / domain

        # --- Peer Signing Certificate ---
        print(f"\n  1. Peer Signing Certificate: {peer_name}")
        signing_key = self.generate_key()
        signing_csr = self.create_csr(signing_key, peer_name, org_name)
        signing_csr_pem = signing_csr.public_bytes(serialization.Encoding.PEM)

        signing_cert_pem = self.enclave.sign_certificate(signing_csr_pem, "peer")

        # Save certificate to signcerts (NOT the key)
        signcerts_dir = peer_dir / "peers" / peer_name / "msp" / "signcerts"
        signcerts_dir.mkdir(parents=True, exist_ok=True)
        (signcerts_dir / "cert.pem").write_bytes(signing_cert_pem)

        # Save private key to keystore with SKI-based filename
        keystore_dir = peer_dir / "peers" / peer_name / "msp" / "keystore"
        keystore_dir.mkdir(parents=True, exist_ok=True)
        signing_key_pem = signing_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption()
        )
        # Use SKI-based filename for Fabric compatibility
        key_filename = self.get_ski_filename(signing_cert_pem)
        (keystore_dir / key_filename).write_bytes(signing_key_pem)
        print(f"     ✓ Signing cert saved")

        # --- Peer TLS Certificate ---
        print(f"\n  2. Peer TLS Certificate: {peer_name}")
        tls_key = self.generate_key()
        tls_csr = self.create_csr(tls_key, peer_name, org_name)
        tls_csr_pem = tls_csr.public_bytes(serialization.Encoding.PEM)

        tls_cert_pem = self.enclave.sign_certificate(tls_csr_pem, "peer")

        # Save
        tls_dir = peer_dir / "peers" / peer_name / "tls"
        self.save_crypto_material(tls_dir, tls_key, tls_cert_pem, "")
        (tls_dir / "cert.pem").rename(tls_dir / "server.crt")
        (tls_dir / "priv_sk").rename(tls_dir / "server.key")
        root_ca_pem = self.root_ca_cert.public_bytes(serialization.Encoding.PEM)
        (tls_dir / "ca.crt").write_bytes(root_ca_pem)
        print(f"     ✓ TLS cert saved")

        # --- Admin User Certificate ---
        print(f"\n  3. Admin User Certificate: admin@{domain}")
        admin_key = self.generate_key()
        admin_csr = self.create_csr(admin_key, f"admin@{domain}", org_name)
        admin_csr_pem = admin_csr.public_bytes(serialization.Encoding.PEM)

        admin_cert_pem = self.enclave.sign_certificate(admin_csr_pem, "client")

        # Save certificate to signcerts (NOT the key)
        admin_signcerts_dir = peer_dir / "users" / f"Admin@{domain}" / "msp" / "signcerts"
        admin_signcerts_dir.mkdir(parents=True, exist_ok=True)
        (admin_signcerts_dir / "cert.pem").write_bytes(admin_cert_pem)

        # Save private key to keystore with SKI-based filename
        admin_keystore = peer_dir / "users" / f"Admin@{domain}" / "msp" / "keystore"
        admin_keystore.mkdir(parents=True, exist_ok=True)
        admin_key_pem = admin_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption()
        )
        # Use SKI-based filename for Fabric compatibility
        key_filename = self.get_ski_filename(admin_cert_pem)
        (admin_keystore / key_filename).write_bytes(admin_key_pem)
        print(f"     ✓ Admin cert saved")

        # Copy Root CA to all MSP cacerts and create config.yaml
        for msp_base in [peer_dir / "peers" / peer_name / "msp",
                         peer_dir / "users" / f"Admin@{domain}" / "msp"]:
            cacerts_dir = msp_base / "cacerts"
            cacerts_dir.mkdir(parents=True, exist_ok=True)
            (cacerts_dir / "ca-cert.pem").write_bytes(root_ca_pem)

            tlscacerts_dir = msp_base / "tlscacerts"
            tlscacerts_dir.mkdir(parents=True, exist_ok=True)
            (tlscacerts_dir / "tlsca-cert.pem").write_bytes(root_ca_pem)

            # Create MSP config.yaml
            self.create_msp_config(msp_base)

        print(f"\n  ✓ Peer certificates generated for {org_name}")

    def generate_service_certs(self, service_name: str, service_domain: str):
        """Generate TLS certificates for external services like IPFS"""
        print(f"\n{'='*60}")
        print(f"Generating Service Certificates - {service_name}")
        print(f"{'='*60}")

        service_dir = CRYPTO_DIR / "services" / service_name

        # --- Service TLS Certificate ---
        print(f"\n  Service TLS Certificate: {service_domain}")
        tls_key = self.generate_key()
        tls_csr = self.create_csr(tls_key, service_domain, service_name)
        tls_csr_pem = tls_csr.public_bytes(serialization.Encoding.PEM)

        tls_cert_pem = self.enclave.sign_certificate(tls_csr_pem, "client")

        # Save TLS cert and key
        tls_dir = service_dir / "tls"
        tls_dir.mkdir(parents=True, exist_ok=True)

        (tls_dir / "server.crt").write_bytes(tls_cert_pem)
        tls_key_pem = tls_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption()
        )
        (tls_dir / "server.key").write_bytes(tls_key_pem)

        # Copy Root CA
        root_ca_pem = self.root_ca_cert.public_bytes(serialization.Encoding.PEM)
        (tls_dir / "ca.crt").write_bytes(root_ca_pem)

        print(f"     ✓ Service TLS cert saved to: {tls_dir}")
        print(f"\n  ✓ Service certificates generated for {service_name}")

    def generate_all_certificates(self):
        """Generate all Fabric certificates"""
        print("\n" + "=" * 60)
        print("GENERATING ALL FABRIC CERTIFICATES")
        print("=" * 60)

        # Create base directories
        CRYPTO_DIR.mkdir(parents=True, exist_ok=True)

        # Generate orderer certificates
        self.generate_orderer_certs("hot")
        self.generate_orderer_certs("cold")

        # Generate peer certificates for all organizations
        orgs = [
            ("LawEnforcementMSP", "lawenforcement.com", "hot"),
            ("ForensicLabMSP", "forensiclab.com", "hot"),
            ("ArchiveMSP", "archive.com", "cold"),
        ]

        for org_name, domain, chain_type in orgs:
            self.generate_peer_certs(org_name, domain, chain_type)

        # Generate service certificates for IPFS
        self.generate_service_certs("ipfs", "ipfs-node")

        print("\n" + "=" * 60)
        print("CERTIFICATE GENERATION COMPLETE")
        print("=" * 60)
        print(f"\n  All certificates signed by enclave Root CA")
        print(f"  Certificates saved to: {CRYPTO_DIR}")
        print(f"  Orderer signing keys stored in enclave")
        print(f"  Service TLS certificates generated for: IPFS")
        print()

def main():
    """Main function"""
    try:
        generator = FabricCertGenerator()
        generator.generate_all_certificates()

        print("\n" + "=" * 60)
        print("NEXT STEPS")
        print("=" * 60)
        print("  1. Verify certificates: ./verify_certs.sh")
        print("  2. Update Fabric configs with new certificate paths")
        print("  3. Start Fabric networks")
        print()

        return 0

    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    sys.exit(main())
