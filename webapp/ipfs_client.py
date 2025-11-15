"""
Secure IPFS Client with mTLS using Fabric CA certificates
Provides authenticated and encrypted access to IPFS API
"""

import requests
import os
from pathlib import Path

class SecureIPFSClient:
    """IPFS client that uses mTLS with Fabric CA certificates"""

    def __init__(self,
                 api_url="https://localhost:5443",
                 gateway_url="https://localhost:8443",
                 cert_path=None,
                 key_path=None,
                 ca_path=None):
        """
        Initialize secure IPFS client

        Args:
            api_url: IPFS API URL (with TLS)
            gateway_url: IPFS Gateway URL (with TLS)
            cert_path: Path to client certificate
            key_path: Path to client private key
            ca_path: Path to CA certificate for server verification
        """
        self.api_url = api_url
        self.gateway_url = gateway_url

        # Determine certificate paths
        if cert_path is None or key_path is None or ca_path is None:
            # Use webapp's Fabric certificates
            webapp_dir = Path(__file__).parent.parent
            msp_dir = webapp_dir / "organizations" / "peerOrganizations" / "lawenforcement.com" / "users" / "Admin@lawenforcement.com" / "msp"

            cert_path = cert_path or (msp_dir / "signcerts" / "cert.pem")
            ca_path = ca_path or (msp_dir / "cacerts" / "ca-cert.pem")

            # Find the SKI-based key file
            keystore = msp_dir / "keystore"
            if keystore.exists():
                key_files = list(keystore.glob("*_sk"))
                if key_files:
                    key_path = key_path or key_files[0]

        self.cert_path = str(cert_path) if cert_path else None
        self.key_path = str(key_path) if key_path else None
        self.ca_path = str(ca_path) if ca_path else None

        # Verify certificates exist
        if self.cert_path and not os.path.exists(self.cert_path):
            raise FileNotFoundError(f"Client certificate not found: {self.cert_path}")
        if self.key_path and not os.path.exists(self.key_path):
            raise FileNotFoundError(f"Client key not found: {self.key_path}")
        if self.ca_path and not os.path.exists(self.ca_path):
            raise FileNotFoundError(f"CA certificate not found: {self.ca_path}")

    def _get_session(self):
        """Create requests session with mTLS configuration"""
        session = requests.Session()

        # Configure client certificate and key
        if self.cert_path and self.key_path:
            session.cert = (self.cert_path, self.key_path)

        # Configure CA for server verification
        if self.ca_path:
            session.verify = self.ca_path
        else:
            session.verify = False  # Fallback (not recommended for production)

        return session

    def add(self, file_path):
        """
        Add a file to IPFS

        Args:
            file_path: Path to file to upload

        Returns:
            dict: Response from IPFS with 'Hash', 'Name', 'Size'
        """
        session = self._get_session()

        with open(file_path, 'rb') as f:
            files = {'file': f}
            response = session.post(
                f"{self.api_url}/api/v0/add",
                files=files,
                timeout=60
            )
            response.raise_for_status()
            return response.json()

    def cat(self, ipfs_hash):
        """
        Retrieve file content from IPFS

        Args:
            ipfs_hash: IPFS hash of the file

        Returns:
            bytes: File content
        """
        session = self._get_session()
        response = session.post(
            f"{self.api_url}/api/v0/cat",
            params={'arg': ipfs_hash},
            timeout=60
        )
        response.raise_for_status()
        return response.content

    def get(self, ipfs_hash):
        """
        Download file from IPFS gateway

        Args:
            ipfs_hash: IPFS hash of the file

        Returns:
            bytes: File content
        """
        session = self._get_session()
        response = session.get(
            f"{self.gateway_url}/ipfs/{ipfs_hash}",
            timeout=60
        )
        response.raise_for_status()
        return response.content

    def version(self):
        """
        Get IPFS version (for health check)

        Returns:
            dict: IPFS version info
        """
        session = self._get_session()
        response = session.post(
            f"{self.api_url}/api/v0/version",
            timeout=5
        )
        response.raise_for_status()
        return response.json()

    def pin_add(self, ipfs_hash):
        """
        Pin a hash to ensure it's not garbage collected

        Args:
            ipfs_hash: IPFS hash to pin

        Returns:
            dict: Response from IPFS
        """
        session = self._get_session()
        response = session.post(
            f"{self.api_url}/api/v0/pin/add",
            params={'arg': ipfs_hash},
            timeout=30
        )
        response.raise_for_status()
        return response.json()


# Fallback to insecure HTTP connection if mTLS not available
class InsecureIPFSClient:
    """Fallback IPFS client without mTLS (for backward compatibility)"""

    def __init__(self, api_url="http://localhost:5001", gateway_url="http://localhost:8080"):
        self.api_url = api_url
        self.gateway_url = gateway_url

    def add(self, file_path):
        with open(file_path, 'rb') as f:
            files = {'file': f}
            response = requests.post(f"{self.api_url}/api/v0/add", files=files, timeout=60)
            response.raise_for_status()
            return response.json()

    def cat(self, ipfs_hash):
        response = requests.post(f"{self.api_url}/api/v0/cat", params={'arg': ipfs_hash}, timeout=60)
        response.raise_for_status()
        return response.content

    def get(self, ipfs_hash):
        response = requests.get(f"{self.gateway_url}/ipfs/{ipfs_hash}", timeout=60)
        response.raise_for_status()
        return response.content

    def version(self):
        response = requests.post(f"{self.api_url}/api/v0/version", timeout=5)
        response.raise_for_status()
        return response.json()

    def pin_add(self, ipfs_hash):
        response = requests.post(f"{self.api_url}/api/v0/pin/add", params={'arg': ipfs_hash}, timeout=30)
        response.raise_for_status()
        return response.json()


def get_ipfs_client(use_mtls=True):
    """
    Factory function to get appropriate IPFS client

    Args:
        use_mtls: Whether to use mTLS (default True)

    Returns:
        IPFSClient instance
    """
    try:
        if use_mtls:
            return SecureIPFSClient()
        else:
            return InsecureIPFSClient()
    except Exception as e:
        print(f"Warning: Failed to create secure IPFS client: {e}")
        print("Falling back to insecure HTTP connection")
        return InsecureIPFSClient()
