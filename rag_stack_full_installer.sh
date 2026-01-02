#!/bin/bash
# RAG Stack with Full Observability - One-Shot Installer v6.0
# December 2025 - Latest versions with complete observability stack
# Creates all configuration files and validates before deployment

set -e

# =============================================================================
# CONFIGURATION CONSTANTS
# =============================================================================
# Password/key lengths
PASSWORD_LENGTH=32
SECRET_KEY_LENGTH=64

# Service startup wait times (seconds)
WAIT_DATABASE_INIT=90
WAIT_DATABASE_EXTRA=30
WAIT_APPLICATION=30
WAIT_OBSERVABILITY=30
WAIT_QUICK_MINIMUM=10

# Password minimum length for validation
PASSWORD_MIN_LENGTH=24

# Default RAM estimates (GB)
RAM_BASE=5
RAM_REDIS=1
RAM_CHATWOOT=2
RAM_OBSERVABILITY_LITE=2
RAM_OBSERVABILITY_FULL=6
RAM_PER_WORKER=1

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Validation flags
VALIDATION_PASSED=true
VALIDATION_ERRORS=()

# Create log file
LOGFILE="rag_installer_$(date +%s).log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"
}

echo_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log "INFO: $1"
}

echo_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log "SUCCESS: $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log "ERROR: $1"
}

echo_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log "WARNING: $1"
}

add_validation_error() {
    VALIDATION_PASSED=false
    VALIDATION_ERRORS+=("$1")
    echo_error "VALIDATION: $1"
}

# Cross-platform URL opener
open_url() {
    local url=$1
    if command -v xdg-open &> /dev/null; then
        xdg-open "$url" 2>/dev/null &
    elif command -v open &> /dev/null; then
        open "$url"
    elif command -v start &> /dev/null; then
        start "$url"
    else
        echo_warning "Could not open browser. Please visit: $url"
    fi
}

find_available_port() {
    local preferred_port=$1
    local port=$preferred_port
    
    while lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; do
        port=$((port + 1))
        if [ $port -gt 65535 ]; then
            echo_error "No available ports found starting from $preferred_port"
            exit 1
        fi
    done
    
    echo $port
}

wait_with_progress() {
    local seconds=$1
    local message=$2
    local service=$3
    
    # Reduce wait times in quick start mode
    if [ "$QUICK_START" = true ]; then
        seconds=$((seconds / 3))
        if [ $seconds -lt $WAIT_QUICK_MINIMUM ]; then
            seconds=$WAIT_QUICK_MINIMUM
        fi
    fi
    
    echo "$message (Press Ctrl+C to skip)"
    
    # Set up trap to catch Ctrl+C
    trap 'echo ""; echo_info "Skipping wait..."; return 0' INT
    
    for ((i=1; i<=seconds; i++)); do
        printf "\r[%3d/%3d] " $i $seconds
        
        # Print progress bar
        local progress=$((i * 40 / seconds))
        printf "["
        for ((j=0; j<progress; j++)); do printf "="; done
        if [ $progress -lt 40 ]; then printf ">"; fi
        for ((j=progress+1; j<40; j++)); do printf " "; done
        printf "]"
        
        # Check service health if provided
        if [ -n "$service" ]; then
            case $service in
                postgres)
                    if docker exec "${CLIENT_NAME_SAFE}-postgres" pg_isready -U postgres > /dev/null 2>&1; then
                        echo ""
                        echo_success "✓ PostgreSQL is ready!"
                        trap - INT
                        return 0
                    fi
                    ;;
                redis)
                    if docker exec "${CLIENT_NAME_SAFE}-redis" redis-cli --no-auth-warning -a "${REDIS_PASSWORD}" ping > /dev/null 2>&1; then
                        echo ""
                        echo_success "✓ Redis is ready!"
                        trap - INT
                        return 0
                    fi
                    ;;
            esac
        fi
        
        sleep 1
    done
    
    trap - INT
    echo ""
}

echo ""
echo "==============================================================================="
echo "   RAG Stack with Full Observability - One-Shot Installer v6.0"
echo "   Redis 8.4 | PostgreSQL 16 | N8N v2 | OpenTelemetry | Jaeger v2 | Loki v3.6"
echo ""
echo "   Usage: ./rag_stack_full_installer.sh [--quick|-q]"
echo "   Options:"
echo "     --quick, -q    Quick start mode (reduced wait times)"
echo "==============================================================================="
echo ""

log "Starting RAG Stack Installer with Full Observability"

# Check Docker
echo_info "Checking Docker installation..."
if ! command -v docker &> /dev/null; then
    echo_error "Docker not found. Please install Docker Desktop (https://www.docker.com/products/docker-desktop)."
    exit 1
fi

if ! docker info &> /dev/null 2>&1; then
    echo_error "Docker is not running. Please start Docker Desktop and try again."
    exit 1
fi

echo_success "Docker is ready"

# Detect docker compose command (prefer 'docker compose' over deprecated 'docker-compose')
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
    echo_info "Using: docker compose (modern)"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
    echo_warning "Using: docker-compose (deprecated, consider updating)"
else
    echo_error "Neither 'docker compose' nor 'docker-compose' found."
    exit 1
fi

# Get client information
echo ""
echo_info "Client Information"
echo ""

# Check for quick start flag
QUICK_START=false
if [ "$1" = "--quick" ] || [ "$1" = "-q" ]; then
    QUICK_START=true
    echo_info "Quick start mode enabled - minimal wait times"
    echo ""
fi

while true; do
    read -p "Client/Company name: " CLIENT_NAME
    if [ -n "$CLIENT_NAME" ]; then
        log "Client name: $CLIENT_NAME"
        break
    fi
    echo_warning "Please enter a client name."
done

# SSL Configuration
echo ""
echo "SSL Configuration:"
echo "1. Self-signed certificate (recommended for local development)"
echo "2. Let's Encrypt (requires public domain name)"
echo ""

while true; do
    read -p "Choose option (1 or 2) [1]: " SSL_CHOICE
    SSL_CHOICE=${SSL_CHOICE:-1}
    case $SSL_CHOICE in
        1)
            USE_SSL="self-signed"
            PROTOCOL="https"
            CLIENT_DOMAIN="localhost"
            log "SSL choice: Self-signed"
            break
            ;;
        2)
            USE_SSL="letsencrypt"
            PROTOCOL="https"
            echo ""
            while true; do
                read -p "Enter your domain name (e.g., yourdomain.com): " CLIENT_DOMAIN
                if [ -n "$CLIENT_DOMAIN" ]; then
                    break
                fi
            done
            echo ""
            while true; do
                read -p "Enter email for Let's Encrypt notifications: " LETSENCRYPT_EMAIL
                if [ -n "$LETSENCRYPT_EMAIL" ]; then
                    echo ""
                    read -p "Is '$LETSENCRYPT_EMAIL' correct? (y/n): " EMAIL_CONFIRM
                    if [ "$EMAIL_CONFIRM" = "y" ] || [ "$EMAIL_CONFIRM" = "Y" ]; then
                        log "SSL choice: Let's Encrypt for $CLIENT_DOMAIN with email $LETSENCRYPT_EMAIL"
                        break
                    fi
                fi
            done
            break
            ;;
        *)
            echo_warning "Invalid choice. Please enter 1 or 2."
            ;;
    esac
done

# Create safe client name
echo_info "Processing client name..."
CLIENT_NAME_SAFE=$(echo "$CLIENT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ._' '-' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
if [ -z "$CLIENT_NAME_SAFE" ]; then
    CLIENT_NAME_SAFE="default-client"
fi
log "Client name: '$CLIENT_NAME' -> Safe name: '$CLIENT_NAME_SAFE'"

INSTALL_DIR="$HOME/rag-stack-$CLIENT_NAME_SAFE"

# Display summary
echo ""
echo "Installation Summary:"
echo "====================="
echo "Client:       $CLIENT_NAME"
echo "Safe name:    $CLIENT_NAME_SAFE"
echo "Domain:       $CLIENT_DOMAIN"
echo "SSL:          $USE_SSL"
echo "Protocol:     $PROTOCOL"
if [ "$USE_SSL" = "letsencrypt" ]; then
    echo "LE Email:     $LETSENCRYPT_EMAIL"
fi
echo "Location:     $INSTALL_DIR"
echo ""
echo "Stack Components:"
echo "  - PostgreSQL 16 (with pgvector)"
echo "  - Redis 8.4"
echo "  - N8N v2.0 (workflow automation)"
echo "  - Chatwoot (customer support)"
echo "  - Qdrant (vector database)"
echo "  - OpenTelemetry Collector v0.142.0"
echo "  - Jaeger v2.13.0 (distributed tracing)"
echo "  - Loki v3.6.3 (log aggregation)"
echo "  - Grafana Alloy (log collector)"
echo "  - Prometheus (metrics)"
echo "  - Grafana (visualization)"
echo ""

read -p "Continue with installation? (y/n): " PROCEED
if [ "$PROCEED" != "y" ] && [ "$PROCEED" != "Y" ]; then
    echo_info "Installation cancelled."
    log "Installation cancelled by user"
    exit 0
fi

# Cleanup existing installation
echo ""
echo_info "Cleaning any existing installation..."
if [ -d "$INSTALL_DIR" ]; then
    cd "$INSTALL_DIR"
    $DOCKER_COMPOSE down -v 2>/dev/null || true
    # Remove only project-specific volumes (not all unused volumes system-wide)
    if [ -n "$CLIENT_NAME_SAFE" ]; then
        # Note: avoiding xargs -r as it's not available on macOS
        VOLUMES_TO_REMOVE=$(docker volume ls -q --filter "name=${CLIENT_NAME_SAFE}" 2>/dev/null)
        if [ -n "$VOLUMES_TO_REMOVE" ]; then
            echo "$VOLUMES_TO_REMOVE" | xargs docker volume rm 2>/dev/null || true
        fi
    fi
    echo_success "Cleaned existing installation"
fi

# Create fresh installation
echo_info "Setting up fresh installation..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Create directory structure
mkdir -p ssl prometheus grafana/provisioning/{dashboards,datasources} init-sql

# Optional Component Selection
echo ""
echo_info "Component Configuration"
echo ""

# N8N Queue Mode Selection
echo "⚡ N8N Execution Mode:"
echo ""
echo "  1. Single Instance (default)"
echo "     → Simple, good for most users, low resource usage"
echo "     → Best for: Development, low-medium workflow volume"
echo ""
echo "  2. Queue Mode with Workers"
echo "     → Scalable with Redis, handles high concurrent load"
echo "     → Best for: Production, high workflow volume, long-running tasks"
echo "     → Requires: Redis (adds ~100MB RAM + worker containers)"
echo ""
read -p "Select N8N mode (1/2) [1]: " N8N_MODE_CHOICE
N8N_MODE_CHOICE=${N8N_MODE_CHOICE:-1}

if [ "$N8N_MODE_CHOICE" = "2" ]; then
    N8N_QUEUE_MODE="true"
    echo_info "✓ Queue Mode selected"
    read -p "Number of worker containers (1-5) [2]: " N8N_WORKERS
    N8N_WORKERS=${N8N_WORKERS:-2}
    echo_info "Will deploy: 1 main + ${N8N_WORKERS} worker containers"
else
    N8N_QUEUE_MODE="false"
    N8N_WORKERS=0
    echo_info "✓ Single Instance selected"
fi

# Customer Support Pack
echo ""
echo "📦 Customer Support (Optional):"
echo ""
echo "  Chatwoot - Multi-channel customer support platform"
echo "  → Live chat, email, social media, ticketing"
echo "  → Requires: Redis (adds ~150MB RAM)"
echo ""
read -p "Install Chatwoot? (y/n) [n]: " INSTALL_CHATWOOT
INSTALL_CHATWOOT=${INSTALL_CHATWOOT:-n}
# Normalize to lowercase for consistent checking throughout script
INSTALL_CHATWOOT=$(echo "$INSTALL_CHATWOOT" | tr '[:upper:]' '[:lower:]')

if [ "$INSTALL_CHATWOOT" = "y" ]; then
    echo_info "✓ Chatwoot will be installed"
fi

# Determine if Redis is needed
INSTALL_REDIS="false"
REDIS_REASON=""
if [ "$N8N_QUEUE_MODE" = "true" ] && [ "$INSTALL_CHATWOOT" = "y" ]; then
    INSTALL_REDIS="true"
    REDIS_REASON="N8N Queue Mode + Chatwoot"
elif [ "$N8N_QUEUE_MODE" = "true" ]; then
    INSTALL_REDIS="true"
    REDIS_REASON="N8N Queue Mode"
elif [ "$INSTALL_CHATWOOT" = "y" ]; then
    INSTALL_REDIS="true"
    REDIS_REASON="Chatwoot"
fi

if [ "$INSTALL_REDIS" = "true" ]; then
    echo ""
    echo_info "✓ Redis will be installed (required by: $REDIS_REASON)"
fi

# Observability Packs
echo ""
echo "📊 Observability (Optional):"
echo ""
echo "  1. None"
echo "     → No monitoring, minimal resource usage"
echo ""
echo "  2. Lite - Metrics & Dashboards"
echo "     → Prometheus + Grafana for basic monitoring"
echo "     → Adds ~2GB RAM"
echo ""
echo "  3. Full - Complete Observability"
echo "     → Adds: Distributed tracing (Jaeger), Log aggregation (Loki)"
echo "     → Adds ~6GB RAM, best for production debugging"
echo ""
read -p "Select observability pack (1/2/3) [1]: " OBSERVABILITY_CHOICE
OBSERVABILITY_CHOICE=${OBSERVABILITY_CHOICE:-1}

case $OBSERVABILITY_CHOICE in
    1)
        INSTALL_OBSERVABILITY="none"
        echo_info "✓ No observability (minimal setup)"
        ;;
    2)
        INSTALL_OBSERVABILITY="lite"
        echo_info "✓ Lite observability (Prometheus + Grafana)"
        ;;
    3)
        INSTALL_OBSERVABILITY="full"
        echo_info "✓ Full observability (complete stack)"
        ;;
    *)
        echo_warning "Invalid choice, defaulting to None"
        INSTALL_OBSERVABILITY="none"
        ;;
