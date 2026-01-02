#!/bin/bash
# RAG Stack Enhancement Script v2.0
# Run this AFTER the main installer to add:
# - Selective service monitoring (exporters + dashboards)
# - UFW firewall configuration
# - Qdrant API key security
# - Alerting rules

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
echo_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }
echo_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
echo_header() { echo -e "${CYAN}$1${NC}"; }

echo "==============================================================================="
echo "   RAG Stack Enhancement Script v2.0"
echo "==============================================================================="
echo ""

# Check if we're in a RAG stack directory
if [ ! -f ".env" ] || [ ! -f "docker-compose.yml" ]; then
    echo_error "This script must be run from a RAG stack installation directory"
    echo "Please cd to ~/rag-stack-<client-name> first"
    exit 1
fi

# Load environment
set -a
source .env
set +a

# Detect docker compose command
if docker compose version &> /dev/null; then
    DC="docker compose"
elif command -v docker-compose &> /dev/null; then
    DC="docker-compose"
else
    echo_error "Docker compose not found"
    exit 1
fi

echo_info "Detected installation: ${CLIENT_NAME_SAFE}"
echo ""

# =============================================================================
# MAIN MENU
# =============================================================================
echo "Available enhancements:"
echo ""
echo "  ${CYAN}MONITORING${NC}"
echo "    1. Configure Monitoring (select services to monitor)"
echo ""
echo "  ${CYAN}SECURITY${NC}"
echo "    2. Configure UFW Firewall"
echo "    3. Secure Qdrant with API Key"
echo ""
echo "  ${CYAN}QUICK OPTIONS${NC}"
echo "    4. Full Enhancement (monitoring + security)"
echo "    5. Exit"
echo ""

read -p "Choose option (1-5) [4]: " MAIN_CHOICE
MAIN_CHOICE=${MAIN_CHOICE:-4}

# =============================================================================
# MONITORING CONFIGURATION
# =============================================================================
configure_monitoring() {
    echo ""
    echo_header "═══════════════════════════════════════════════════════════════════════════"
    echo_header "   MONITORING CONFIGURATION"
    echo_header "═══════════════════════════════════════════════════════════════════════════"
    echo ""
    
    echo "Select services to monitor (adds exporters + Grafana dashboards):"
    echo ""
    
    # N8N - always recommended
    read -p "  Monitor N8N? (y/n) [y]: " MONITOR_N8N
    MONITOR_N8N=${MONITOR_N8N:-y}
    
    # Qdrant
    read -p "  Monitor Qdrant? (y/n) [y]: " MONITOR_QDRANT
    MONITOR_QDRANT=${MONITOR_QDRANT:-y}
    
    # Redis (if installed)
    if grep -q "redis:" docker-compose.yml 2>/dev/null; then
        read -p "  Monitor Redis? (y/n) [y]: " MONITOR_REDIS
        MONITOR_REDIS=${MONITOR_REDIS:-y}
    else
        MONITOR_REDIS="n"
    fi
    
    # PostgreSQL
    read -p "  Monitor PostgreSQL? (y/n) [n]: " MONITOR_POSTGRES
    MONITOR_POSTGRES=${MONITOR_POSTGRES:-n}
    
    # Chatwoot (if installed)
    if grep -q "chatwoot:" docker-compose.yml 2>/dev/null; then
        read -p "  Monitor Chatwoot? (y/n) [n]: " MONITOR_CHATWOOT
        MONITOR_CHATWOOT=${MONITOR_CHATWOOT:-n}
    else
        MONITOR_CHATWOOT="n"
    fi
    
    echo ""
    
    # Add exporters based on selection
    add_selected_exporters
    
    # Add dashboards based on selection
    add_selected_dashboards
    
    # Update Prometheus scrape config
    update_prometheus_config
    
    # Add alerting rules
    add_alerting_rules
    
    echo ""
    echo_success "Monitoring configuration complete!"
    echo_info "Restart services to apply: $DC restart prometheus grafana"
}

