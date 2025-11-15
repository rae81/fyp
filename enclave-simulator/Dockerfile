FROM python:3.11-slim

LABEL description="Software Enclave Simulator for DFIR Blockchain"
LABEL maintainer="Claude AI"

# Install dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Create enclave user
RUN useradd -m -u 1000 enclave

# Create directories
RUN mkdir -p /enclave-data && chown enclave:enclave /enclave-data
RUN mkdir -p /app && chown enclave:enclave /app

# Set working directory
WORKDIR /app

# Copy requirements
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy enclave service
COPY enclave_sgx.py .
COPY enclave_api.py .

# Switch to enclave user
USER enclave

# Expose port
EXPOSE 5001

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:5001/health')"

# Run enclave service
CMD ["python", "enclave_api.py"]
