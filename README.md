# RAG Stack Installer

One-command installer for a production-ready RAG (Retrieval-Augmented Generation) stack with N8N workflow automation, vector database, observability, and optional customer support platform.

![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-blue)
![Docker](https://img.shields.io/badge/docker-required-blue)
![License](https://img.shields.io/badge/license-MIT-green)

> ⚠️ **Windows Version:** The Windows installer (`RAG_Stack_Windows_Installer.bat`) is currently **untested**. It has been ported from the Linux/macOS version but has not been validated in a Windows environment. Please report any issues you encounter.

## What You Get

| Component | Description |
|-----------|-------------|
| **PostgreSQL 16** | Main database with pgvector extension for embeddings |
| **N8N v2** | Workflow automation platform with 400+ integrations |
| **Qdrant** | High-performance vector database for RAG |
| **Redis 8** | In-memory cache (for queue mode or Chatwoot) |
| **Chatwoot** | Customer support platform (optional) |
| **Prometheus + Grafana** | Metrics and dashboards |
| **Jaeger** | Distributed tracing (full observability) |
| **Loki + Alloy** | Log aggregation (full observability) |
| **OpenTelemetry** | Telemetry collection (full observability) |

## Quick Start

### Linux / macOS

```bash
chmod +x rag_stack_full_installer.sh
./rag_stack_full_installer.sh
```

### Windows (Untested)

```cmd
RAG_Stack_Windows_Installer.bat
```

> ⚠️ The Windows installer has not been tested. Please report issues if you try it.

Follow the interactive prompts to configure your stack.

## Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| **Docker** | Docker 20.10+ | Docker 24+ |
| **Docker Compose** | v2.0+ | v2.20+ |
| **RAM** | 8 GB | 16 GB |
| **Disk** | 20 GB | 50 GB |
| **OS** | Ubuntu 20.04+ / macOS 12+ / Windows 10+ | Ubuntu 22.04 / macOS 14 / Windows 11 |

## Installation Options

### SSL Configuration

| Option | Use Case |
|--------|----------|
| **Self-signed HTTPS** | Local development, internal networks |
| **Let's Encrypt** | Production with public domain |

> **Note:** HTTP-only is not offered. Many external services (Telegram, Shopify, etc.) require HTTPS for webhooks to function.

### N8N Execution Mode

| Mode | Description |
|------|-------------|
| **Single Instance** | Simple setup, lower resources |
| **Queue Mode** | Scalable with Redis + workers, better for high-volume workflows |

### Observability Levels

| Level | Components | RAM Usage |
|-------|------------|-----------|
| **None** | Docker logs only | +0 GB |
| **Lite** | Prometheus + Grafana | +1.5 GB |
| **Full** | Prometheus + Grafana + Jaeger + Loki + OTel + Alloy | +4 GB |

## Generated Files

After installation, your directory contains:

```
rag-stack-{client}/
├── docker-compose.yml      # Service definitions
├── .env                    # Environment variables (KEEP SECURE)
├── CREDENTIALS.txt         # All passwords (KEEP SECURE)
├── README.md               # Local documentation
├── welcome.html            # Browser quick-start guide
├── .gitignore              # Protects sensitive files
│
├── start.sh / start.bat    # Start all services
├── stop.sh / stop.bat      # Stop all services
├── status.sh / status.bat  # Check service status
├── logs.sh / logs.bat      # View service logs
├── restart.sh / restart.bat
├── enhance.sh / enhance.bat    # Add exporters, firewall, security
├── toggle-n8n-queue.sh / .bat  # Switch execution modes
├── renew-ssl.sh / .bat         # Renew Let's Encrypt (if enabled)
│
├── ssl/                    # SSL certificates
├── prometheus/             # Prometheus config
├── grafana/                # Grafana provisioning
├── loki/                   # Loki config (full observability)
├── alloy/                  # Alloy config (full observability)
└── init-sql/               # Database initialization
```

## Service URLs

After installation, access your services at:

| Service | URL | Credentials |
|---------|-----|-------------|
| **N8N** | http://localhost:5678 | Create on first visit |
| **Qdrant** | http://localhost:6333 | None (run enhance to add API key) |
| **Grafana** | http://localhost:3001 | admin / (see CREDENTIALS.txt) |
| **Chatwoot** | http://localhost:3000 | Create on first visit |
| **Jaeger** | http://localhost:16686 | None |
| **Prometheus** | http://localhost:9090 | None |

## Post-Installation

### 1. Open Welcome Page

The installer will prompt to open `welcome.html` - a quick-start guide with links to all services.

### 2. Create N8N Account

Visit N8N and create your admin account on first access.

### 3. Run Enhancement Script (Recommended)

```bash
# Linux/macOS
./enhance.sh

# Windows
enhance.bat
```

This adds:
- **Monitoring exporters** (Redis, PostgreSQL) for Grafana dashboards
- **Firewall rules** (UFW on Linux, Windows Firewall)
- **Qdrant API key** for security

### 4. Connect N8N to Qdrant

In N8N, add Qdrant credentials:
- **URL:** `http://{client-name}-qdrant:6333`
- **API Key:** (from enhance script, if enabled)

### 5. Connect to Local LLMs

If using LM Studio or Ollama on the host machine:

```
# LM Studio
http://host.docker.internal:1234/v1

# Ollama
http://host.docker.internal:11434
```

## Management Commands

### Daily Operations

```bash
# Start all services
./start.sh          # Linux/macOS
start.bat           # Windows

# Stop all services
./stop.sh           # Linux/macOS
stop.bat            # Windows

# Check status
./status.sh         # Linux/macOS
status.bat          # Windows

# View logs
./logs.sh           # Linux/macOS
logs.bat            # Windows
```

### Scaling N8N Workers (Queue Mode)

```bash
# Scale to 4 workers
docker compose --profile n8n-queue up -d --scale n8n-worker=4
```

### Toggle N8N Execution Mode

```bash
./toggle-n8n-queue.sh   # Linux/macOS
toggle-n8n-queue.bat    # Windows
```

### Renew SSL Certificate (Let's Encrypt)

```bash
./renew-ssl.sh          # Linux/macOS
renew-ssl.bat           # Windows
```

## ⚠️ Security Notice

**This installer creates a basic setup suitable for development and internal use.** If you plan to expose services to the public internet, you should explore additional security measures.

### What This Installer Does NOT Include

| Security Layer | Description | Examples |
|----------------|-------------|----------|
| **Rate Limiting** | Protection against brute-force attacks | Fail2ban, Cloudflare |
| **Authentication Proxy** | SSO, 2FA | Authelia, Authentik |
| **WAF** | Web Application Firewall | Cloudflare, ModSecurity |
| **DDoS Protection** | Denial of service mitigation | Cloudflare |
| **Reverse Proxy** | TLS termination, routing | Traefik, Caddy, Nginx |
| **Network Isolation** | Zero-trust networking | Cloudflare Tunnel, Tailscale |

Please research these options and their compatibility with your setup before deploying to production.

## Security Recommendations

1. **Run the enhancement script** to configure firewall rules
2. **Generate Qdrant API key** via enhancement script
3. **Change Grafana password** on first login
4. **Keep `.env` and `CREDENTIALS.txt` secure** - never commit to git
5. **Use HTTPS** for production deployments

### Port Exposure Guide

| Service | Expose Externally? | Notes |
|---------|-------------------|-------|
| N8N | ✅ Yes | User-facing, use HTTPS |
| Grafana | ⚠️ Optional | Only if remote monitoring needed |
| Jaeger | ⚠️ Optional | Development/debugging only |
| Qdrant | ⚠️ Optional | Only if external apps need access |
| PostgreSQL | ❌ No | Keep internal |
| Redis | ❌ No | Keep internal |
| Prometheus | ❌ No | Keep internal |

## Troubleshooting

### Services Won't Start

```bash
# Check container status
docker compose ps

# View logs for specific service
docker compose logs n8n
docker compose logs postgres
```

### Database Connection Issues

```bash
# Test PostgreSQL
docker exec {client}-postgres pg_isready -U postgres

# Test Redis
docker exec {client}-redis redis-cli -a {password} ping
```

### Port Already in Use

The Linux/macOS installer automatically finds available ports. For Windows, manually change ports in `docker-compose.yml` if conflicts occur.

### Reset Everything

```bash
# Stop and remove containers + volumes (DATA LOSS!)
docker compose down -v

# Restart fresh
./start.sh
```

## File Descriptions

| File | Description |
|------|-------------|
| `rag_stack_full_installer.sh` | Main installer for Linux/macOS (3,500+ lines) - **Tested** |
| `rag_stack_enhance.sh` | Standalone enhancement script for Linux/macOS - **Tested** |
| `RAG_Stack_Windows_Installer.bat` | Complete installer for Windows (1,800+ lines) - **Untested** |

> **Note:** The Windows installer was ported from the bash version and includes all the same features, but has not been tested in a real Windows environment. Contributions and bug reports welcome!

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Requests                            │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      N8N (Port 5678)                             │
│                   Workflow Automation                            │
│         ┌──────────┬──────────┬──────────┐                      │
│         │ Webhooks │ Triggers │ Actions  │                      │
│         └────┬─────┴────┬─────┴────┬─────┘                      │
└──────────────┼──────────┼──────────┼────────────────────────────┘
               │          │          │
    ┌──────────┘          │          └──────────┐
    ▼                     ▼                     ▼
┌────────────┐    ┌──────────────┐    ┌─────────────────┐
│ PostgreSQL │    │    Qdrant    │    │  External APIs  │
│  (5432)    │    │   (6333)     │    │  LLMs, etc.     │
│            │    │              │    │                 │
│ • N8N data │    │ • Vectors    │    │ • OpenAI        │
│ • Chatwoot │    │ • Embeddings │    │ • LM Studio     │
│ • pgvector │    │ • RAG search │    │ • Ollama        │
└────────────┘    └──────────────┘    └─────────────────┘
               
┌─────────────────────────────────────────────────────────────────┐
│                    Observability Stack                           │
├─────────────┬─────────────┬─────────────┬───────────────────────┤
│ Prometheus  │   Grafana   │   Jaeger    │    Loki + Alloy       │
│  (9090)     │   (3001)    │  (16686)    │      (3100)           │
│             │             │             │                        │
│ • Metrics   │ • Dashboards│ • Traces    │ • Logs                │
│ • Alerts    │ • Viz       │ • Spans     │ • Aggregation         │
└─────────────┴─────────────┴─────────────┴───────────────────────┘
```

## Contributing

Issues and pull requests are welcome!

### Particularly Needed

- **Windows testing** - The Windows installer needs real-world validation
- **Bug reports** - Especially for edge cases and different OS versions
- **Security improvements** - Additional hardening suggestions

### Before Submitting

1. Test on a clean system if possible
2. Include your OS version and Docker version in bug reports
3. For Windows issues, include any error messages from the command prompt

## License

MIT License - See LICENSE file for details.

## Acknowledgments

- [N8N](https://n8n.io/) - Workflow automation
- [Qdrant](https://qdrant.tech/) - Vector database
- [Chatwoot](https://www.chatwoot.com/) - Customer support
- [Grafana Labs](https://grafana.com/) - Observability stack