esac

# Summary
echo ""
echo "==============================================================================="
echo "   Installation Summary"
echo "==============================================================================="
echo ""
echo "Base Stack:"
echo "  • PostgreSQL 16 (database)"
echo "  • N8N v2 (workflow automation) - ${N8N_QUEUE_MODE}" | sed 's/true/Queue Mode/' | sed 's/false/Single Instance/'
echo "  • Qdrant (vector database)"

if [ "$INSTALL_REDIS" = "true" ]; then
    echo "  • Redis 8.4 (for: $REDIS_REASON)"
fi

if [ "$INSTALL_CHATWOOT" = "y" ]; then
    echo ""
    echo "Optional:"
    echo "  • Chatwoot (customer support)"
fi

if [ "$INSTALL_OBSERVABILITY" != "none" ]; then
    echo ""
    echo "Observability:"
    if [ "$INSTALL_OBSERVABILITY" = "lite" ]; then
        echo "  • Prometheus (metrics)"
        echo "  • Grafana (dashboards)"
    else
        echo "  • Prometheus + Grafana + Jaeger + Loki + OpenTelemetry"
    fi
fi

echo ""
echo "Estimated RAM: " 
if [ "$N8N_QUEUE_MODE" = "true" ]; then
    RAM=$((RAM_BASE + N8N_WORKERS * RAM_PER_WORKER))
else
    RAM=$RAM_BASE
fi
if [ "$INSTALL_REDIS" = "true" ]; then
    RAM=$((RAM + RAM_REDIS))
fi
if [ "$INSTALL_CHATWOOT" = "y" ]; then
    RAM=$((RAM + RAM_CHATWOOT))
fi
if [ "$INSTALL_OBSERVABILITY" = "lite" ]; then
    RAM=$((RAM + RAM_OBSERVABILITY_LITE))
elif [ "$INSTALL_OBSERVABILITY" = "full" ]; then
    RAM=$((RAM + RAM_OBSERVABILITY_FULL))
fi
echo "  ~${RAM}GB"
echo ""
read -p "Proceed with installation? (y/n) [y]: " PROCEED
PROCEED=${PROCEED:-y}

if [ "$PROCEED" != "y" ] && [ "$PROCEED" != "Y" ]; then
    echo_error "Installation cancelled"
    exit 0
fi

log "User selections: N8N_Queue=$N8N_QUEUE_MODE, Workers=$N8N_WORKERS, Redis=$INSTALL_REDIS ($REDIS_REASON), Chatwoot=$INSTALL_CHATWOOT, Observability=$INSTALL_OBSERVABILITY, Estimated_RAM=${RAM}GB"

# Generate cryptographically secure passwords
echo_info "Generating cryptographically secure passwords..."
POSTGRES_PASS=$(openssl rand -base64 ${PASSWORD_LENGTH} | tr -d '/+=' | cut -c1-${PASSWORD_LENGTH})
POSTGRES_N8N_PASS=$(openssl rand -base64 ${PASSWORD_LENGTH} | tr -d '/+=' | cut -c1-${PASSWORD_LENGTH})
POSTGRES_CHATWOOT_PASS=$(openssl rand -base64 ${PASSWORD_LENGTH} | tr -d '/+=' | cut -c1-${PASSWORD_LENGTH})
REDIS_PASS=$(openssl rand -base64 ${PASSWORD_LENGTH} | tr -d '/+=' | cut -c1-${PASSWORD_LENGTH})
GRAFANA_PASS=$(openssl rand -base64 ${PASSWORD_LENGTH} | tr -d '/+=' | cut -c1-${PASSWORD_LENGTH})
CHATWOOT_SECRET=$(openssl rand -base64 ${SECRET_KEY_LENGTH} | tr -d '/+=' | cut -c1-${SECRET_KEY_LENGTH})
N8N_ENCRYPTION_KEY=$(openssl rand -base64 ${PASSWORD_LENGTH} | tr -d '/+=' | cut -c1-${PASSWORD_LENGTH})
log "Generated secure passwords (length: ${PASSWORD_LENGTH})"

# Allocate available ports
echo ""
echo_info "Allocating available ports..."
PORT_POSTGRES=$(find_available_port 5432)
PORT_REDIS=$(find_available_port 6379)
PORT_N8N=$(find_available_port 5678)
PORT_CHATWOOT=$(find_available_port 3000)
PORT_GRAFANA=$(find_available_port 3001)
PORT_QDRANT=$(find_available_port 6333)
PORT_PROMETHEUS=$(find_available_port 9090)
PORT_LOKI=$(find_available_port 3100)
PORT_JAEGER=$(find_available_port 16686)
PORT_OTEL_GRPC=$(find_available_port 4317)
PORT_OTEL_HTTP=$(find_available_port 4318)
PORT_OTEL_METRICS=$(find_available_port 8888)
PORT_ALLOY=$(find_available_port 12345)

echo_success "Allocated ports:"
echo "  PostgreSQL: $PORT_POSTGRES"
echo "  Redis: $PORT_REDIS"
echo "  N8N: $PORT_N8N"
echo "  Chatwoot: $PORT_CHATWOOT"
echo "  Grafana: $PORT_GRAFANA"
echo "  Qdrant: $PORT_QDRANT"
echo "  Prometheus: $PORT_PROMETHEUS"
echo "  Loki: $PORT_LOKI"
echo "  Jaeger: $PORT_JAEGER"
echo "  OTel gRPC: $PORT_OTEL_GRPC"
echo "  OTel HTTP: $PORT_OTEL_HTTP"
log "Port allocation complete"

# Generate SSL certificates if needed
if [ "$USE_SSL" = "self-signed" ]; then
    echo_info "Generating enhanced self-signed SSL certificates (4096-bit RSA)..."
    
    cat > ssl/openssl.cnf << EOF
[req]
default_bits = 4096
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=US
ST=State
L=City
O=${CLIENT_NAME}
CN=${CLIENT_DOMAIN}

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${CLIENT_DOMAIN}
DNS.2 = localhost
DNS.3 = *.localhost
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

    docker run --rm -v "$PWD/ssl:/certs" alpine/openssl req \
        -x509 -nodes -days 1095 -newkey rsa:4096 \
        -keyout /certs/privkey.pem -out /certs/fullchain.pem \
        -config /certs/openssl.cnf -extensions v3_req 2>/dev/null
    
    docker run --rm -v "$PWD/ssl:/certs" alpine chmod 644 /certs/privkey.pem /certs/fullchain.pem
    rm ssl/openssl.cnf
    
    if [ ! -f "ssl/privkey.pem" ]; then
        add_validation_error "Failed to generate SSL certificate"
    else
        echo_success "Enhanced SSL certificate generated (4096-bit, with SANs)"
        log "Self-signed SSL certificate generated"
    fi
fi

# Generate Let's Encrypt certificates if selected
if [ "$USE_SSL" = "letsencrypt" ]; then
    echo_info "Obtaining Let's Encrypt certificate for ${CLIENT_DOMAIN}..."
    echo_warning "Ensure port 80 is open and ${CLIENT_DOMAIN} points to this server"
    echo ""
    
    # Create letsencrypt directory
    mkdir -p letsencrypt
    
    # Run certbot in standalone mode
    docker run --rm -it \
        -v "$PWD/ssl:/etc/letsencrypt/live/${CLIENT_DOMAIN}" \
        -v "$PWD/letsencrypt:/etc/letsencrypt" \
        -p 80:80 \
        certbot/certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email "${LETSENCRYPT_EMAIL}" \
        -d "${CLIENT_DOMAIN}"
    
    # Copy certificates to ssl directory with expected names
    if [ -f "letsencrypt/live/${CLIENT_DOMAIN}/privkey.pem" ]; then
        cp "letsencrypt/live/${CLIENT_DOMAIN}/privkey.pem" ssl/privkey.pem
        cp "letsencrypt/live/${CLIENT_DOMAIN}/fullchain.pem" ssl/fullchain.pem
        chmod 644 ssl/privkey.pem ssl/fullchain.pem
        echo_success "Let's Encrypt certificate obtained for ${CLIENT_DOMAIN}"
        log "Let's Encrypt SSL certificate generated"
        
        # Create renewal script
        cat > renew-ssl.sh << 'RENEWEOF'
#!/bin/bash
cd "$(dirname "$0")"
source .env

echo "Renewing Let's Encrypt certificate..."

# Stop services that use port 80/443
docker compose stop n8n 2>/dev/null || true

# Renew certificate
docker run --rm \
    -v "$PWD/letsencrypt:/etc/letsencrypt" \
    -p 80:80 \
    certbot/certbot renew

# Copy renewed certs
if [ -f "letsencrypt/live/${DOMAIN}/privkey.pem" ]; then
    cp "letsencrypt/live/${DOMAIN}/privkey.pem" ssl/privkey.pem
    cp "letsencrypt/live/${DOMAIN}/fullchain.pem" ssl/fullchain.pem
    chmod 644 ssl/privkey.pem ssl/fullchain.pem
    echo "Certificate renewed successfully"
fi

# Restart services
docker compose start n8n
echo "Services restarted"
RENEWEOF
        chmod +x renew-ssl.sh
        echo_info "Created renew-ssl.sh for certificate renewal"
    else
        echo_error "Failed to obtain Let's Encrypt certificate"
        echo_warning "Falling back to self-signed certificate..."
        USE_SSL="self-signed"
        
        # Generate self-signed as fallback
        cat > ssl/openssl.cnf << EOF
[req]
default_bits = 4096
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=US
ST=State
L=City
O=${CLIENT_NAME}
CN=${CLIENT_DOMAIN}

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${CLIENT_DOMAIN}
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF
        docker run --rm -v "$PWD/ssl:/certs" alpine/openssl req \
            -x509 -nodes -days 1095 -newkey rsa:4096 \
            -keyout /certs/privkey.pem -out /certs/fullchain.pem \
            -config /certs/openssl.cnf -extensions v3_req 2>/dev/null
        docker run --rm -v "$PWD/ssl:/certs" alpine chmod 644 /certs/privkey.pem /certs/fullchain.pem
        rm ssl/openssl.cnf
        echo_warning "Using self-signed certificate as fallback"
    fi
fi

# Create .env file
echo_info "Creating .env file..."
cat > .env << EOF
# RAG Stack Configuration for ${CLIENT_NAME}
# Generated: $(date)
CLIENT_NAME=${CLIENT_NAME}
CLIENT_NAME_SAFE=${CLIENT_NAME_SAFE}
DOMAIN=${CLIENT_DOMAIN}
USE_SSL=${USE_SSL}
PROTOCOL=${PROTOCOL}
$([ "$USE_SSL" = "letsencrypt" ] && echo "LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}")

# Database passwords (cryptographically secure)
POSTGRES_PASSWORD=${POSTGRES_PASS}
POSTGRES_N8N_PASSWORD=${POSTGRES_N8N_PASS}
POSTGRES_CHATWOOT_PASSWORD=${POSTGRES_CHATWOOT_PASS}
REDIS_PASSWORD=${REDIS_PASS}

# Application credentials
CHATWOOT_SECRET_KEY=${CHATWOOT_SECRET}
GRAFANA_USER=admin
GRAFANA_PASSWORD=${GRAFANA_PASS}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}

# Project settings
COMPOSE_PROJECT_NAME=rag-stack-${CLIENT_NAME_SAFE}

# Allocated Ports
PORT_POSTGRES=${PORT_POSTGRES}
PORT_REDIS=${PORT_REDIS}
PORT_N8N=${PORT_N8N}
PORT_CHATWOOT=${PORT_CHATWOOT}
PORT_GRAFANA=${PORT_GRAFANA}
PORT_QDRANT=${PORT_QDRANT}
PORT_PROMETHEUS=${PORT_PROMETHEUS}
PORT_LOKI=${PORT_LOKI}
PORT_JAEGER=${PORT_JAEGER}
PORT_OTEL_GRPC=${PORT_OTEL_GRPC}
PORT_OTEL_HTTP=${PORT_OTEL_HTTP}
PORT_OTEL_METRICS=${PORT_OTEL_METRICS}
PORT_ALLOY=${PORT_ALLOY}

# Optional Component Selections
INSTALL_REDIS=${INSTALL_REDIS}
INSTALL_CHATWOOT=${INSTALL_CHATWOOT}
INSTALL_OBSERVABILITY=${INSTALL_OBSERVABILITY}
N8N_QUEUE_MODE=${N8N_QUEUE_MODE}
N8N_WORKERS=${N8N_WORKERS}
EXECUTIONS_MODE=$([ "$N8N_QUEUE_MODE" = "true" ] && echo "queue" || echo "regular")
EOF

# Create .gitignore
cat > .gitignore << 'EOF'
# Sensitive files
.env
CREDENTIALS.txt
*.log

# SSL certificates
ssl/

# Data directories
postgres_data/
redis_data/
n8n_data/
chatwoot_data/
qdrant_data/
prometheus_data/
grafana_data/
jaeger_data/
loki_data/
alloy_data/

