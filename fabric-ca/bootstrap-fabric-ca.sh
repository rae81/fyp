#!/bin/bash
#
# Bootstrap Fabric CA Servers for all organizations
# Each CA server gets an intermediate cert from the Enclave Root CA
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENCLAVE_URL="${ENCLAVE_URL:-http://enclave:5001}"

echo "================================================================"
echo "Bootstrapping Fabric CA Servers with Enclave Root CA"
echo "================================================================"

# Wait for enclave to be ready
echo "Waiting for enclave service..."
until curl -sf "$ENCLAVE_URL/health" > /dev/null; do
    echo "  Enclave not ready yet, waiting..."
    sleep 2
done
echo "✓ Enclave service is ready"

# Check if Root CA is initialized
ENCLAVE_INFO=$(curl -s "$ENCLAVE_URL/enclave/info")
ROOT_CA_INIT=$(echo "$ENCLAVE_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin)['root_ca_initialized'])")

if [ "$ROOT_CA_INIT" != "True" ]; then
    echo "Root CA not initialized in enclave. Initializing now..."
    curl -X POST "$ENCLAVE_URL/ca/init"
    sleep 2
fi

# Download Root CA certificate
echo "Downloading Root CA certificate..."
curl -s "$ENCLAVE_URL/ca/certificate" > "$PROJECT_ROOT/fabric-ca/root-ca.pem"
echo "✓ Root CA certificate downloaded"

# Organizations to create CA servers for
ORGS=(
    "lawenforcement:hot:7054"
    "forensiclab:hot:8054"
    "auditor:cold:9054"
    "court:shared:10054"
    "orderer-hot:hot:11054"
    "orderer-cold:cold:12054"
)

for ORG_SPEC in "${ORGS[@]}"; do
    IFS=':' read -r ORG_NAME CHAIN PORT <<< "$ORG_SPEC"

    echo ""
    echo "Setting up Fabric CA for: $ORG_NAME ($CHAIN chain)"

    CA_DIR="$PROJECT_ROOT/fabric-ca/$ORG_NAME"
    mkdir -p "$CA_DIR"

    # Generate CA server private key using ECDSA P-256 in PKCS#8 format
    # Fabric CA's BCCSP fully supports ECDSA and requires PKCS#8 encoding
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$CA_DIR/ca-key.pem"

    # Create CSR for intermediate CA with SANs including localhost
    openssl req -new -key "$CA_DIR/ca-key.pem" \
        -out "$CA_DIR/ca-csr.pem" \
        -subj "/C=US/ST=California/L=San Francisco/O=DFIR Blockchain/OU=${ORG_NAME^^}MSP/CN=ca.${ORG_NAME}.coc.com" \
        -addext "subjectAltName=DNS:ca.${ORG_NAME}.coc.com,DNS:ca-${ORG_NAME},DNS:localhost"

    # Get CSR content
    CSR_CONTENT=$(cat "$CA_DIR/ca-csr.pem")

    # Sign with enclave Root CA
    echo "  Requesting certificate from enclave..."
    CERT_RESPONSE=$(curl -s -X POST "$ENCLAVE_URL/ca/sign" \
        -H "Content-Type: application/json" \
        -d "{\"csr\": $(echo "$CSR_CONTENT" | jq -Rs .), \"type\": \"intermediate-ca\", \"validity_days\": 1825}")

    # Extract certificate
    echo "$CERT_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['certificate'])" > "$CA_DIR/ca-cert.pem"

    # Create CA chain (intermediate + root)
    cat "$CA_DIR/ca-cert.pem" "$PROJECT_ROOT/fabric-ca/root-ca.pem" > "$CA_DIR/ca-chain.pem"

    # Create fabric-ca-server config
    cat > "$CA_DIR/fabric-ca-server-config.yaml" <<EOF
version: 1.5.5

port: $PORT

debug: false

crlsizelimit: 512000

tls:
  enabled: true
  certfile: ca-cert.pem
  keyfile: ca-key.pem

ca:
  name: ca-${ORG_NAME}
  keyfile: ca-key.pem
  certfile: ca-cert.pem
  chainfile: ca-chain.pem

csr:
  cn: ca.${ORG_NAME}.coc.com
  names:
    - C: US
      ST: California
      L: San Francisco
      O: DFIR Blockchain
      OU: ${ORG_NAME^^}MSP
  hosts:
    - ca.${ORG_NAME}.coc.com
    - ca-${ORG_NAME}
    - localhost
  ca:
    expiry: 131400h
    pathlength: 1

registry:
  maxenrollments: -1
  identities:
    - name: admin
      pass: adminpw
      type: client
      affiliation: ""
      attrs:
        hf.Registrar.Roles: "*"
        hf.Registrar.DelegateRoles: "*"
        hf.Revoker: true
        hf.IntermediateCA: true
        hf.GenCRL: true
        hf.Registrar.Attributes: "*"
        hf.AffiliationMgr: true

db:
  type: sqlite3
  datasource: fabric-ca-server.db
  tls:
    enabled: false

affiliations:
  ${ORG_NAME}:
    - department1
    - department2

signing:
  default:
    usage:
      - digital signature
    expiry: 8760h
  profiles:
    ca:
      usage:
        - cert sign
        - crl sign
      expiry: 43800h
      caconstraint:
        isca: true
        maxpathlen: 0
    tls:
      usage:
        - signing
        - key encipherment
        - server auth
        - client auth
        - key agreement
      expiry: 8760h

EOF

    echo "✓ CA server configured for $ORG_NAME (port $PORT)"
done

echo ""
echo "================================================================"
echo "✓ All Fabric CA servers bootstrapped successfully"
echo "================================================================"
echo ""
echo "Root CA: $PROJECT_ROOT/fabric-ca/root-ca.pem"
echo "Intermediate CAs created for all organizations"
echo ""
echo "Next: Start fabric-ca servers with docker-compose"