# =============================================================================
# ADD SELECTED EXPORTERS
# =============================================================================
add_selected_exporters() {
    echo ""
    echo_info "Adding exporters for selected services..."
    
    # Check if exporters section already exists
    if grep -q "# === MONITORING EXPORTERS" docker-compose.yml 2>/dev/null; then
        echo_warning "Exporters section already exists. Skipping."
        return
    fi
    
    # Start exporters section
    cat >> docker-compose.yml << 'EOF'

  # === MONITORING EXPORTERS (added by enhance script) ===
EOF

    # Redis exporter
    if [ "$MONITOR_REDIS" = "y" ]; then
        cat >> docker-compose.yml << EOF

  redis-exporter:
    image: oliver006/redis_exporter:latest
    container_name: ${CLIENT_NAME_SAFE}-redis-exporter
    environment:
      - REDIS_ADDR=redis://${CLIENT_NAME_SAFE}-redis:6379
      - REDIS_PASSWORD=\${REDIS_PASSWORD}
    ports:
      - "9121:9121"
    depends_on:
      - redis
    restart: unless-stopped
    networks:
      - rag-network
    profiles:
      - monitoring
EOF
        echo_success "  ✓ Redis exporter added"
    fi
    
    # PostgreSQL exporter
    if [ "$MONITOR_POSTGRES" = "y" ]; then
        cat >> docker-compose.yml << EOF

  postgres-exporter:
    image: prometheuscommunity/postgres-exporter:latest
    container_name: ${CLIENT_NAME_SAFE}-postgres-exporter
    environment:
      - DATA_SOURCE_NAME=postgresql://postgres:\${POSTGRES_PASSWORD}@${CLIENT_NAME_SAFE}-postgres:5432/postgres?sslmode=disable
    ports:
      - "9187:9187"
    depends_on:
      - postgres
    restart: unless-stopped
    networks:
      - rag-network
    profiles:
      - monitoring
EOF
        echo_success "  ✓ PostgreSQL exporter added"
    fi
}