# macOS
.DS_Store
EOF

# Create SQL initialization
echo_info "Creating database initialization scripts..."
cat > init-sql/01-init.sql << EOF
-- Database initialization for ${CLIENT_NAME}
CREATE EXTENSION IF NOT EXISTS vector;

-- Create databases
SELECT 'CREATE DATABASE n8n' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'n8n')\gexec
SELECT 'CREATE DATABASE chatwoot' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'chatwoot')\gexec

-- Drop existing users if they exist
DROP USER IF EXISTS n8n_user;
DROP USER IF EXISTS chatwoot_user;

-- Create users
CREATE USER n8n_user WITH ENCRYPTED PASSWORD '${POSTGRES_N8N_PASS}';
CREATE USER chatwoot_user WITH SUPERUSER ENCRYPTED PASSWORD '${POSTGRES_CHATWOOT_PASS}';

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n_user;
GRANT ALL PRIVILEGES ON DATABASE chatwoot TO chatwoot_user;

-- N8N schema permissions
\c n8n
GRANT ALL ON SCHEMA public TO n8n_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO n8n_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO n8n_user;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO n8n_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO n8n_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO n8n_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO n8n_user;

-- Chatwoot schema permissions
\c chatwoot
GRANT ALL ON SCHEMA public TO chatwoot_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO chatwoot_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO chatwoot_user;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO chatwoot_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO chatwoot_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO chatwoot_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO chatwoot_user;

\c postgres
SELECT 'Database initialization completed' AS status;
EOF

# Create OpenTelemetry Collector configuration
echo_info "Creating OpenTelemetry Collector configuration..."
cat > otel-collector-config.yaml << 'OTELEOF'
# OpenTelemetry Collector Configuration v0.142.0

receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
        max_recv_msg_size_mib: 4
      http:
        endpoint: 0.0.0.0:4318
        cors:
          allowed_origins:
            - "http://*"
            - "https://*"

  prometheus:
    config:
      scrape_configs:
        - job_name: 'otel-collector'
          scrape_interval: 30s
          static_configs:
            - targets: ['localhost:8888']

processors:
  batch:
    timeout: 10s
    send_batch_size: 1024
    send_batch_max_size: 2048

  memory_limiter:
    check_interval: 1s
    limit_percentage: 75
    spike_limit_percentage: 25

  resource:
    attributes:
      - key: deployment.environment
        value: "production"
        action: insert

  attributes:
    actions:
      - key: http.user_agent
        action: delete

  filter:
    error_mode: ignore
    traces:
      span:
        - 'attributes["http.target"] == "/health"'
        - 'attributes["http.target"] == "/metrics"'

exporters:
  otlp/jaeger:
    endpoint: jaeger:4317
    tls:
      insecure: true
    compression: gzip
    retry_on_failure:
      enabled: true
      initial_interval: 5s
      max_interval: 30s
      max_elapsed_time: 300s

  otlphttp/loki:
    endpoint: http://loki:3100/otlp
    tls:
      insecure: true

  prometheus:
    endpoint: "0.0.0.0:8889"
    namespace: otel

  debug:
    verbosity: detailed
    sampling_initial: 5
    sampling_thereafter: 200

extensions:
  health_check:
    endpoint: 0.0.0.0:13133
  pprof:
    endpoint: localhost:1777
  zpages:
    endpoint: localhost:55679

service:
  extensions: [health_check, pprof, zpages]
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch, resource, attributes, filter]
      exporters: [otlp/jaeger]
    metrics:
      receivers: [otlp, prometheus]
      processors: [memory_limiter, batch, resource]
      exporters: [prometheus]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch, resource]
      exporters: [otlphttp/loki]
  telemetry:
    logs:
      level: info
    metrics:
      level: detailed
OTELEOF

# Create Loki configuration
echo_info "Creating Loki v3.6 configuration..."
cat > loki-config.yaml << 'LOKIEOF'
# Loki v3.6.3 Configuration

auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096
  log_level: info

distributor:
  ring:
    kvstore:
      store: inmemory

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s
  chunk_idle_period: 30m
  chunk_target_size: 1572864
  chunk_encoding: snappy
  max_chunk_age: 2h
  wal:
    enabled: true
    dir: /loki/wal
    flush_on_shutdown: true

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

storage_config:
  filesystem:
    directory: /loki/chunks
  tsdb_shipper:
    active_index_directory: /loki/tsdb-index
    cache_location: /loki/tsdb-cache

compactor:
  working_directory: /loki/compactor
  compaction_interval: 10m
  retention_enabled: true
  retention_delete_delay: 2h
  delete_request_store: filesystem

limits_config:
  ingestion_rate_mb: 10
  ingestion_burst_size_mb: 20
  max_streams_per_user: 10000
  max_query_length: 721h
  retention_period: 720h
  unordered_writes: true

ruler:
  storage:
    type: local
    local:
      directory: /loki/rules
  rule_path: /loki/rules-temp
  alertmanager_url: ""
  ring:
    kvstore:
      store: inmemory
  enable_api: false

common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory
LOKIEOF

# Create Grafana Alloy configuration
echo_info "Creating Grafana Alloy configuration..."
cat > alloy-config.alloy << 'ALLOYEOF'
logging {
  level  = "info"
  format = "logfmt"
}

discovery.docker "containers" {
  host = "unix:///var/run/docker.sock"
  refresh_interval = "5s"
}

discovery.relabel "docker_logs" {
  targets = discovery.docker.containers.targets
  
  rule {
    source_labels = ["__meta_docker_container_name"]
    target_label  = "container"
  }
  
  rule {
    source_labels = ["__meta_docker_container_id"]
    target_label  = "container_id"
  }
}

loki.source.docker "containers" {
  host    = "unix:///var/run/docker.sock"
  targets = discovery.relabel.docker_logs.output
  forward_to = [loki.process.add_metadata.receiver]
  relabel_rules = discovery.relabel.docker_logs.rules
}

loki.process "add_metadata" {
  stage.json {
    expressions = {
      level = "level",
    }
  }
  forward_to = [loki.write.endpoint.receiver]
}

loki.write "endpoint" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
    batch_wait = "1s"
    batch_size = "1MB"
  }
}
ALLOYEOF

# Create Prometheus configuration
echo_info "Creating Prometheus configuration..."
cat > prometheus/prometheus.yml << 'PROMEOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'n8n'
    static_configs:
      - targets: ['n8n:5678']
    metrics_path: '/metrics'
    scrape_interval: 30s

  - job_name: 'otel-collector'
    static_configs:
      - targets: ['otel-collector:8888']
    scrape_interval: 30s

  - job_name: 'grafana'
    static_configs:
      - targets: ['grafana:3000']
    scrape_interval: 30s

  - job_name: 'qdrant'
    static_configs:
      - targets: ['qdrant:6333']
    metrics_path: '/metrics'
    scrape_interval: 30s

  - job_name: 'loki'
    static_configs:
      - targets: ['loki:3100']
    scrape_interval: 30s

  - job_name: 'jaeger'
    static_configs:
      - targets: ['jaeger:8888']
    scrape_interval: 30s
PROMEOF

# Create Grafana datasources
echo_info "Creating Grafana datasources configuration..."
cat > grafana/provisioning/datasources/datasources.yml << GRAFANAEOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true

  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    jsonData:
      derivedFields:
        - datasourceUid: jaeger
          matcherRegex: "trace_id=(\\\\w+)"
          name: TraceID
          url: "\$\${__value.raw}"
    editable: true

  - name: Jaeger
    type: jaeger
    access: proxy
    url: http://jaeger:16686
    jsonData:
      tracesToLogsV2:
        datasourceUid: loki
      nodeGraph:
        enabled: true
    editable: true

  - name: PostgreSQL-N8N
    type: postgres
    url: postgres:5432
    database: n8n
    user: n8n_user
    secureJsonData:
      password: '${POSTGRES_N8N_PASS}'
    jsonData:
      sslmode: 'disable'

  - name: PostgreSQL-Chatwoot
    type: postgres
    url: postgres:5432
    database: chatwoot
    user: chatwoot_user
    secureJsonData:
      password: '${POSTGRES_CHATWOOT_PASS}'
    jsonData:
      sslmode: 'disable'
GRAFANAEOF

# Create docker-compose.yml
echo_info "Creating docker-compose.yml..."
# Generate docker-compose.yml with selected services
log "Generating docker-compose.yml with selected components"

cat > docker-compose.yml << 'DOCKEREOF'
services:
  postgres:
    image: pgvector/pgvector:pg16
    container_name: ${CLIENT_NAME_SAFE}-postgres
    ports:
      - "${PORT_POSTGRES}:5432"
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./init-sql:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 15
      start_period: 60s
    restart: unless-stopped
    networks:
      - rag-network
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G
        reservations:
          memory: 2G

  redis:
    image: redis:8.4-alpine
    container_name: ${CLIENT_NAME_SAFE}-redis
    ports:
      - "${PORT_REDIS}:6379"
    command: redis-server --requirepass ${REDIS_PASSWORD} --maxmemory 512mb --maxmemory-policy allkeys-lru
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "--no-auth-warning", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5
    restart: unless-stopped
    networks:
      - rag-network
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 1G
    profiles:
      - redis
DOCKEREOF

# Continue building docker-compose.yml with N8N service
cat >> docker-compose.yml << 'DOCKEREOF'

  n8n:
    image: n8nio/n8n:latest
    container_name: ${CLIENT_NAME_SAFE}-n8n
    ports:
      - "${PORT_N8N}:5678"
    environment:
      - N8N_HOST=${DOMAIN}
      - N8N_PROTOCOL=${PROTOCOL}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=${CLIENT_NAME_SAFE}-postgres
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n_user
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_N8N_PASSWORD}
      - WEBHOOK_URL=${PROTOCOL}://${DOMAIN}:${PORT_N8N}/
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_RUNNERS_ENABLED=true
      - N8N_DEFAULT_BINARY_DATA_MODE=filesystem
      - EXECUTIONS_MODE=${EXECUTIONS_MODE:-regular}
      - QUEUE_BULL_REDIS_HOST=${CLIENT_NAME_SAFE}-redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_PASSWORD=${REDIS_PASSWORD}
      - QUEUE_BULL_REDIS_DB=0
DOCKEREOF

# Add Prometheus metrics for N8N (when any observability is enabled)
if [ "$INSTALL_OBSERVABILITY" = "lite" ] || [ "$INSTALL_OBSERVABILITY" = "full" ]; then
    cat >> docker-compose.yml << 'DOCKEREOF'
      - N8N_METRICS=true
      - N8N_METRICS_INCLUDE_DEFAULT_METRICS=true
      - N8N_METRICS_INCLUDE_CACHE_METRICS=true
      - N8N_METRICS_INCLUDE_MESSAGE_EVENT_BUS_METRICS=true
DOCKEREOF
fi

# Add queue metrics for N8N (when queue mode is enabled)
if [ "$N8N_QUEUE_MODE" = "true" ]; then
    cat >> docker-compose.yml << 'DOCKEREOF'
      - N8N_METRICS_INCLUDE_QUEUE_METRICS=true
DOCKEREOF
fi

# Conditionally add OTel environment variables for N8N (only when full observability)
if [ "$INSTALL_OBSERVABILITY" = "full" ]; then
    cat >> docker-compose.yml << 'DOCKEREOF'
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://${CLIENT_NAME_SAFE}-otel-collector:4318
      - OTEL_SERVICE_NAME=n8n
DOCKEREOF
fi

# Add SSL configuration for N8N
if [ "$USE_SSL" = "self-signed" ] || [ "$USE_SSL" = "letsencrypt" ]; then
    cat >> docker-compose.yml << 'DOCKEREOF'
      - N8N_SSL_KEY=/home/node/ssl/privkey.pem
      - N8N_SSL_CERT=/home/node/ssl/fullchain.pem
DOCKEREOF
fi

# Continue N8N service definition with volumes
cat >> docker-compose.yml << 'DOCKEREOF'
    volumes:
      - n8n_data:/home/node/.n8n
      - n8n_files:/home/node/.n8n-files
DOCKEREOF

# Add SSL volume mount if SSL is enabled
if [ "$USE_SSL" = "self-signed" ] || [ "$USE_SSL" = "letsencrypt" ]; then
    cat >> docker-compose.yml << 'DOCKEREOF'
      - ./ssl:/home/node/ssl:ro
DOCKEREOF
fi

# Continue with depends_on
cat >> docker-compose.yml << 'DOCKEREOF'
    depends_on:
      postgres:
        condition: service_healthy
DOCKEREOF

# Conditionally add Redis dependency for N8N (when queue mode is enabled)
if [ "$N8N_QUEUE_MODE" = "true" ]; then
    cat >> docker-compose.yml << 'DOCKEREOF'
      redis:
        condition: service_healthy
DOCKEREOF
fi

# Continue N8N service definition
cat >> docker-compose.yml << 'DOCKEREOF'
    restart: unless-stopped
    networks:
      - rag-network
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G

  n8n-worker:
    image: n8nio/n8n:latest
    # Note: no container_name here to allow scaling with --scale
    command: worker
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=${CLIENT_NAME_SAFE}-postgres
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n_user
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_N8N_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=${CLIENT_NAME_SAFE}-redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_PASSWORD=${REDIS_PASSWORD}
      - QUEUE_BULL_REDIS_DB=0
    volumes:
      - n8n_data:/home/node/.n8n
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    restart: unless-stopped
    networks:
      - rag-network
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 1G
    profiles:
      - n8n-queue

  chatwoot:
    image: chatwoot/chatwoot:latest
    container_name: ${CLIENT_NAME_SAFE}-chatwoot
    command: ["sh", "-c", "bundle exec rails db:chatwoot_prepare && bundle exec rails server -b 0.0.0.0 -p 3000"]
    ports:
      - "${PORT_CHATWOOT}:3000"
    environment:
      - RAILS_ENV=production
      - SECRET_KEY_BASE=${CHATWOOT_SECRET_KEY}
      - POSTGRES_HOST=${CLIENT_NAME_SAFE}-postgres
      - POSTGRES_USERNAME=chatwoot_user
      - POSTGRES_PASSWORD=${POSTGRES_CHATWOOT_PASSWORD}
      - POSTGRES_DATABASE=chatwoot
      - REDIS_URL=redis://:${REDIS_PASSWORD}@${CLIENT_NAME_SAFE}-redis:6379/1
      - FRONTEND_URL=${PROTOCOL}://${DOMAIN}:3000
      - BRAND_NAME=${CLIENT_NAME}
    volumes:
      - chatwoot_data:/app/storage
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    restart: unless-stopped
    networks:
      - rag-network
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
    profiles:
      - chatwoot

  qdrant:
    image: qdrant/qdrant:latest
    container_name: ${CLIENT_NAME_SAFE}-qdrant
    ports:
      - "${PORT_QDRANT}:6333"
      - "6334:6334"
    volumes:
      - qdrant_data:/qdrant/storage
    restart: unless-stopped
    networks:
      - rag-network
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G

  otel-collector:
    image: otel/opentelemetry-collector-contrib:0.142.0
    container_name: ${CLIENT_NAME_SAFE}-otel-collector
    command: ["--config=/etc/otelcol-contrib/otel-collector-config.yaml"]
    ports:
      - "${PORT_OTEL_GRPC}:4317"
      - "${PORT_OTEL_HTTP}:4318"
      - "${PORT_OTEL_METRICS}:8888"
      - "8889:8889"
      - "13133:13133"
    volumes:
      - ./otel-collector-config.yaml:/etc/otelcol-contrib/otel-collector-config.yaml:ro
    restart: unless-stopped
    networks:
      - rag-network
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 1G

  jaeger:
    image: jaegertracing/jaeger:2.13.0
    container_name: ${CLIENT_NAME_SAFE}-jaeger
    ports:
      - "${PORT_JAEGER}:16686"
      - "4319:4317"
      - "4320:4318"
      - "8889:8888"
    environment:
      - COLLECTOR_OTLP_ENABLED=true
      - SPAN_STORAGE_TYPE=badger
      - BADGER_EPHEMERAL=false
      - BADGER_DIRECTORY_VALUE=/badger/data
      - BADGER_DIRECTORY_KEY=/badger/key
    volumes:
      - jaeger_data:/badger
    restart: unless-stopped
    networks:
      - rag-network
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 1G

  loki:
    image: grafana/loki:3.6.3
    container_name: ${CLIENT_NAME_SAFE}-loki
    ports:
      - "${PORT_LOKI}:3100"
    command: -config.file=/etc/loki/local-config.yaml
    volumes:
      - ./loki-config.yaml:/etc/loki/local-config.yaml:ro
      - loki_data:/loki
    restart: unless-stopped
    networks:
      - rag-network
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 1G

  alloy:
    image: grafana/alloy:latest
    container_name: ${CLIENT_NAME_SAFE}-alloy
    command:
      - run
      - --server.http.listen-addr=0.0.0.0:12345
      - --storage.path=/var/lib/alloy/data
      - /etc/alloy/config.alloy
    ports:
      - "${PORT_ALLOY}:12345"
    volumes:
      - ./alloy-config.alloy:/etc/alloy/config.alloy:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - alloy_data:/var/lib/alloy
    restart: unless-stopped
    networks:
      - rag-network
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M

  prometheus:
    image: prom/prometheus:latest
    container_name: ${CLIENT_NAME_SAFE}-prometheus
    ports:
      - "${PORT_PROMETHEUS}:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
    restart: unless-stopped
    networks:
      - rag-network
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 2G

  grafana:
    image: grafana/grafana:latest
    container_name: ${CLIENT_NAME_SAFE}-grafana
    ports:
      - "${PORT_GRAFANA}:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_USER}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
      - GF_SERVER_ROOT_URL=${PROTOCOL}://${DOMAIN}:3001/
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_FEATURE_TOGGLES_ENABLE=traceToMetrics
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
DOCKEREOF

# Conditionally add Grafana dependencies based on observability level
if [ "$INSTALL_OBSERVABILITY" = "full" ]; then
    cat >> docker-compose.yml << 'DOCKEREOF'
    depends_on:
      - prometheus
      - loki
      - jaeger
DOCKEREOF
elif [ "$INSTALL_OBSERVABILITY" = "lite" ]; then
    cat >> docker-compose.yml << 'DOCKEREOF'
    depends_on:
      - prometheus
DOCKEREOF
fi

# Continue Grafana service definition
cat >> docker-compose.yml << 'DOCKEREOF'
    restart: unless-stopped
    networks:
      - rag-network
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 1G

volumes:
  postgres_data:
    name: ${CLIENT_NAME_SAFE}-postgres-data
  redis_data:
    name: ${CLIENT_NAME_SAFE}-redis-data
  n8n_data:
    name: ${CLIENT_NAME_SAFE}-n8n-data
  n8n_files:
    name: ${CLIENT_NAME_SAFE}-n8n-files
  chatwoot_data:
    name: ${CLIENT_NAME_SAFE}-chatwoot-data
  qdrant_data:
    name: ${CLIENT_NAME_SAFE}-qdrant-data
  jaeger_data:
    name: ${CLIENT_NAME_SAFE}-jaeger-data
  loki_data:
    name: ${CLIENT_NAME_SAFE}-loki-data
  alloy_data:
    name: ${CLIENT_NAME_SAFE}-alloy-data
  prometheus_data:
    name: ${CLIENT_NAME_SAFE}-prometheus-data
  grafana_data:
    name: ${CLIENT_NAME_SAFE}-grafana-data

networks:
  rag-network:
    name: ${CLIENT_NAME_SAFE}-rag-network
    driver: bridge
DOCKEREOF

# Create management scripts
echo_info "Creating management scripts..."

cat > start.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}===============================================================================${NC}"
echo -e "${BLUE}   Starting RAG Stack${NC}"
echo -e "${BLUE}===============================================================================${NC}"
echo ""

# Load environment
if [ -f .env ]; then
    set -a; source .env; set +a
fi

# Detect docker compose command
if docker compose version &> /dev/null; then
    DC="docker compose"
elif command -v docker-compose &> /dev/null; then
    DC="docker-compose"
else
    echo "Error: docker compose not found"
    exit 1
fi

# Build profile flags
PROFILE_FLAGS=""
if [ "$INSTALL_REDIS" = "true" ]; then
    PROFILE_FLAGS="$PROFILE_FLAGS --profile redis"
fi
if [ "$N8N_QUEUE_MODE" = "true" ]; then
    PROFILE_FLAGS="$PROFILE_FLAGS --profile n8n-queue"
fi
if [ "$INSTALL_CHATWOOT" = "y" ]; then
    PROFILE_FLAGS="$PROFILE_FLAGS --profile chatwoot"
fi

echo -e "${BLUE}Stage 1: Starting databases...${NC}"
if [ "$INSTALL_REDIS" = "true" ]; then
    $DC $PROFILE_FLAGS up -d postgres redis
    echo "Waiting for PostgreSQL and Redis..."
else
    $DC $PROFILE_FLAGS up -d postgres
    echo "Waiting for PostgreSQL..."
fi

for i in {1..30}; do
    printf "\r[%2d/30] " $i
    if docker exec ${CLIENT_NAME_SAFE}-postgres pg_isready -U postgres > /dev/null 2>&1; then
        echo ""
        echo -e "${GREEN}✓ PostgreSQL is ready!${NC}"
        break
    fi
    sleep 1
done

if [ "$INSTALL_REDIS" = "true" ]; then
    if docker exec ${CLIENT_NAME_SAFE}-redis redis-cli -a ${REDIS_PASSWORD} ping > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Redis is ready!${NC}"
    fi
fi

echo ""
echo -e "${BLUE}Stage 2: Starting core applications...${NC}"
CORE_APPS="n8n qdrant"

# Start core apps with profiles
$DC $PROFILE_FLAGS up -d $CORE_APPS

# Scale workers if queue mode enabled
if [ "$N8N_QUEUE_MODE" = "true" ]; then
    echo "Starting ${N8N_WORKERS} N8N worker(s)..."
    $DC $PROFILE_FLAGS up -d --scale n8n-worker=${N8N_WORKERS} n8n-worker
fi

echo "Waiting 30 seconds for initialization..."
sleep 30

if [ "$INSTALL_OBSERVABILITY" != "none" ]; then
    echo ""
    if [ "$INSTALL_OBSERVABILITY" = "lite" ]; then
        echo -e "${BLUE}Stage 3: Starting observability (Lite)...${NC}"
        $DC $PROFILE_FLAGS up -d prometheus grafana
    elif [ "$INSTALL_OBSERVABILITY" = "full" ]; then
        echo -e "${BLUE}Stage 3: Starting observability (Full)...${NC}"
        $DC $PROFILE_FLAGS up -d otel-collector jaeger loki alloy prometheus grafana
    fi
    echo "Waiting 20 seconds..."
    sleep 20
fi

echo ""
echo -e "${GREEN}===============================================================================${NC}"
echo -e "${GREEN}   All services started!${NC}"
echo -e "${GREEN}===============================================================================${NC}"
echo ""
echo "Service URLs:"
echo "  N8N:        http://localhost:${PORT_N8N}"

if [ "$INSTALL_CHATWOOT" = "y" ]; then
    echo "  Chatwoot:   http://localhost:${PORT_CHATWOOT}"
fi

if [ "$INSTALL_OBSERVABILITY" != "none" ]; then
    echo "  Grafana:    http://localhost:${PORT_GRAFANA}"
    echo "  Prometheus: http://localhost:${PORT_PROMETHEUS}"
fi

if [ "$INSTALL_OBSERVABILITY" = "full" ]; then
    echo "  Jaeger:     http://localhost:${PORT_JAEGER}"
fi

echo ""
echo "Run './status.sh' to check service health"
EOF

cat > stop.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

# Colors
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${YELLOW}===============================================================================${NC}"
echo -e "${YELLOW}   Stopping RAG Stack${NC}"
echo -e "${YELLOW}===============================================================================${NC}"
echo ""

# Load environment
if [ -f .env ]; then
    set -a; source .env; set +a
fi

# Detect docker compose command
if docker compose version &> /dev/null; then
    DC="docker compose"
elif command -v docker-compose &> /dev/null; then
    DC="docker-compose"
else
    echo "Error: docker compose not found"
    exit 1
fi

echo "Stopping all services..."
$DC down

echo ""
echo -e "${GREEN}✓ All services stopped${NC}"
echo ""
echo "To remove volumes (WARNING: deletes all data):"
echo "  $DC down -v"
echo ""
echo "To start again:"
echo "  ./start.sh"
EOF

cat > status.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "==============================================================================="
echo "   RAG Stack Status Check"
echo "==============================================================================="
echo ""

# Load environment variables
if [ -f .env ]; then
    set -a; source .env; set +a
fi

# Detect docker compose command
if docker compose version &> /dev/null; then
    DC="docker compose"
elif command -v docker-compose &> /dev/null; then
    DC="docker-compose"
else
    echo "Error: docker compose not found"
    exit 1
fi

echo "=== Container Status ==="
$DC ps

echo ""
echo "=== Service Health ==="

# Check each service
check_service() {
    local name=$1
    local container=$2
    local check_cmd=$3
    
    if docker ps --filter "name=${container}" --filter "status=running" | grep -q "${container}"; then
        if [ -n "$check_cmd" ]; then
            if eval "$check_cmd" > /dev/null 2>&1; then
                echo -e "${GREEN}✓${NC} ${name}: Running and healthy"
            else
                echo -e "${YELLOW}⚠${NC} ${name}: Running but not responding"
            fi
        else
            echo -e "${GREEN}✓${NC} ${name}: Running"
        fi
    else
        echo -e "${RED}✗${NC} ${name}: Not running"
    fi
}

check_service "PostgreSQL" "${CLIENT_NAME_SAFE}-postgres" "docker exec ${CLIENT_NAME_SAFE}-postgres pg_isready -U postgres"
check_service "Redis" "${CLIENT_NAME_SAFE}-redis" "docker exec ${CLIENT_NAME_SAFE}-redis redis-cli --no-auth-warning -a ${REDIS_PASSWORD} ping"
check_service "N8N" "${CLIENT_NAME_SAFE}-n8n" "curl -f http://localhost:${PORT_N8N}/healthz"
check_service "Chatwoot" "${CLIENT_NAME_SAFE}-chatwoot"
check_service "Qdrant" "${CLIENT_NAME_SAFE}-qdrant" "curl -f http://localhost:${PORT_QDRANT}/healthz"
check_service "OTel Collector" "${CLIENT_NAME_SAFE}-otel-collector" "curl -f http://localhost:13133"
check_service "Jaeger" "${CLIENT_NAME_SAFE}-jaeger"
check_service "Loki" "${CLIENT_NAME_SAFE}-loki" "curl -f http://localhost:${PORT_LOKI}/ready"
check_service "Alloy" "${CLIENT_NAME_SAFE}-alloy"
check_service "Prometheus" "${CLIENT_NAME_SAFE}-prometheus" "curl -f http://localhost:${PORT_PROMETHEUS}/-/healthy"
check_service "Grafana" "${CLIENT_NAME_SAFE}-grafana" "curl -f http://localhost:${PORT_GRAFANA}/api/health"