# =============================================================================
# ADD SELECTED DASHBOARDS
# =============================================================================
add_selected_dashboards() {
    echo ""
    echo_info "Creating Grafana dashboards..."
    
    mkdir -p grafana/provisioning/dashboards
    
    # Dashboard provisioner config
    cat > grafana/provisioning/dashboards/default.yaml << 'EOF'
apiVersion: 1
providers:
  - name: 'RAG Stack Dashboards'
    orgId: 1
    folder: 'RAG Stack'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    options:
      path: /etc/grafana/provisioning/dashboards
EOF

    # N8N Dashboard
    if [ "$MONITOR_N8N" = "y" ]; then
        cat > grafana/provisioning/dashboards/n8n.json << 'EOF'
{
  "dashboard": {
    "title": "N8N Workflows",
    "uid": "n8n-workflows",
    "tags": ["n8n", "rag-stack"],
    "timezone": "browser",
    "refresh": "30s",
    "panels": [
      {
        "title": "Workflow Executions (24h)",
        "type": "stat",
        "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
        "targets": [{"expr": "sum(increase(n8n_workflow_execution_total[24h]))", "datasource": "Prometheus"}],
        "fieldConfig": {"defaults": {"unit": "short"}}
      },
      {
        "title": "Failed Executions (24h)",
        "type": "stat",
        "gridPos": {"h": 4, "w": 6, "x": 6, "y": 0},
        "targets": [{"expr": "sum(increase(n8n_workflow_execution_total{status=\"error\"}[24h]))", "datasource": "Prometheus"}],
        "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "thresholds"}, "thresholds": {"steps": [{"value": 0, "color": "green"}, {"value": 1, "color": "red"}]}}}
      },
      {
        "title": "Memory Usage",
        "type": "gauge",
        "gridPos": {"h": 4, "w": 6, "x": 12, "y": 0},
        "targets": [{"expr": "process_resident_memory_bytes{job=\"n8n\"}", "datasource": "Prometheus"}],
        "fieldConfig": {"defaults": {"unit": "bytes", "max": 4294967296}}
      },
      {
        "title": "Execution Rate",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 4},
        "targets": [{"expr": "rate(n8n_workflow_execution_total[5m])", "legendFormat": "{{status}}", "datasource": "Prometheus"}]
      },
      {
        "title": "N8N Logs",
        "type": "logs",
        "gridPos": {"h": 10, "w": 24, "x": 0, "y": 12},
        "targets": [{"expr": "{container_name=~\".*n8n.*\"}", "datasource": "Loki"}]
      }
    ],
    "schemaVersion": 38
  }
}
EOF
        echo_success "  ✓ N8N dashboard created"
    fi
    
    # Qdrant Dashboard
    if [ "$MONITOR_QDRANT" = "y" ]; then
        cat > grafana/provisioning/dashboards/qdrant.json << 'EOF'
{
  "dashboard": {
    "title": "Qdrant Vector DB",
    "uid": "qdrant-metrics",
    "tags": ["qdrant", "rag-stack"],
    "timezone": "browser",
    "refresh": "30s",
    "panels": [
      {
        "title": "Collections",
        "type": "stat",
        "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
        "targets": [{"expr": "qdrant_collections_total", "datasource": "Prometheus"}]
      },
      {
        "title": "Total Points",
        "type": "stat",
        "gridPos": {"h": 4, "w": 6, "x": 6, "y": 0},
        "targets": [{"expr": "sum(qdrant_points_total)", "datasource": "Prometheus"}]
      },
      {
        "title": "Search Requests/sec",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 4},
        "targets": [{"expr": "rate(qdrant_search_total[5m])", "datasource": "Prometheus"}]
      },
      {
        "title": "Qdrant Logs",
        "type": "logs",
        "gridPos": {"h": 10, "w": 24, "x": 0, "y": 12},
        "targets": [{"expr": "{container_name=~\".*qdrant.*\"}", "datasource": "Loki"}]
      }
    ],
    "schemaVersion": 38
  }
}
EOF
        echo_success "  ✓ Qdrant dashboard created"
    fi
    
    # Redis Dashboard
    if [ "$MONITOR_REDIS" = "y" ]; then
        cat > grafana/provisioning/dashboards/redis.json << 'EOF'
{
  "dashboard": {
    "title": "Redis",
    "uid": "redis-metrics",
    "tags": ["redis", "rag-stack"],
    "timezone": "browser",
    "refresh": "30s",
    "panels": [
      {
        "title": "Connected Clients",
        "type": "stat",
        "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
        "targets": [{"expr": "redis_connected_clients", "datasource": "Prometheus"}]
      },
      {
        "title": "Memory Usage",
        "type": "gauge",
        "gridPos": {"h": 4, "w": 6, "x": 6, "y": 0},
        "targets": [{"expr": "redis_memory_used_bytes", "datasource": "Prometheus"}],
        "fieldConfig": {"defaults": {"unit": "bytes", "max": 536870912}}
      },
      {
        "title": "Keys",
        "type": "stat",
        "gridPos": {"h": 4, "w": 6, "x": 12, "y": 0},
        "targets": [{"expr": "sum(redis_db_keys)", "datasource": "Prometheus"}]
      },
      {
        "title": "Commands/sec",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 4},
        "targets": [{"expr": "rate(redis_commands_processed_total[1m])", "datasource": "Prometheus"}]
      }
    ],
    "schemaVersion": 38
  }
}
EOF
        echo_success "  ✓ Redis dashboard created"
    fi
    
    # PostgreSQL Dashboard
    if [ "$MONITOR_POSTGRES" = "y" ]; then
        cat > grafana/provisioning/dashboards/postgresql.json << 'EOF'
{
  "dashboard": {
    "title": "PostgreSQL",
    "uid": "postgres-metrics",
    "tags": ["postgresql", "rag-stack"],
    "timezone": "browser",
    "refresh": "30s",
    "panels": [
      {
        "title": "Active Connections",
        "type": "stat",
        "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
        "targets": [{"expr": "pg_stat_activity_count", "datasource": "Prometheus"}]
      },
      {
        "title": "Database Size",
        "type": "stat",
        "gridPos": {"h": 4, "w": 6, "x": 6, "y": 0},
        "targets": [{"expr": "sum(pg_database_size_bytes)", "datasource": "Prometheus"}],
        "fieldConfig": {"defaults": {"unit": "bytes"}}
      },
      {
        "title": "Transactions/sec",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 4},
        "targets": [{"expr": "rate(pg_stat_database_xact_commit[1m])", "datasource": "Prometheus"}]
      }
    ],
    "schemaVersion": 38
  }
}
EOF
        echo_success "  ✓ PostgreSQL dashboard created"
    fi
    
    # System Overview Dashboard (always)
    cat > grafana/provisioning/dashboards/system-overview.json << 'EOF'
{
  "dashboard": {
    "title": "RAG Stack Overview",
    "uid": "rag-overview",
    "tags": ["system", "rag-stack"],
    "timezone": "browser",
    "refresh": "30s",
    "panels": [
      {
        "title": "Service Status",
        "type": "stat",
        "gridPos": {"h": 4, "w": 24, "x": 0, "y": 0},
        "targets": [{"expr": "up", "legendFormat": "{{job}}", "datasource": "Prometheus"}],
        "fieldConfig": {"defaults": {"mappings": [{"type": "value", "options": {"0": {"text": "DOWN", "color": "red"}, "1": {"text": "UP", "color": "green"}}}]}}
      },
      {
        "title": "All Container Logs",
        "type": "logs",
        "gridPos": {"h": 16, "w": 24, "x": 0, "y": 4},
        "targets": [{"expr": "{job=\"docker\"}", "datasource": "Loki"}]
      }
    ],
    "schemaVersion": 38
  }
}
EOF
    echo_success "  ✓ System overview dashboard created"
}