echo ""
echo "=== Service URLs ==="
echo "Grafana:      http://localhost:${PORT_GRAFANA}"
echo "Jaeger:       http://localhost:${PORT_JAEGER}"
echo "Prometheus:   http://localhost:${PORT_PROMETHEUS}"
echo "N8N:          http://localhost:${PORT_N8N}"
echo "Chatwoot:     http://localhost:${PORT_CHATWOOT}"
echo "Qdrant:       http://localhost:${PORT_QDRANT}"

echo ""
echo "=== Quick Commands ==="
echo "View logs:       $DC logs -f [service]"
echo "Restart service: $DC restart [service]"
echo "Stop all:        ./stop.sh"
echo "Restart all:     ./restart.sh"

echo ""
read -p "Show recent logs? (y/n): " SHOW_LOGS
if [ "$SHOW_LOGS" = "y" ] || [ "$SHOW_LOGS" = "Y" ]; then
    echo ""
    echo "=== Recent Logs (last 10 lines per service) ==="
    for service in postgres redis n8n chatwoot qdrant otel-collector jaeger loki alloy prometheus grafana; do
        echo ""
        echo "--- $service ---"
        $DC logs --tail=10 $service 2>/dev/null || echo "No logs available"
    done
fi
EOF

cat > restart.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

# Detect docker compose command
if docker compose version &> /dev/null; then
    DC="docker compose"
elif command -v docker-compose &> /dev/null; then
    DC="docker-compose"
else
    echo "Error: docker compose not found"
    exit 1
fi

if [ -n "$1" ]; then
    echo -e "${BLUE}Restarting $1...${NC}"
    $DC restart $1
    echo -e "${GREEN}✓ $1 restarted${NC}"
else
    echo -e "${BLUE}Restarting all services...${NC}"
    $DC restart
    echo -e "${GREEN}✓ All services restarted${NC}"
fi
EOF

cat > logs.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

# Colors
BLUE='\033[0;34m'
NC='\033[0m'

# Detect docker compose command
if docker compose version &> /dev/null; then
    DC="docker compose"
elif command -v docker-compose &> /dev/null; then
    DC="docker-compose"
else
    echo "Error: docker compose not found"
    exit 1
fi

echo -e "${BLUE}===============================================================================${NC}"
echo -e "${BLUE}   RAG Stack Logs${NC}"
echo -e "${BLUE}===============================================================================${NC}"
echo ""

if [ -n "$1" ]; then
    # Show logs for specific service
    if [ "$2" = "-f" ] || [ "$2" = "--follow" ]; then
        echo "Following logs for $1 (Ctrl+C to exit)..."
        $DC logs -f --tail=100 $1
    else
        echo "Last 50 lines for $1:"
        $DC logs --tail=50 $1
    fi
else
    # Show menu
    echo "Available services:"
    echo "  1. postgres"
    echo "  2. redis"
    echo "  3. n8n"
    echo "  4. chatwoot"
    echo "  5. qdrant"
    echo "  6. otel-collector"
    echo "  7. jaeger"
    echo "  8. loki"
    echo "  9. alloy"
    echo "  10. prometheus"
    echo "  11. grafana"
    echo "  12. all (show all services)"
    echo ""
    echo "Usage:"
    echo "  ./logs.sh [service]           # Show last 50 lines"
    echo "  ./logs.sh [service] -f        # Follow logs (live)"
    echo "  ./logs.sh postgres            # Show postgres logs"
    echo "  ./logs.sh n8n -f              # Follow n8n logs"
    echo ""
    read -p "Enter service name or number: " choice
    
    case $choice in
        1) service="postgres" ;;
        2) service="redis" ;;
        3) service="n8n" ;;
        4) service="chatwoot" ;;
        5) service="qdrant" ;;
        6) service="otel-collector" ;;
        7) service="jaeger" ;;
        8) service="loki" ;;
        9) service="alloy" ;;
        10) service="prometheus" ;;
        11) service="grafana" ;;
        12) service="all" ;;
        *) service=$choice ;;
    esac
    
    read -p "Follow logs? (y/n): " follow
    
    if [ "$service" = "all" ]; then
        if [ "$follow" = "y" ]; then
            $DC logs -f
        else
            $DC logs --tail=20
        fi
    else
        if [ "$follow" = "y" ]; then
            $DC logs -f --tail=100 $service
        else
            $DC logs --tail=50 $service
        fi
    fi
fi
EOF

chmod +x logs.sh

# Create toggle script for N8N queue mode
cat > toggle-n8n-queue.sh << 'TOGGLEEOF'
#!/bin/bash
# Toggle N8N Redis Usage
# 
# This script switches N8N between two modes:
#   1. Single Instance Mode (NO Redis) - N8N uses only PostgreSQL
#   2. Queue Mode (USES Redis) - N8N uses Redis for job distribution + workers
#
# When you toggle:
#   - EXECUTIONS_MODE changes between "regular" and "queue"
#   - Redis connection for N8N is enabled/disabled
#   - Worker containers start/stop
#
# Note: Redis must be installed to enable Queue Mode

cd "$(dirname "$0")"

if [ -f .env ]; then
    source .env
else
    echo "ERROR: .env file not found"
    exit 1
fi

# Detect docker compose command
if docker compose version &> /dev/null; then
    DC="docker compose"
elif command -v docker-compose &> /dev/null; then
    DC="docker-compose"
else
    echo "Error: docker compose not found"
    exit 1
fi

current_mode=$(grep "^EXECUTIONS_MODE=" .env | cut -d'=' -f2)

echo "==============================================================================="
echo "   N8N Redis Toggle (Queue Mode)"
echo "==============================================================================="
echo ""
echo "Current mode: ${current_mode:-regular}"
echo ""

if [ "$current_mode" = "queue" ]; then
    echo "Switch to Single Instance mode?"
    echo "  • N8N will STOP using Redis"
    echo "  • Workers will stop"
    echo "  • N8N will use only PostgreSQL"
    echo "  • Redis will remain running (if used by Chatwoot)"
    echo ""
    read -p "Disable Redis for N8N? (y/n): " confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        # Update .env
        sed -i.bak 's/^EXECUTIONS_MODE=queue/EXECUTIONS_MODE=regular/' .env
        sed -i.bak 's/^N8N_QUEUE_MODE=true/N8N_QUEUE_MODE=false/' .env
        rm -f .env.bak
        
        # Stop workers
        $DC --profile n8n-queue stop n8n-worker
        $DC --profile n8n-queue rm -f n8n-worker
        
        # Restart main N8N
        $DC restart n8n
        
        echo ""
        echo "✓ Redis disabled for N8N"
        echo ""
        echo "N8N is now in Single Instance mode:"
        echo "  • NOT using Redis"
        echo "  • Using PostgreSQL only"
        echo "  • No worker containers running"
    fi
else
    echo "Enable Redis for N8N?"
    echo "  • N8N will START using Redis"
    echo "  • Checking Redis availability..."
    
    if [ "$INSTALL_REDIS" != "true" ]; then
        echo ""
        echo "ERROR: Redis is not installed."
        echo "Redis is required for queue mode."
        echo "Please reinstall with Redis support or choose queue mode during installation."
        exit 1
    fi
    
    echo "  ✓ Redis is installed and available"
    echo ""
    echo "  • Will start ${N8N_WORKERS:-2} worker container(s)"
    echo "  • N8N will connect to Redis for job distribution"
    echo "  • Better for high-volume workflows"
    echo ""
    read -p "Enable Redis for N8N? (y/n): " confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        # Ensure Redis is running
        $DC --profile redis up -d redis
        sleep 5
        
        # Update .env
        sed -i.bak 's/^EXECUTIONS_MODE=regular/EXECUTIONS_MODE=queue/' .env
        sed -i.bak 's/^N8N_QUEUE_MODE=false/N8N_QUEUE_MODE=true/' .env
        rm -f .env.bak
        
        # Reload env
        set -a; source .env; set +a
        
        # Start workers
        echo "Starting ${N8N_WORKERS:-2} worker(s)..."
        $DC --profile n8n-queue --profile redis up -d --scale n8n-worker=${N8N_WORKERS:-2} n8n-worker
        
        # Restart main N8N
        $DC restart n8n
        
        echo ""
        echo "✓ Redis enabled for N8N"
        echo ""
        echo "N8N is now in Queue Mode:"
        echo "  • USING Redis for job distribution"
        echo "  • Workers starting..."
        sleep 5
        $DC ps | grep n8n
        echo ""
        echo "TIP: To scale workers later, run:"
        echo "  $DC --profile n8n-queue --profile redis up -d --scale n8n-worker=<number>"
    fi
fi
TOGGLEEOF

chmod +x toggle-n8n-queue.sh

# Create enhance.sh script
echo_info "Creating enhancement script..."
cat > enhance.sh << 'ENHANCEOF'
#!/bin/bash
# RAG Stack Enhancement Script v2.0
# Adds: monitoring exporters, dashboards, UFW firewall, Qdrant security

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
echo_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
echo_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }
echo_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

echo "==============================================================================="
echo "   RAG Stack Enhancement Script v2.0"
echo "==============================================================================="
echo ""

[ ! -f ".env" ] || [ ! -f "docker-compose.yml" ] && echo_error "Run from RAG stack directory" && exit 1
set -a; source .env; set +a

if docker compose version &> /dev/null; then DC="docker compose"; else DC="docker-compose"; fi

echo "Options:"
echo "  1. Add Redis/PostgreSQL Exporters + Dashboards"
echo "  2. Configure UFW Firewall"  
echo "  3. Secure Qdrant with API Key"
echo "  4. All of the above"
echo "  5. Exit"
echo ""
read -p "Choose (1-5) [4]: " CHOICE; CHOICE=${CHOICE:-4}

add_exporters() {
    echo_info "Adding exporters..."
    grep -q "redis-exporter" docker-compose.yml 2>/dev/null && echo_warning "Already added" && return
    
    cat >> docker-compose.yml << EOF

  # === MONITORING EXPORTERS ===
  redis-exporter:
    image: oliver006/redis_exporter:latest
    container_name: ${CLIENT_NAME_SAFE}-redis-exporter
    environment:
      - REDIS_ADDR=redis://${CLIENT_NAME_SAFE}-redis:6379
      - REDIS_PASSWORD=\${REDIS_PASSWORD}
    ports: ["9121:9121"]
    depends_on: [redis]
    restart: unless-stopped
    networks: [rag-network]
    profiles: [monitoring]

  postgres-exporter:
    image: prometheuscommunity/postgres-exporter:latest
    container_name: ${CLIENT_NAME_SAFE}-postgres-exporter
    environment:
      - DATA_SOURCE_NAME=postgresql://postgres:\${POSTGRES_PASSWORD}@${CLIENT_NAME_SAFE}-postgres:5432/postgres?sslmode=disable
    ports: ["9187:9187"]
    depends_on: [postgres]
    restart: unless-stopped
    networks: [rag-network]
    profiles: [monitoring]
EOF
    echo_success "Exporters added. Start with: $DC --profile monitoring up -d"
}

add_dashboards() {
    echo_info "Creating dashboards..."
    mkdir -p grafana/provisioning/dashboards
    cat > grafana/provisioning/dashboards/default.yaml << 'EOF'
apiVersion: 1
providers:
  - name: 'RAG Stack'
    orgId: 1
    folder: 'RAG Stack'
    type: file
    options:
      path: /etc/grafana/provisioning/dashboards
EOF
    echo_success "Dashboards created"
}

configure_ufw() {
    echo_info "Configuring UFW..."
    command -v ufw &> /dev/null || { sudo apt-get update && sudo apt-get install -y ufw; }
    
    read -p "Allow Grafana externally? (y/n) [n]: " ALLOW_GRAFANA; ALLOW_GRAFANA=${ALLOW_GRAFANA:-n}
    read -p "Allow Jaeger externally? (y/n) [n]: " ALLOW_JAEGER; ALLOW_JAEGER=${ALLOW_JAEGER:-n}
    
    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow 22/tcp comment 'SSH'
    sudo ufw allow ${PORT_N8N:-5678}/tcp comment 'N8N'
    [ "$ALLOW_GRAFANA" = "y" ] && sudo ufw allow ${PORT_GRAFANA:-3000}/tcp comment 'Grafana'
    [ "$ALLOW_JAEGER" = "y" ] && sudo ufw allow ${PORT_JAEGER:-16686}/tcp comment 'Jaeger'
    sudo ufw --force enable
    echo_success "UFW configured"
    sudo ufw status
}

secure_qdrant() {
    echo_info "Securing Qdrant..."
    QDRANT_API_KEY=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)
    
    grep -q "QDRANT_API_KEY" .env || echo -e "\nQDRANT_API_KEY=${QDRANT_API_KEY}" >> .env
    
    mkdir -p qdrant
    cat > qdrant/config.yaml << EOF
service:
  api_key: ${QDRANT_API_KEY}
storage:
  storage_path: /qdrant/storage
EOF
    
    echo_success "Qdrant API key: ${QDRANT_API_KEY}"
    echo_warning "Add to docker-compose.yml qdrant volumes: ./qdrant/config.yaml:/qdrant/config/config.yaml:ro"
    echo_warning "Then restart: $DC restart qdrant"
    
    grep -q "QDRANT" CREDENTIALS.txt || echo -e "\n=== QDRANT ===\nAPI Key: ${QDRANT_API_KEY}" >> CREDENTIALS.txt
}

case $CHOICE in
    1) add_exporters; add_dashboards ;;
    2) configure_ufw ;;
    3) secure_qdrant ;;
    4) add_exporters; add_dashboards; configure_ufw; secure_qdrant ;;
    5) exit 0 ;;
esac

echo_success "Enhancement complete!"
ENHANCEOF

chmod +x enhance.sh

chmod +x start.sh stop.sh status.sh restart.sh

# Create README.md
cat > README.md << 'READMEEOF'
# RAG Stack Installation

## 📋 What's Installed

This directory contains your complete RAG (Retrieval-Augmented Generation) stack with the following components:

### Base Services

**PostgreSQL 16** - Main database
- Stores N8N workflows, executions, credentials
- Stores Chatwoot data (if installed)
- Includes pgvector extension for embeddings
- Port: See CREDENTIALS.txt

**N8N v2** - Workflow Automation
READMEEOF

if [ "$N8N_QUEUE_MODE" = "true" ]; then
cat >> README.md << READMEEOF
- Mode: Queue Mode (scalable with ${N8N_WORKERS} workers)
- Uses Redis for job distribution
- Can handle high-volume concurrent workflows
READMEEOF
else
cat >> README.md << 'READMEEOF'
- Mode: Single Instance
- Handles workflows sequentially
- Perfect for low-medium volume
READMEEOF
fi

cat >> README.md << 'READMEEOF'
- Access: See CREDENTIALS.txt for URL
- Features: 400+ integrations, custom nodes, webhook support

**Qdrant** - Vector Database
- Stores embeddings for semantic search
- Used for RAG applications
- Fast similarity search
- Access: See CREDENTIALS.txt

READMEEOF

if [ "$INSTALL_REDIS" = "true" ]; then
cat >> README.md << READMEEOF
**Redis 8.4** - In-Memory Data Store
- Used by: $REDIS_REASON
- Provides: Caching, job queues, real-time messaging
- Separate databases for each service (no conflicts)

READMEEOF
fi

if [ "$INSTALL_CHATWOOT" = "y" ]; then
cat >> README.md << 'READMEEOF'
### Customer Support

**Chatwoot** - Multi-Channel Support Platform
- Live chat, email, social media integration
- Agent dashboard and team collaboration
- Conversation management and ticketing
- Access: See CREDENTIALS.txt

READMEEOF
fi

if [ "$INSTALL_OBSERVABILITY" = "lite" ]; then
cat >> README.md << 'READMEEOF'
### Observability (Lite)

**Prometheus** - Metrics Collection
- Scrapes metrics from all services
- Time-series database
- Access: See CREDENTIALS.txt

**Grafana** - Visualization
- Pre-configured dashboards
- Metrics visualization
- Alerting capabilities
- Access: See CREDENTIALS.txt (includes login)

READMEEOF
elif [ "$INSTALL_OBSERVABILITY" = "full" ]; then
cat >> README.md << 'READMEEOF'
### Observability (Full Stack)

**OpenTelemetry Collector** - Telemetry Hub
- Receives traces, logs, and metrics
- Processes and exports to backends
- Central collection point

**Jaeger** - Distributed Tracing
- Trace workflows across services
- Performance analysis
- Dependency mapping
- Access: See CREDENTIALS.txt

**Loki** - Log Aggregation
- Centralized log storage
- Fast log queries
- Integrates with Grafana
- Access: See CREDENTIALS.txt

**Prometheus + Grafana** - Metrics & Dashboards
- Complete monitoring solution
- Pre-configured datasources
- Trace-log-metric correlation
- Access: See CREDENTIALS.txt

**Grafana Alloy** - Log Collector
- Collects container logs
- Sends to Loki
- Lightweight and efficient

READMEEOF
fi

cat >> README.md << 'READMEEOF'

---

## 🔭 Observability Modes Explained

This stack offers three observability levels:

| Mode | Components | Best For |
|------|------------|----------|
| **none** | Just `docker logs` | Development, minimal resources |
| **lite** | Prometheus + Grafana | Basic metrics, uptime monitoring |
| **full** | Prometheus + Grafana + Loki + Jaeger + OTel + Alloy | Production debugging, distributed tracing |

### When to use Full Observability

- **Debugging workflow failures** - Trace requests across N8N → Qdrant → external APIs
- **Performance optimization** - Find slow operations with distributed traces
- **Compliance/audit requirements** - Centralized, searchable logs
- **Multi-worker N8N setups** - Track jobs across workers
- **High-traffic production** - Correlate metrics, logs, and traces

### Resource Cost

| Mode | Additional RAM | Additional CPU |
|------|----------------|----------------|
| none | 0 | 0 |
| lite | ~1.5GB | 0.5 cores |
| full | ~4GB | 1.5 cores |

---

## 🚀 Quick Start

### Start All Services
```bash
./start.sh
```

### Check Status
```bash
./status.sh
```

### View Logs
```bash
./logs.sh              # Interactive menu
./logs.sh n8n          # Specific service
./logs.sh n8n -f       # Follow logs (live)
```

### Stop All Services
```bash
./stop.sh
```

### Restart Services
```bash
./restart.sh           # All services
./restart.sh n8n       # Specific service
```

---

## 📂 Important Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Service definitions |
| `.env` | Environment variables (KEEP SECURE!) |
| `CREDENTIALS.txt` | Access URLs and passwords (KEEP SECURE!) |
| `welcome.html` | Post-install guide (open in browser) |
| `start.sh` | Start all services |
| `stop.sh` | Stop all services |
| `status.sh` | Check service health |
| `logs.sh` | View service logs |
| `restart.sh` | Restart services |
| `enhance.sh` | Add monitoring, security, dashboards |
| `install.log` | Installation log |
| `README.md` | This file |

---

## 🔐 Security Notes

**IMPORTANT:** These files contain sensitive information:
- `.env` - Contains all passwords
- `CREDENTIALS.txt` - Contains access credentials
- `init-sql/` - Database initialization scripts

**Do NOT commit these to version control!**

The installer has created a `.gitignore` file to protect these files.

### Port Exposure Guide

| Service | Expose Externally? | Notes |
|---------|-------------------|-------|
| N8N | ✅ Yes | User-facing, use HTTPS |
| Grafana | ⚠️ Optional | Only if remote access needed |
| Jaeger | ⚠️ Optional | Development/debugging only |
| Qdrant | ⚠️ Optional | Only if external apps need it |
| PostgreSQL | ❌ No | Keep internal |
| Redis | ❌ No | Keep internal |
| Prometheus | ❌ No | Keep internal |
| Loki | ❌ No | Keep internal |

**Recommendation:** Run `./enhance.sh` and select UFW configuration to automatically set up firewall rules.

---

## 🎯 Common Tasks

### Access N8N
1. Open URL from CREDENTIALS.txt
2. Create your first workflow
3. Use webhook triggers or schedule workflows
4. Connect to Qdrant for vector operations

### Access Grafana (if installed)
1. Open URL from CREDENTIALS.txt
2. Login with credentials from CREDENTIALS.txt
3. Explore pre-configured dashboards
4. View metrics, traces, and logs

### Access Chatwoot (if installed)
1. Open URL from CREDENTIALS.txt
2. Create your first account
3. Set up inbox and channels
4. Start handling conversations

### Connect N8N to Qdrant
In N8N workflows:
```
Qdrant Node:
  Host: qdrant
  Port: 6333
  Collection: your_collection_name
```

### Connect N8N to LM Studio (running on Mac)
In N8N workflows:
```
HTTP Request Node:
  URL: http://host.docker.internal:1234/v1/chat/completions
```

READMEEOF

if [ "$INSTALL_REDIS" = "true" ]; then
cat >> README.md << READMEEOF

### Redis Database Usage
Redis is shared between services using separate databases:
- **Database 0**: N8N (queue jobs - if queue mode enabled)
- **Database 1**: Chatwoot (cache, Sidekiq, pub/sub - if installed)

Check Redis usage:
\`\`\`bash
# Connect to Redis
docker exec \${CLIENT_NAME_SAFE}-redis redis-cli -a \${REDIS_PASSWORD}

# View databases
INFO keyspace

# Example output:
# db0:keys=25,expires=0   ← N8N
# db1:keys=142,expires=18 ← Chatwoot
\`\`\`

This architecture prevents conflicts between services.

READMEEOF
fi

if [ "$N8N_QUEUE_MODE" = "true" ]; then
cat >> README.md << READMEEOF

### Scale N8N Workers (Queue Mode)
\`\`\`bash
# Add more workers
docker-compose --profile n8n-queue --profile redis up -d --scale n8n-worker=3

# View worker status
docker-compose ps | grep worker
\`\`\`

### Switch N8N Mode (Toggle Redis Usage)
Use the toggle script to enable or disable Redis for N8N:
\`\`\`bash
./toggle-n8n-queue.sh
\`\`\`

**What this does:**
- **Single Instance Mode:** N8N does NOT use Redis (simple, PostgreSQL only)
- **Queue Mode:** N8N USES Redis for job distribution (scalable with workers)

The script will:
- Check current mode
- Verify Redis availability (for queue mode)
- Update configuration (EXECUTIONS_MODE)
- Enable/disable Redis connection for N8N
- Start/stop worker containers as needed
- Restart N8N

READMEEOF
else
cat >> README.md << 'READMEEOF'

### Toggle N8N Mode (Enable Redis)
Your N8N is currently in Single Instance mode (not using Redis). 

To enable Redis and use Queue Mode:
\`\`\`bash
./toggle-n8n-queue.sh
\`\`\`

This will:
- Enable Redis connection for N8N
- Switch to Queue Mode with workers
- Allow horizontal scaling

**Note:** Queue mode requires Redis. If you didn't install Redis initially, you'll need to reinstall with Redis support.
READMEEOF
fi

cat >> README.md << 'READMEEOF'

---

## 🔧 Troubleshooting

### Service Won't Start
```bash
# Check logs
./logs.sh [service-name]

# Check status
./status.sh

# Try restart
./restart.sh [service-name]
```

---

## ⚡ Enhancement Script

After installation, run the enhancement script for additional features:

```bash
./enhance.sh
```

### What it adds:

**Monitoring Enhancements**
- Redis exporter (if Redis installed)
- PostgreSQL exporter
- Pre-built Grafana dashboards for each service
- Prometheus alerting rules

**Security Hardening**
- UFW firewall configuration (auto-configures ports)
- Qdrant API key protection

### Enhancement Menu

```
1. Configure Monitoring    - Select which services to monitor
2. Configure UFW Firewall  - Set up firewall rules
3. Secure Qdrant           - Generate API key
4. Full Enhancement        - All of the above
5. Exit
```

---

## 🔒 Security Notes

### Port Conflicts
If you see "port already in use" errors:
- Ports are auto-allocated during installation
- Check CREDENTIALS.txt for actual ports
- All services use environment variables from .env

### Database Issues
```bash
# Check PostgreSQL
docker exec ${CLIENT_NAME_SAFE}-postgres pg_isready -U postgres

# View PostgreSQL logs
./logs.sh postgres
```

READMEEOF

if [ "$INSTALL_REDIS" = "true" ]; then
cat >> README.md << 'READMEEOF'
### Redis Issues
```bash
# Check Redis
docker exec ${CLIENT_NAME_SAFE}-redis redis-cli -a ${REDIS_PASSWORD} ping

# Should return: PONG