# =============================================================================
# UPDATE PROMETHEUS CONFIG
# =============================================================================
update_prometheus_config() {
    echo ""
    echo_info "Updating Prometheus scrape configuration..."
    
    # Backup existing config
    cp prometheus/prometheus.yml prometheus/prometheus.yml.bak 2>/dev/null || true
    
    cat > prometheus/prometheus.yml << EOF
# Prometheus Configuration (Enhanced)
# Generated by RAG Stack Enhancement Script

global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - /etc/prometheus/rules/*.yml

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF

    # Add N8N scrape
    if [ "$MONITOR_N8N" = "y" ]; then
        cat >> prometheus/prometheus.yml << EOF

  - job_name: 'n8n'
    static_configs:
      - targets: ['n8n:5678']
    metrics_path: '/metrics'
EOF
    fi
    
    # Add Qdrant scrape
    if [ "$MONITOR_QDRANT" = "y" ]; then
        cat >> prometheus/prometheus.yml << EOF

  - job_name: 'qdrant'
    static_configs:
      - targets: ['qdrant:6333']
    metrics_path: '/metrics'
EOF
    fi
    
    # Add Redis exporter scrape
    if [ "$MONITOR_REDIS" = "y" ]; then
        cat >> prometheus/prometheus.yml << EOF

  - job_name: 'redis'
    static_configs:
      - targets: ['${CLIENT_NAME_SAFE}-redis-exporter:9121']
EOF
    fi
    
    # Add PostgreSQL exporter scrape
    if [ "$MONITOR_POSTGRES" = "y" ]; then
        cat >> prometheus/prometheus.yml << EOF

  - job_name: 'postgresql'
    static_configs:
      - targets: ['${CLIENT_NAME_SAFE}-postgres-exporter:9187']
EOF
    fi
    
    # Add standard scrapes
    cat >> prometheus/prometheus.yml << EOF

  - job_name: 'grafana'
    static_configs:
      - targets: ['grafana:3000']

  - job_name: 'loki'
    static_configs:
      - targets: ['loki:3100']

  - job_name: 'otel-collector'
    static_configs:
      - targets: ['otel-collector:8888']

  - job_name: 'jaeger'
    static_configs:
      - targets: ['jaeger:8888']
EOF

    echo_success "  ✓ Prometheus configuration updated"
}

# =============================================================================
# ADD ALERTING RULES
# =============================================================================
add_alerting_rules() {
    echo ""
    echo_info "Creating alerting rules..."
    
    mkdir -p prometheus/rules
    
    cat > prometheus/rules/rag-stack.yml << 'EOF'
groups:
  - name: rag-stack-alerts
    interval: 30s
    rules:
      - alert: ServiceDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Service {{ $labels.job }} is down"
          
      - alert: HighMemoryUsage
        expr: process_resident_memory_bytes > 3221225472
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.job }}"
          
      - alert: N8NHighErrorRate
        expr: rate(n8n_workflow_execution_total{status="error"}[5m]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "N8N high error rate"
EOF

    # Add Redis alerts if monitoring
    if [ "$MONITOR_REDIS" = "y" ]; then
        cat >> prometheus/rules/rag-stack.yml << 'EOF'
          
      - alert: RedisDown
        expr: redis_up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Redis is down"
          
      - alert: RedisHighMemory
        expr: redis_memory_used_bytes / redis_memory_max_bytes > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Redis memory usage above 80%"
EOF
    fi
    
    # Add PostgreSQL alerts if monitoring
    if [ "$MONITOR_POSTGRES" = "y" ]; then
        cat >> prometheus/rules/rag-stack.yml << 'EOF'
          
      - alert: PostgreSQLDown
        expr: pg_up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "PostgreSQL is down"
          
      - alert: PostgreSQLHighConnections
        expr: pg_stat_activity_count > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "PostgreSQL connection count high"
EOF
    fi

    echo_success "  ✓ Alerting rules created"
}

# =============================================================================
# UFW FIREWALL CONFIGURATION
# =============================================================================
configure_ufw() {
    echo ""
    echo_header "═══════════════════════════════════════════════════════════════════════════"
    echo_header "   UFW FIREWALL CONFIGURATION"
    echo_header "═══════════════════════════════════════════════════════════════════════════"
    echo ""
    
    # Check if UFW is installed
    if ! command -v ufw &> /dev/null; then
        echo_warning "UFW is not installed. Installing..."
        sudo apt-get update && sudo apt-get install -y ufw
    fi
    
    echo "This will configure UFW firewall rules for your RAG stack."
    echo ""
    echo "Default rules:"
    echo "  ✓ Allow SSH (22)"
    echo "  ✓ Allow N8N (${PORT_N8N:-5678})"
    echo ""
    echo "Optional rules:"
    
    read -p "  Allow Grafana externally? (${PORT_GRAFANA:-3000}) (y/n) [n]: " ALLOW_GRAFANA
    ALLOW_GRAFANA=${ALLOW_GRAFANA:-n}
    
    read -p "  Allow Jaeger UI externally? (${PORT_JAEGER:-16686}) (y/n) [n]: " ALLOW_JAEGER
    ALLOW_JAEGER=${ALLOW_JAEGER:-n}
    
    read -p "  Allow Qdrant externally? (${PORT_QDRANT:-6333}) (y/n) [n]: " ALLOW_QDRANT
    ALLOW_QDRANT=${ALLOW_QDRANT:-n}
    
    if grep -q "chatwoot:" docker-compose.yml 2>/dev/null; then
        read -p "  Allow Chatwoot externally? (${PORT_CHATWOOT:-3001}) (y/n) [y]: " ALLOW_CHATWOOT
        ALLOW_CHATWOOT=${ALLOW_CHATWOOT:-y}
    else
        ALLOW_CHATWOOT="n"
    fi
    
    echo ""
    read -p "Apply these rules now? (y/n) [y]: " APPLY_UFW
    APPLY_UFW=${APPLY_UFW:-y}
    
    if [ "$APPLY_UFW" = "y" ]; then
        echo ""
        echo_info "Configuring UFW..."
        
        # Reset UFW (with confirmation bypass)
        sudo ufw --force reset
        
        # Default policies
        sudo ufw default deny incoming
        sudo ufw default allow outgoing
        
        # Always allow SSH
        sudo ufw allow 22/tcp comment 'SSH'
        echo_success "  ✓ SSH (22) allowed"
        
        # Always allow N8N
        sudo ufw allow ${PORT_N8N:-5678}/tcp comment 'N8N'
        echo_success "  ✓ N8N (${PORT_N8N:-5678}) allowed"
        
        # Optional rules
        if [ "$ALLOW_GRAFANA" = "y" ]; then
            sudo ufw allow ${PORT_GRAFANA:-3000}/tcp comment 'Grafana'
            echo_success "  ✓ Grafana (${PORT_GRAFANA:-3000}) allowed"
        fi
        
        if [ "$ALLOW_JAEGER" = "y" ]; then
            sudo ufw allow ${PORT_JAEGER:-16686}/tcp comment 'Jaeger'
            echo_success "  ✓ Jaeger (${PORT_JAEGER:-16686}) allowed"
        fi
        
        if [ "$ALLOW_QDRANT" = "y" ]; then
            sudo ufw allow ${PORT_QDRANT:-6333}/tcp comment 'Qdrant'
            echo_success "  ✓ Qdrant (${PORT_QDRANT:-6333}) allowed"
        fi
        
        if [ "$ALLOW_CHATWOOT" = "y" ]; then
            sudo ufw allow ${PORT_CHATWOOT:-3001}/tcp comment 'Chatwoot'
            echo_success "  ✓ Chatwoot (${PORT_CHATWOOT:-3001}) allowed"
        fi
        
        # Enable UFW
        sudo ufw --force enable
        
        echo ""
        echo_success "UFW firewall configured and enabled!"
        echo ""
        echo_info "Current rules:"
        sudo ufw status numbered
    else
        echo_warning "UFW configuration skipped"
    fi
}

# =============================================================================
# SECURE QDRANT
# =============================================================================
secure_qdrant() {
    echo ""
    echo_header "═══════════════════════════════════════════════════════════════════════════"
    echo_header "   QDRANT SECURITY"
    echo_header "═══════════════════════════════════════════════════════════════════════════"
    echo ""
    
    # Check if already secured
    if grep -q "QDRANT_API_KEY" .env 2>/dev/null; then
        echo_warning "Qdrant API key already configured in .env"
        EXISTING_KEY=$(grep "QDRANT_API_KEY" .env | cut -d'=' -f2)
        echo "Existing key: ${EXISTING_KEY}"
        read -p "Generate new key? (y/n) [n]: " REGEN_KEY
        if [ "$REGEN_KEY" != "y" ]; then
            return
        fi
    fi
    
    # Generate API key
    QDRANT_API_KEY=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)
    
    # Add to .env
    if grep -q "QDRANT_API_KEY" .env 2>/dev/null; then
        sed -i "s/QDRANT_API_KEY=.*/QDRANT_API_KEY=${QDRANT_API_KEY}/" .env
    else
        echo "" >> .env
        echo "# Qdrant Security (added by enhance script)" >> .env
        echo "QDRANT_API_KEY=${QDRANT_API_KEY}" >> .env
    fi
    
    # Create Qdrant config
    mkdir -p qdrant
    cat > qdrant/config.yaml << EOF
service:
  api_key: ${QDRANT_API_KEY}
  
storage:
  storage_path: /qdrant/storage
  
log_level: INFO
EOF
    
    echo_success "Qdrant API key generated: ${QDRANT_API_KEY}"
    echo ""
    echo_warning "IMPORTANT: You need to update docker-compose.yml to mount the config."
    echo ""
    echo "Add this to the qdrant service volumes:"
    echo "  - ./qdrant/config.yaml:/qdrant/config/config.yaml:ro"
    echo ""
    echo "Then restart Qdrant: $DC restart qdrant"
    echo ""
    echo "Use this key when adding Qdrant credentials in N8N!"
    
    # Update CREDENTIALS.txt
    if ! grep -q "QDRANT" CREDENTIALS.txt 2>/dev/null; then
        echo "" >> CREDENTIALS.txt
        echo "=== QDRANT (added by enhance script) ===" >> CREDENTIALS.txt
        echo "API Key: ${QDRANT_API_KEY}" >> CREDENTIALS.txt
        echo_success "API key added to CREDENTIALS.txt"
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

case $MAIN_CHOICE in
    1)
        configure_monitoring
        ;;
    2)
        configure_ufw
        ;;
    3)
        secure_qdrant
        ;;
    4)
        configure_monitoring
        configure_ufw
        secure_qdrant
        ;;
    5)
        echo "Exiting..."
        exit 0
        ;;
    *)
        echo_error "Invalid choice"
        exit 1
        ;;
esac

echo ""
echo "==============================================================================="
echo "   Enhancement Complete"
echo "==============================================================================="
echo ""
echo "Next steps:"
if [ "$MONITOR_REDIS" = "y" ] || [ "$MONITOR_POSTGRES" = "y" ]; then
    echo "  1. Start exporters: $DC --profile monitoring up -d"
fi
echo "  2. Restart services: $DC restart prometheus grafana"
echo "  3. Access Grafana to see new dashboards"
echo ""