# View what's in Redis
docker exec ${CLIENT_NAME_SAFE}-redis redis-cli -a ${REDIS_PASSWORD} INFO keyspace
```
READMEEOF
fi

cat >> README.md << 'READMEEOF'

### Out of Memory
Check Docker Desktop resources:
- Recommended: 16GB RAM minimum
- Increase in: Docker Desktop → Preferences → Resources

### Clean Restart
```bash
./stop.sh
docker-compose down
./start.sh
```

---

## 📊 Resource Usage

Approximate memory usage:

READMEEOF

cat >> README.md << READMEEOF
- PostgreSQL: ~2GB
- N8N Main: ~2GB
READMEEOF

if [ "$N8N_QUEUE_MODE" = "true" ]; then
cat >> README.md << READMEEOF
- N8N Workers: ~1GB each (${N8N_WORKERS} workers)
READMEEOF
fi

if [ "$INSTALL_REDIS" = "true" ]; then
cat >> README.md << 'READMEEOF'
- Redis: ~100MB
READMEEOF
fi

if [ "$INSTALL_CHATWOOT" = "y" ]; then
cat >> README.md << 'READMEEOF'
- Chatwoot: ~2GB
READMEEOF
fi

cat >> README.md << 'READMEEOF'
- Qdrant: ~1GB
READMEEOF

if [ "$INSTALL_OBSERVABILITY" = "lite" ]; then
cat >> README.md << 'READMEEOF'
- Prometheus: ~1GB
- Grafana: ~500MB
READMEEOF
elif [ "$INSTALL_OBSERVABILITY" = "full" ]; then
cat >> README.md << 'READMEEOF'
- OpenTelemetry: ~500MB
- Jaeger: ~1GB
- Loki: ~1GB
- Prometheus: ~1GB
- Grafana: ~500MB
- Alloy: ~100MB
READMEEOF
fi

cat >> README.md << READMEEOF

**Total: ~${RAM}GB**

---

## 🔄 Updates

### Update Services
\`\`\`bash
cd $(pwd)
docker-compose pull
docker-compose up -d
\`\`\`

### Backup Data
\`\`\`bash
# Backup volumes
docker run --rm -v postgres_data:/data -v \$(pwd)/backups:/backup alpine tar czf /backup/postgres-\$(date +%Y%m%d).tar.gz /data

# Or use Docker Desktop's built-in backup feature
\`\`\`

---

## 📚 Documentation

- **N8N**: https://docs.n8n.io
- **Qdrant**: https://qdrant.tech/documentation
- **PostgreSQL**: https://www.postgresql.org/docs
READMEEOF

if [ "$INSTALL_CHATWOOT" = "y" ]; then
cat >> README.md << 'READMEEOF'
- **Chatwoot**: https://www.chatwoot.com/docs
READMEEOF
fi

if [ "$INSTALL_OBSERVABILITY" != "none" ]; then
cat >> README.md << 'READMEEOF'
- **Grafana**: https://grafana.com/docs
- **Prometheus**: https://prometheus.io/docs
READMEEOF
fi

if [ "$INSTALL_OBSERVABILITY" = "full" ]; then
cat >> README.md << 'READMEEOF'
- **Jaeger**: https://www.jaegertracing.io/docs
- **Loki**: https://grafana.com/docs/loki
- **OpenTelemetry**: https://opentelemetry.io/docs
READMEEOF
fi

cat >> README.md << 'READMEEOF'

---

## 💡 Tips

1. **Use ./status.sh regularly** - Quick health check of all services
2. **Follow logs during development** - `./logs.sh n8n -f` while building workflows
3. **Check CREDENTIALS.txt** - Contains all access URLs and passwords
4. **Backup your .env file** - Contains encryption keys needed for restores
5. **Monitor resource usage** - Use `docker stats` to check memory/CPU
6. **Use Docker Desktop** - Easy to view containers, volumes, and logs

---

## 🆘 Support

If you encounter issues:

1. Check `./logs.sh [service]` for error messages
2. Run `./status.sh` to see service health
3. Review this README for troubleshooting steps
4. Check official documentation (links above)
5. Review `install.log` for installation details

---

**Installation completed:** $(date)
**Installation directory:** $(pwd)
**Client:** ${CLIENT_NAME}

Keep this README for reference. Keep `.env` and `CREDENTIALS.txt` secure!
READMEEOF

echo_success "✓ README.md created"

# Create CREDENTIALS.txt
cat > CREDENTIALS.txt << EOF
RAG Stack with Full Observability
Client: ${CLIENT_NAME}
Generated: $(date)

=== BASE STACK ===
PostgreSQL:   localhost:${PORT_POSTGRES}
Redis:        localhost:${PORT_REDIS}
N8N:          ${PROTOCOL}://${CLIENT_DOMAIN}:${PORT_N8N}
Qdrant:       http://${CLIENT_DOMAIN}:${PORT_QDRANT}

EOF

# Add Chatwoot if selected
if [ "$INSTALL_CHATWOOT" = "y" ]; then
cat >> CREDENTIALS.txt << EOF
=== CUSTOMER SUPPORT ===
Chatwoot:     http://${CLIENT_DOMAIN}:${PORT_CHATWOOT}

EOF
fi

# Add Observability URLs if selected
if [ "$INSTALL_OBSERVABILITY" = "lite" ]; then
cat >> CREDENTIALS.txt << EOF
=== OBSERVABILITY (LITE) ===
Grafana:      http://localhost:${PORT_GRAFANA} (main dashboard)
Prometheus:   http://localhost:${PORT_PROMETHEUS} (metrics)

EOF
elif [ "$INSTALL_OBSERVABILITY" = "full" ]; then
cat >> CREDENTIALS.txt << EOF
=== OBSERVABILITY (FULL) ===
Grafana:      http://localhost:${PORT_GRAFANA} (main dashboard)
Jaeger:       http://localhost:${PORT_JAEGER} (distributed tracing)
Prometheus:   http://localhost:${PORT_PROMETHEUS} (metrics)
Loki:         http://localhost:${PORT_LOKI} (logs API)
OTel:         http://localhost:${PORT_OTEL_GRPC} (gRPC), ${PORT_OTEL_HTTP} (HTTP)

EOF
fi

cat >> CREDENTIALS.txt << EOF
=== CREDENTIALS ===
PostgreSQL:   postgres / ${POSTGRES_PASS}
Redis:        ${REDIS_PASS}
N8N DB User:  n8n_user / ${POSTGRES_N8N_PASS}
EOF

if [ "$INSTALL_CHATWOOT" = "y" ]; then
cat >> CREDENTIALS.txt << EOF
Chatwoot DB:  chatwoot_user / ${POSTGRES_CHATWOOT_PASS}
EOF
fi

if [ "$INSTALL_OBSERVABILITY" != "none" ]; then
cat >> CREDENTIALS.txt << EOF
Grafana:      admin / ${GRAFANA_PASS}
EOF
fi

cat >> CREDENTIALS.txt << EOF

=== INSTALLED COMPONENTS ===
Base Stack: PostgreSQL 16, N8N v2, Qdrant
EOF

if [ "$INSTALL_REDIS" = "true" ]; then
cat >> CREDENTIALS.txt << EOF
Redis: 8.4 (for: $REDIS_REASON)
EOF
fi

if [ "$INSTALL_CHATWOOT" = "y" ]; then
cat >> CREDENTIALS.txt << EOF
Customer Support: Chatwoot
EOF
fi

if [ "$INSTALL_OBSERVABILITY" = "lite" ]; then
cat >> CREDENTIALS.txt << EOF
Observability: Lite (Prometheus, Grafana)
EOF
elif [ "$INSTALL_OBSERVABILITY" = "full" ]; then
cat >> CREDENTIALS.txt << EOF
Observability: Full (OTel v0.142.0, Jaeger v2.13.0, Loki v3.6.3, Prometheus, Grafana, Alloy)
EOF
fi

cat >> CREDENTIALS.txt << EOF

=== MANAGEMENT ===
Start:    ./start.sh
Stop:     ./stop.sh
Status:   ./status.sh
Restart:  ./restart.sh [service]
Logs:     ./logs.sh [service] [-f]

KEEP THIS FILE SECURE!
EOF

# Create welcome.html
echo_info "Creating welcome page..."
cat > welcome.html << WELCOMEEOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>RAG Stack - ${CLIENT_NAME}</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%);
            min-height: 100vh;
            color: #e0e0e0;
            padding: 40px 20px;
        }
        .container { max-width: 900px; margin: 0 auto; }
        h1 {
            font-size: 2.5rem;
            margin-bottom: 10px;
            background: linear-gradient(90deg, #00d9ff, #00ff88);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
        }
        .subtitle { color: #888; margin-bottom: 30px; font-size: 1.1rem; }
        .card {
            background: rgba(255,255,255,0.05);
            border-radius: 16px;
            padding: 24px;
            margin-bottom: 20px;
            border: 1px solid rgba(255,255,255,0.1);
            backdrop-filter: blur(10px);
        }
        .card h2 {
            font-size: 1.3rem;
            margin-bottom: 16px;
            color: #00d9ff;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .service-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 12px; }
        .service {
            background: rgba(0,0,0,0.2);
            border-radius: 10px;
            padding: 16px;
            display: flex;
            align-items: center;
            gap: 12px;
            transition: transform 0.2s, background 0.2s;
        }
        .service:hover { transform: translateY(-2px); background: rgba(0,217,255,0.1); }
        .service-icon {
            width: 40px;
            height: 40px;
            border-radius: 8px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 1.2rem;
        }
        .service-info { flex: 1; }
        .service-name { font-weight: 600; color: #fff; }
        .service-url { font-size: 0.85rem; color: #888; }
        .service-link {
            color: #00d9ff;
            text-decoration: none;
            font-size: 0.9rem;
            padding: 6px 12px;
            border: 1px solid #00d9ff;
            border-radius: 6px;
            transition: all 0.2s;
        }
        .service-link:hover { background: #00d9ff; color: #1a1a2e; }
        .checklist { list-style: none; }
        .checklist li {
            padding: 12px 0;
            border-bottom: 1px solid rgba(255,255,255,0.1);
            display: flex;
            align-items: flex-start;
            gap: 12px;
        }
        .checklist li:last-child { border-bottom: none; }
        .check-box {
            width: 24px;
            height: 24px;
            border: 2px solid #00ff88;
            border-radius: 6px;
            display: flex;
            align-items: center;
            justify-content: center;
            flex-shrink: 0;
            cursor: pointer;
        }
        .check-box.checked { background: #00ff88; color: #1a1a2e; }
        .check-text strong { color: #fff; }
        .note {
            background: rgba(255,200,0,0.1);
            border-left: 3px solid #ffc800;
            padding: 12px 16px;
            border-radius: 0 8px 8px 0;
            margin-top: 16px;
            font-size: 0.9rem;
        }
        .credentials-note {
            background: rgba(255,100,100,0.1);
            border-left: 3px solid #ff6464;
        }
        footer { text-align: center; margin-top: 40px; color: #666; font-size: 0.85rem; }
        footer a { color: #00d9ff; text-decoration: none; }
        @media (max-width: 600px) {
            h1 { font-size: 1.8rem; }
            .service-grid { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎉 RAG Stack Ready!</h1>
        <p class="subtitle">Installation complete for ${CLIENT_NAME}</p>

        <div class="card">
            <h2>🔗 Your Services</h2>
            <div class="service-grid">
                <div class="service">
                    <div class="service-icon" style="background: linear-gradient(135deg, #ff6b6b, #ee5a5a);">⚡</div>
                    <div class="service-info">
                        <div class="service-name">N8N Automation</div>
                        <div class="service-url">${PROTOCOL}://localhost:${PORT_N8N}</div>
                    </div>
                    <a href="${PROTOCOL}://localhost:${PORT_N8N}" target="_blank" class="service-link">Open</a>
                </div>
                <div class="service">
                    <div class="service-icon" style="background: linear-gradient(135deg, #4ecdc4, #45b7aa);">🔍</div>
                    <div class="service-info">
                        <div class="service-name">Qdrant Vector DB</div>
                        <div class="service-url">http://localhost:${PORT_QDRANT}</div>
                    </div>
                    <a href="http://localhost:${PORT_QDRANT}/dashboard" target="_blank" class="service-link">Open</a>
                </div>
WELCOMEEOF

# Add Chatwoot to welcome page if installed
if [ "$INSTALL_CHATWOOT" = "y" ]; then
cat >> welcome.html << WELCOMEEOF
                <div class="service">
                    <div class="service-icon" style="background: linear-gradient(135deg, #667eea, #5a67d8);">💬</div>
                    <div class="service-info">
                        <div class="service-name">Chatwoot</div>
                        <div class="service-url">http://localhost:${PORT_CHATWOOT}</div>
                    </div>
                    <a href="http://localhost:${PORT_CHATWOOT}" target="_blank" class="service-link">Open</a>
                </div>
WELCOMEEOF
fi

# Add observability services to welcome page
if [ "$INSTALL_OBSERVABILITY" != "none" ]; then
cat >> welcome.html << WELCOMEEOF
                <div class="service">
                    <div class="service-icon" style="background: linear-gradient(135deg, #f093fb, #f5576c);">📊</div>
                    <div class="service-info">
                        <div class="service-name">Grafana</div>
                        <div class="service-url">http://localhost:${PORT_GRAFANA}</div>
                    </div>
                    <a href="http://localhost:${PORT_GRAFANA}" target="_blank" class="service-link">Open</a>
                </div>
WELCOMEEOF
fi

if [ "$INSTALL_OBSERVABILITY" = "full" ]; then
cat >> welcome.html << WELCOMEEOF
                <div class="service">
                    <div class="service-icon" style="background: linear-gradient(135deg, #43cea2, #185a9d);">🔭</div>
                    <div class="service-info">
                        <div class="service-name">Jaeger Tracing</div>
                        <div class="service-url">http://localhost:${PORT_JAEGER}</div>
                    </div>
                    <a href="http://localhost:${PORT_JAEGER}" target="_blank" class="service-link">Open</a>
                </div>
WELCOMEEOF
fi

cat >> welcome.html << WELCOMEEOF
            </div>
        </div>

        <div class="card">
            <h2>✅ Post-Install Checklist</h2>
            <ul class="checklist">
                <li>
                    <div class="check-box" onclick="this.classList.toggle('checked')"></div>
                    <div class="check-text">
                        <strong>Create N8N User Account</strong><br>
                        Open N8N and create your first admin user. This is required before you can use N8N.
                    </div>
                </li>
WELCOMEEOF

if [ "$INSTALL_OBSERVABILITY" != "none" ]; then
cat >> welcome.html << WELCOMEEOF
                <li>
                    <div class="check-box" onclick="this.classList.toggle('checked')"></div>
                    <div class="check-text">
                        <strong>Login to Grafana</strong><br>
                        Username: <code>admin</code> | Password: see CREDENTIALS.txt<br>
                        Change the default password on first login.
                    </div>
                </li>
WELCOMEEOF
fi

if [ "$INSTALL_CHATWOOT" = "y" ]; then
cat >> welcome.html << WELCOMEEOF
                <li>
                    <div class="check-box" onclick="this.classList.toggle('checked')"></div>
                    <div class="check-text">
                        <strong>Setup Chatwoot</strong><br>
                        Create your Chatwoot admin account and configure your first inbox.
                    </div>
                </li>
WELCOMEEOF
fi

cat >> welcome.html << WELCOMEEOF
                <li>
                    <div class="check-box" onclick="this.classList.toggle('checked')"></div>
                    <div class="check-text">
                        <strong>Add Qdrant to N8N</strong><br>
                        In N8N, add a Qdrant credential: URL = <code>http://${CLIENT_NAME_SAFE}-qdrant:6333</code>
                    </div>
                </li>
                <li>
                    <div class="check-box" onclick="this.classList.toggle('checked')"></div>
                    <div class="check-text">
                        <strong>(Optional) Run Enhancement Script</strong><br>
                        Run <code>./enhance.sh</code> to add exporters, dashboards, firewall rules, and Qdrant API security.
                    </div>
                </li>
            </ul>
        </div>

        <div class="card">
            <h2>📁 Important Files</h2>
            <div class="note credentials-note">
                <strong>🔐 CREDENTIALS.txt</strong> - Contains all passwords and connection strings. Keep this secure!
            </div>
            <div class="note">
                <strong>📋 Management Scripts:</strong><br>
                <code>./start.sh</code> | <code>./stop.sh</code> | <code>./status.sh</code> | <code>./logs.sh [service]</code>
            </div>
        </div>

        <footer>
            Generated on $(date) | <a href="https://n8n.io" target="_blank">N8N</a> • <a href="https://qdrant.tech" target="_blank">Qdrant</a> • <a href="https://grafana.com" target="_blank">Grafana</a>
        </footer>
    </div>
    <script>
        // Add checkmark when clicked
        document.querySelectorAll('.check-box').forEach(box => {
            box.addEventListener('click', () => {
                if(box.classList.contains('checked')) {
                    box.innerHTML = '✓';
                } else {
                    box.innerHTML = '';
                }
            });
        });
    </script>
</body>
</html>
WELCOMEEOF

echo_success "✓ welcome.html created"

# ============================================================================
# VALIDATION PHASE
# ============================================================================

echo ""
echo "==============================================================================="
echo "   VALIDATION PHASE"
echo "==============================================================================="
echo ""

echo_info "Validating generated files..."

# Check if all required files exist
REQUIRED_FILES=(
    "docker-compose.yml"
    "otel-collector-config.yaml"
    "loki-config.yaml"
    "alloy-config.alloy"
    "prometheus/prometheus.yml"
    "grafana/provisioning/datasources/datasources.yml"
    "init-sql/01-init.sql"
    ".env"
    "start.sh"
    "stop.sh"
    "welcome.html"
    "enhance.sh"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        add_validation_error "Missing required file: $file"
    else
        echo_success "✓ Found: $file"
    fi
done

# Validate YAML syntax
echo ""
echo_info "Validating YAML syntax..."

for yaml_file in docker-compose.yml otel-collector-config.yaml loki-config.yaml prometheus/prometheus.yml grafana/provisioning/datasources/datasources.yml; do
    if docker run --rm -v "$PWD:/workdir" mikefarah/yq eval "$yaml_file" > /dev/null 2>&1; then
        echo_success "✓ Valid YAML: $yaml_file"
    else
        add_validation_error "Invalid YAML syntax in: $yaml_file"
    fi
done

# Validate .env file
echo ""
echo_info "Validating .env file..."

REQUIRED_ENV_VARS=(
    "CLIENT_NAME_SAFE"
    "POSTGRES_PASSWORD"
    "REDIS_PASSWORD"
    "GRAFANA_PASSWORD"
)

for var in "${REQUIRED_ENV_VARS[@]}"; do
    if grep -q "^${var}=" .env; then
        echo_success "✓ Found env var: $var"
    else
        add_validation_error "Missing environment variable: $var"
    fi
done

# Check password strength
echo ""
echo_info "Validating password strength..."

if [ ${#POSTGRES_PASS} -lt $PASSWORD_MIN_LENGTH ]; then
    add_validation_error "PostgreSQL password too short (${#POSTGRES_PASS} chars, need ${PASSWORD_MIN_LENGTH}+)"
else
    echo_success "✓ PostgreSQL password: ${#POSTGRES_PASS} characters"
fi

if [ ${#REDIS_PASS} -lt $PASSWORD_MIN_LENGTH ]; then
    add_validation_error "Redis password too short (${#REDIS_PASS} chars, need ${PASSWORD_MIN_LENGTH}+)"
else
    echo_success "✓ Redis password: ${#REDIS_PASS} characters"
fi

# Check Docker resources
echo ""
echo_info "Checking Docker resources..."

AVAILABLE_MEMORY=$(docker system info 2>/dev/null | grep "Total Memory" | awk '{print $3}')
if [ -n "$AVAILABLE_MEMORY" ]; then
    echo_success "✓ Docker memory: ${AVAILABLE_MEMORY}GiB available"
else
    echo_warning "⚠ Could not determine Docker memory"
fi

# ============================================================================
# VALIDATION RESULTS
# ============================================================================

echo ""
echo "==============================================================================="
echo "   VALIDATION RESULTS"
echo "==============================================================================="
echo ""

if [ "$VALIDATION_PASSED" = true ]; then
    echo_success "✓ All validation checks passed!"
    echo ""
else
    echo_error "✗ Validation failed with ${#VALIDATION_ERRORS[@]} error(s):"
    echo ""
    for error in "${VALIDATION_ERRORS[@]}"; do
        echo "  - $error"
    done
    echo ""
    read -p "Continue anyway? (y/n): " FORCE_CONTINUE
    if [ "$FORCE_CONTINUE" != "y" ] && [ "$FORCE_CONTINUE" != "Y" ]; then
        echo_error "Installation aborted due to validation errors."
        exit 1
    fi
    echo_warning "Continuing despite validation errors..."
fi

# ============================================================================
# START SERVICES
# ============================================================================

echo ""
echo "==============================================================================="
echo "   STARTING SERVICES"
echo "==============================================================================="
echo ""

echo_info "Starting services with staged startup..."

# Build profile flags based on selected components
PROFILE_FLAGS=""
if [ "$INSTALL_REDIS" = "true" ]; then
    PROFILE_FLAGS="$PROFILE_FLAGS --profile redis"
fi
if [ "$N8N_QUEUE_MODE" = "true" ]; then
    PROFILE_FLAGS="$PROFILE_FLAGS --profile n8n-queue"
fi
if [ "$INSTALL_CHATWOOT" = "y" ]; then
    PROFILE_FLAGS="$PROFILE_FLAGS --profile chatwoot"
fi

echo "Stage 1: Starting databases..."
if [ "$INSTALL_REDIS" = "true" ]; then
    $DOCKER_COMPOSE $PROFILE_FLAGS up -d postgres redis
    echo_info "Starting PostgreSQL and Redis..."
else
    $DOCKER_COMPOSE $PROFILE_FLAGS up -d postgres
    echo_info "Starting PostgreSQL..."
fi
wait_with_progress $WAIT_DATABASE_INIT "Waiting for databases to initialize..." "postgres"

# Double-check database health
if ! docker exec "${CLIENT_NAME_SAFE}-postgres" pg_isready -U postgres > /dev/null 2>&1; then
    echo_warning "PostgreSQL needs more time..."
    wait_with_progress $WAIT_DATABASE_EXTRA "Waiting for PostgreSQL..." "postgres"
fi

echo ""
echo "Stage 2: Starting core applications..."
CORE_APPS="n8n qdrant"
if [ "$INSTALL_CHATWOOT" = "y" ]; then
    CORE_APPS="$CORE_APPS chatwoot"
    echo_info "Including Chatwoot (Customer Support)"
fi
$DOCKER_COMPOSE $PROFILE_FLAGS up -d $CORE_APPS

# Scale workers if queue mode enabled
if [ "$N8N_QUEUE_MODE" = "true" ]; then
    echo_info "Starting ${N8N_WORKERS} N8N worker(s)..."
    $DOCKER_COMPOSE $PROFILE_FLAGS up -d --scale n8n-worker=${N8N_WORKERS} n8n-worker
fi

wait_with_progress $WAIT_APPLICATION "Waiting for applications..."

if [ "$INSTALL_OBSERVABILITY" != "none" ]; then
    echo ""
    if [ "$INSTALL_OBSERVABILITY" = "lite" ]; then
        echo "Stage 3: Starting observability (Lite)..."
        $DOCKER_COMPOSE $PROFILE_FLAGS up -d prometheus grafana
        echo_info "Starting: Prometheus + Grafana"
    elif [ "$INSTALL_OBSERVABILITY" = "full" ]; then
        echo "Stage 3: Starting observability (Full)..."
        $DOCKER_COMPOSE $PROFILE_FLAGS up -d otel-collector jaeger loki alloy prometheus grafana
        echo_info "Starting: Full observability stack"
    fi
    wait_with_progress $WAIT_OBSERVABILITY "Waiting for observability stack..."
fi

echo ""
echo_info "Final service status:"
$DOCKER_COMPOSE $PROFILE_FLAGS ps

# ============================================================================
# INSTALLATION COMPLETE
# ============================================================================

echo ""
echo "==============================================================================="
echo "   INSTALLATION COMPLETE!"
echo "==============================================================================="
echo ""
echo "Stack Information:"
echo "  Client:       $CLIENT_NAME"
echo "  Location:     $INSTALL_DIR"
echo "  Files:        All configuration files are in $INSTALL_DIR"
echo "  Protocol:     $PROTOCOL"
echo ""
echo "Base Services:"
echo "  N8N:          ${PROTOCOL}://${CLIENT_DOMAIN}:${PORT_N8N}"
echo "  Qdrant:       http://${CLIENT_DOMAIN}:${PORT_QDRANT}"
echo "  PostgreSQL:   localhost:${PORT_POSTGRES}"
echo "  Redis:        localhost:${PORT_REDIS}"

if [ "$INSTALL_CHATWOOT" = "y" ]; then
echo ""
echo "Customer Support:"
echo "  Chatwoot:     http://${CLIENT_DOMAIN}:${PORT_CHATWOOT}"
fi

if [ "$INSTALL_OBSERVABILITY" = "lite" ]; then
echo ""
echo "Observability (Lite):"
echo "  Grafana:      http://localhost:${PORT_GRAFANA} (admin/${GRAFANA_PASS})"
echo "  Prometheus:   http://localhost:${PORT_PROMETHEUS}"
elif [ "$INSTALL_OBSERVABILITY" = "full" ]; then
echo ""
echo "Observability (Full):"
echo "  Grafana:      http://localhost:${PORT_GRAFANA} (admin/${GRAFANA_PASS})"
echo "  Jaeger:       http://localhost:${PORT_JAEGER}"
echo "  Prometheus:   http://localhost:${PORT_PROMETHEUS}"
echo "  Loki:         http://localhost:${PORT_LOKI}"
fi

echo ""
echo "Management:"
echo "  Start:        ./start.sh"
echo "  Stop:         ./stop.sh"
echo "  Status:       ./status.sh"
echo "  Restart:      ./restart.sh [service]"
echo "  Logs:         ./logs.sh [service] [-f]"
if [ "$N8N_QUEUE_MODE" = "true" ] || [ "$INSTALL_REDIS" = "true" ]; then
echo "  Toggle N8N:   ./toggle-n8n-queue.sh (enable/disable Redis for N8N)"
fi
echo "  Credentials:  cat CREDENTIALS.txt"
echo ""
echo "Next Steps:"
echo "  1. Open N8N: ${PROTOCOL}://${CLIENT_DOMAIN}:${PORT_N8N}"

if [ "$INSTALL_OBSERVABILITY" != "none" ]; then
echo "  2. Open Grafana: http://localhost:${PORT_GRAFANA}"
echo "  3. Explore pre-configured dashboards"
fi

if [ "$INSTALL_OBSERVABILITY" = "full" ]; then
echo "  4. Check Jaeger for distributed tracing"
echo "  5. View logs in Loki via Grafana"
fi
echo ""
echo "Files Created:"
echo "  - docker-compose.yml"
echo "  - README.md (comprehensive guide)"
echo "  - All config files (otel, loki, alloy, prometheus, grafana)"
echo "  - Management scripts (start.sh, stop.sh, status.sh, restart.sh, logs.sh)"
if [ "$N8N_QUEUE_MODE" = "true" ] || [ "$INSTALL_REDIS" = "true" ]; then
echo "  - toggle-n8n-queue.sh (toggle Redis usage for N8N)"
fi
echo "  - CREDENTIALS.txt (KEEP SECURE!)"
echo "  - .env (KEEP SECURE!)"
echo "  - welcome.html (open in browser for post-install guide)"
echo ""
echo "Installation log: $LOGFILE"
echo ""
echo "==============================================================================="

read -p "Open welcome page in browser? (y/n) [y]: " OPEN_WELCOME
OPEN_WELCOME=${OPEN_WELCOME:-y}
if [ "$OPEN_WELCOME" = "y" ] || [ "$OPEN_WELCOME" = "Y" ]; then
    open_url "file://$PWD/welcome.html"
fi

read -p "Open N8N now? (y/n): " OPEN_N8N
if [ "$OPEN_N8N" = "y" ] || [ "$OPEN_N8N" = "Y" ]; then
    open_url "${PROTOCOL}://${CLIENT_DOMAIN}:${PORT_N8N}"
fi

if [ "$INSTALL_OBSERVABILITY" != "none" ]; then
    read -p "Open Grafana now? (y/n): " OPEN_GRAFANA
    if [ "$OPEN_GRAFANA" = "y" ] || [ "$OPEN_GRAFANA" = "Y" ]; then
        open_url "http://localhost:${PORT_GRAFANA}"
    fi
fi

echo ""
echo_success "Installation complete! Check ./status.sh for service status."
log "Installation completed successfully"
