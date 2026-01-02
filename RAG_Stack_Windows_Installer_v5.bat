@echo off
REM RAG Stack Windows Installer v5.0
REM Features: Observability modes, N8N queue mode, optional Chatwoot, Jaeger/Loki/OTel

setlocal enabledelayedexpansion

REM Create log file
set logfile=rag_installer_%RANDOM%.log

echo =============================================================================== > %logfile%
echo    RAG Stack Installer Log - %date% %time% >> %logfile%
echo =============================================================================== >> %logfile%

echo ===============================================================================
echo    RAG Stack Installer for Windows v5.0
echo    Full Observability Stack with Queue Mode Support
echo ===============================================================================
echo.

REM Check Docker
echo [STEP] Checking Docker...
docker --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Docker not found. Please install Docker Desktop and try again.
    pause
    exit /b 1
)

docker info >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Docker not running. Please start Docker Desktop and try again.
    pause
    exit /b 1
)
echo [OK] Docker is ready
echo [LOG] Docker is running >> %logfile%

REM ============================================================================
REM CLIENT INFORMATION
REM ============================================================================
echo.
echo [STEP] Client Information
echo.

:get_client_name
set /p CLIENT_NAME="Client/Company name: "
if "%CLIENT_NAME%"=="" (
    echo Please enter a client name.
    goto get_client_name
)
echo [LOG] Client name: "%CLIENT_NAME%" >> %logfile%

REM ============================================================================
REM SSL CONFIGURATION
REM ============================================================================
echo.
echo SSL Configuration:
echo   1. HTTP only (recommended for local development)
echo   2. HTTPS with self-signed certificate
echo   3. HTTPS with Let's Encrypt (requires domain + port 80)
echo.

:get_ssl_choice
set /p SSL_CHOICE="Choose option (1-3) [1]: "
if "%SSL_CHOICE%"=="" set SSL_CHOICE=1

if "%SSL_CHOICE%"=="2" (
    set USE_SSL=self-signed
    set PROTOCOL=https
    set CLIENT_DOMAIN=localhost
) else if "%SSL_CHOICE%"=="3" (
    set USE_SSL=letsencrypt
    set PROTOCOL=https
    set /p CLIENT_DOMAIN="Enter your domain name: "
    if "!CLIENT_DOMAIN!"=="" set CLIENT_DOMAIN=localhost
    :get_le_email
    set /p LETSENCRYPT_EMAIL="Enter email for Let's Encrypt: "
    if "!LETSENCRYPT_EMAIL!"=="" (
        echo Email is required for Let's Encrypt.
        goto get_le_email
    )
) else (
    set USE_SSL=no
    set PROTOCOL=http
    set CLIENT_DOMAIN=localhost
)
echo [LOG] SSL: %USE_SSL%, Protocol: %PROTOCOL% >> %logfile%

REM ============================================================================
REM OPTIONAL COMPONENTS
REM ============================================================================
echo.
echo [STEP] Optional Components
echo.

REM Chatwoot
set /p INSTALL_CHATWOOT="Install Chatwoot (customer support platform)? (y/N): "
if /i "%INSTALL_CHATWOOT%"=="y" (
    set INSTALL_CHATWOOT=y
    echo [LOG] Chatwoot: enabled >> %logfile%
) else (
    set INSTALL_CHATWOOT=n
    echo [LOG] Chatwoot: disabled >> %logfile%
)

REM N8N Queue Mode
echo.
echo N8N Execution Mode:
echo   1. Single instance (simple, uses less resources)
echo   2. Queue mode with workers (scalable, requires Redis)
echo.
set /p N8N_MODE="Choose mode (1-2) [1]: "
if "%N8N_MODE%"=="" set N8N_MODE=1

if "%N8N_MODE%"=="2" (
    set N8N_QUEUE_MODE=true
    set INSTALL_REDIS=true
    set /p N8N_WORKERS="Number of workers (1-4) [2]: "
    if "!N8N_WORKERS!"=="" set N8N_WORKERS=2
    echo [LOG] N8N: Queue mode with !N8N_WORKERS! workers >> %logfile%
) else (
    set N8N_QUEUE_MODE=false
    set N8N_WORKERS=0
    REM Redis still needed if Chatwoot is installed
    if "%INSTALL_CHATWOOT%"=="y" (
        set INSTALL_REDIS=true
    ) else (
        set INSTALL_REDIS=false
    )
    echo [LOG] N8N: Single instance mode >> %logfile%
)

REM ============================================================================
REM OBSERVABILITY MODE
REM ============================================================================
echo.
echo Observability Mode:
echo   1. None     - Just docker logs (minimal resources)
echo   2. Lite     - Prometheus + Grafana (basic metrics)
echo   3. Full     - Prometheus + Grafana + Loki + Jaeger + OTel (production debugging)
echo.
echo Resource usage:
echo   None: +0GB RAM
echo   Lite: +1.5GB RAM
echo   Full: +4GB RAM
echo.

set /p OBS_MODE="Choose mode (1-3) [2]: "
if "%OBS_MODE%"=="" set OBS_MODE=2

if "%OBS_MODE%"=="1" (
    set INSTALL_OBSERVABILITY=none
) else if "%OBS_MODE%"=="3" (
    set INSTALL_OBSERVABILITY=full
) else (
    set INSTALL_OBSERVABILITY=lite
)
echo [LOG] Observability: %INSTALL_OBSERVABILITY% >> %logfile%

REM ============================================================================
REM PROCESS CLIENT NAME
REM ============================================================================
echo.
echo [STEP] Processing configuration...

set CLIENT_NAME_SAFE=%CLIENT_NAME%

REM Convert to lowercase
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:A=a%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:B=b%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:C=c%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:D=d%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:E=e%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:F=f%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:G=g%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:H=h%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:I=i%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:J=j%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:K=k%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:L=l%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:M=m%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:N=n%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:O=o%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:P=p%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:Q=q%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:R=r%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:S=s%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:T=t%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:U=u%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:V=v%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:W=w%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:X=x%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:Y=y%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:Z=z%

REM Replace special characters
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE: =-%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:.=-%
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:_=-%

REM Remove consecutive hyphens
:remove_hyphens
set "temp=%CLIENT_NAME_SAFE%"
set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:--=-%
if not "%temp%"=="%CLIENT_NAME_SAFE%" goto remove_hyphens

REM Remove leading/trailing hyphens
if "%CLIENT_NAME_SAFE:~0,1%"=="-" set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:~1%
if "%CLIENT_NAME_SAFE:~-1%"=="-" set CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE:~0,-1%
if "%CLIENT_NAME_SAFE%"=="" set CLIENT_NAME_SAFE=default-client

set INSTALL_DIR=C:\rag-stack-%CLIENT_NAME_SAFE%

REM ============================================================================
REM INSTALLATION SUMMARY
REM ============================================================================
echo.
echo ===============================================================================
echo    Installation Summary
echo ===============================================================================
echo.
echo Client:        %CLIENT_NAME%
echo Safe name:     %CLIENT_NAME_SAFE%
echo Location:      %INSTALL_DIR%
echo.
echo SSL:           %USE_SSL%
echo Protocol:      %PROTOCOL%
echo Domain:        %CLIENT_DOMAIN%
echo.
echo Components:
echo   - PostgreSQL 16 with pgvector
echo   - N8N v2 (%N8N_QUEUE_MODE% queue mode)
if "%N8N_QUEUE_MODE%"=="true" echo     - Workers: %N8N_WORKERS%
echo   - Qdrant (vector database)
if "%INSTALL_REDIS%"=="true" echo   - Redis 8.4
if "%INSTALL_CHATWOOT%"=="y" echo   - Chatwoot (customer support)
echo.
echo Observability: %INSTALL_OBSERVABILITY%
if "%INSTALL_OBSERVABILITY%"=="lite" (
    echo   - Prometheus + Grafana
)
if "%INSTALL_OBSERVABILITY%"=="full" (
    echo   - Prometheus + Grafana
    echo   - Jaeger (distributed tracing)
    echo   - Loki + Alloy (log aggregation)
    echo   - OpenTelemetry Collector
)
echo.
echo ===============================================================================

set /p PROCEED="Continue with installation? (Y/n): "
if /i "%PROCEED%"=="n" (
    echo Installation cancelled.
    pause
    exit /b 0
)

REM ============================================================================
REM CLEANUP AND SETUP
REM ============================================================================
echo.
echo [STEP] Setting up installation directory...

if exist "%INSTALL_DIR%" (
    cd /d "%INSTALL_DIR%"
    docker-compose down -v >nul 2>&1
    cd /d "%USERPROFILE%"
)

if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
cd /d "%INSTALL_DIR%"

REM Create directories
mkdir ssl >nul 2>&1
mkdir prometheus >nul 2>&1
mkdir prometheus\rules >nul 2>&1
mkdir grafana\provisioning\dashboards >nul 2>&1
mkdir grafana\provisioning\datasources >nul 2>&1
mkdir init-sql >nul 2>&1
if "%INSTALL_OBSERVABILITY%"=="full" (
    mkdir loki >nul 2>&1
    mkdir alloy >nul 2>&1
)

REM ============================================================================
REM GENERATE PASSWORDS
REM ============================================================================
echo [STEP] Generating secure passwords...

set POSTGRES_PASS=pg_%RANDOM%%RANDOM%%RANDOM%
set POSTGRES_N8N_PASS=n8n_%RANDOM%%RANDOM%%RANDOM%
set POSTGRES_CHATWOOT_PASS=cw_%RANDOM%%RANDOM%%RANDOM%
set REDIS_PASS=redis_%RANDOM%%RANDOM%%RANDOM%
set GRAFANA_PASS=admin_%RANDOM%%RANDOM%%RANDOM%
set CHATWOOT_SECRET=secret_%RANDOM%%RANDOM%%RANDOM%%RANDOM%
set N8N_ENCRYPTION_KEY=encrypt_%RANDOM%%RANDOM%%RANDOM%%RANDOM%

REM ============================================================================
REM SSL CERTIFICATES
REM ============================================================================
if "%USE_SSL%"=="self-signed" (
    echo [STEP] Generating self-signed SSL certificate...
    docker run --rm -v "%CD%\ssl:/certs" alpine/openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /certs/privkey.pem -out /certs/fullchain.pem -subj "/CN=%CLIENT_DOMAIN%/O=%CLIENT_NAME%/C=US" >nul 2>&1
    docker run --rm -v "%CD%\ssl:/certs" alpine chmod 644 /certs/privkey.pem /certs/fullchain.pem
    
    if not exist "ssl\privkey.pem" (
        echo [ERROR] Failed to generate SSL certificate
        pause
        exit /b 1
    )
    echo [OK] SSL certificate generated
)

if "%USE_SSL%"=="letsencrypt" (
    echo [STEP] Obtaining Let's Encrypt certificate for %CLIENT_DOMAIN%...
    echo.
    echo [WARNING] Ensure the following before continuing:
    echo   1. Port 80 is open and accessible from the internet
    echo   2. %CLIENT_DOMAIN% DNS points to this server
    echo.
    set /p LE_CONTINUE="Continue with Let's Encrypt? (Y/n): "
    if /i "!LE_CONTINUE!"=="n" (
        echo Falling back to self-signed certificate...
        set USE_SSL=self-signed
        docker run --rm -v "%CD%\ssl:/certs" alpine/openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /certs/privkey.pem -out /certs/fullchain.pem -subj "/CN=%CLIENT_DOMAIN%/O=%CLIENT_NAME%/C=US" >nul 2>&1
        docker run --rm -v "%CD%\ssl:/certs" alpine chmod 644 /certs/privkey.pem /certs/fullchain.pem
    ) else (
        mkdir letsencrypt >nul 2>&1
        
        echo Running Certbot to obtain certificate...
        docker run --rm -it -v "%CD%\ssl:/etc/letsencrypt/live/%CLIENT_DOMAIN%" -v "%CD%\letsencrypt:/etc/letsencrypt" -p 80:80 certbot/certbot certonly --standalone --non-interactive --agree-tos --email %LETSENCRYPT_EMAIL% -d %CLIENT_DOMAIN%
        
        if exist "letsencrypt\live\%CLIENT_DOMAIN%\privkey.pem" (
            copy /Y "letsencrypt\live\%CLIENT_DOMAIN%\privkey.pem" "ssl\privkey.pem" >nul
            copy /Y "letsencrypt\live\%CLIENT_DOMAIN%\fullchain.pem" "ssl\fullchain.pem" >nul
            echo [OK] Let's Encrypt certificate obtained for %CLIENT_DOMAIN%
        ) else (
            echo [WARNING] Let's Encrypt failed. Falling back to self-signed...
            set USE_SSL=self-signed
            docker run --rm -v "%CD%\ssl:/certs" alpine/openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /certs/privkey.pem -out /certs/fullchain.pem -subj "/CN=%CLIENT_DOMAIN%/O=%CLIENT_NAME%/C=US" >nul 2>&1
            docker run --rm -v "%CD%\ssl:/certs" alpine chmod 644 /certs/privkey.pem /certs/fullchain.pem
        )
    )
)

REM ============================================================================
REM CREATE .ENV FILE
REM ============================================================================
echo [STEP] Creating configuration files...

(
echo # RAG Stack Configuration for %CLIENT_NAME%
echo CLIENT_NAME=%CLIENT_NAME%
echo CLIENT_NAME_SAFE=%CLIENT_NAME_SAFE%
echo DOMAIN=%CLIENT_DOMAIN%
echo USE_SSL=%USE_SSL%
echo PROTOCOL=%PROTOCOL%
echo.
echo # Passwords
echo POSTGRES_PASSWORD=%POSTGRES_PASS%
echo POSTGRES_N8N_PASSWORD=%POSTGRES_N8N_PASS%
echo POSTGRES_CHATWOOT_PASSWORD=%POSTGRES_CHATWOOT_PASS%
echo REDIS_PASSWORD=%REDIS_PASS%
echo GRAFANA_PASSWORD=%GRAFANA_PASS%
echo CHATWOOT_SECRET_KEY=%CHATWOOT_SECRET%
echo N8N_ENCRYPTION_KEY=%N8N_ENCRYPTION_KEY%
echo.
echo # Settings
echo N8N_QUEUE_MODE=%N8N_QUEUE_MODE%
echo N8N_WORKERS=%N8N_WORKERS%
echo INSTALL_REDIS=%INSTALL_REDIS%
echo INSTALL_OBSERVABILITY=%INSTALL_OBSERVABILITY%
echo INSTALL_CHATWOOT=%INSTALL_CHATWOOT%
echo.
echo COMPOSE_PROJECT_NAME=rag-stack-%CLIENT_NAME_SAFE%
) > .env

REM ============================================================================
REM CREATE SQL INITIALIZATION
REM ============================================================================
(
echo -- Database initialization for %CLIENT_NAME%
echo CREATE EXTENSION IF NOT EXISTS vector;
echo.
echo SELECT 'CREATE DATABASE n8n' WHERE NOT EXISTS ^(SELECT FROM pg_database WHERE datname = 'n8n'^)\gexec
if "%INSTALL_CHATWOOT%"=="y" (
    echo SELECT 'CREATE DATABASE chatwoot' WHERE NOT EXISTS ^(SELECT FROM pg_database WHERE datname = 'chatwoot'^)\gexec
)
echo.
echo DROP USER IF EXISTS n8n_user;
echo CREATE USER n8n_user WITH ENCRYPTED PASSWORD '%POSTGRES_N8N_PASS%';
echo GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n_user;
if "%INSTALL_CHATWOOT%"=="y" (
    echo.
    echo DROP USER IF EXISTS chatwoot_user;
    echo CREATE USER chatwoot_user WITH SUPERUSER ENCRYPTED PASSWORD '%POSTGRES_CHATWOOT_PASS%';
    echo GRANT ALL PRIVILEGES ON DATABASE chatwoot TO chatwoot_user;
)
echo.
echo \c n8n
echo GRANT ALL ON SCHEMA public TO n8n_user;
echo ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO n8n_user;
echo ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO n8n_user;
if "%INSTALL_CHATWOOT%"=="y" (
    echo.
    echo \c chatwoot
    echo GRANT ALL ON SCHEMA public TO chatwoot_user;
    echo ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO chatwoot_user;
    echo ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO chatwoot_user;
)
echo.
echo \c postgres
echo SELECT 'Database initialization completed' AS status;
) > init-sql\01-init.sql

REM ============================================================================
REM CREATE PROMETHEUS CONFIG
REM ============================================================================
if not "%INSTALL_OBSERVABILITY%"=="none" (
    (
    echo global:
    echo   scrape_interval: 15s
    echo   evaluation_interval: 15s
    echo.
    echo scrape_configs:
    echo   - job_name: 'prometheus'
    echo     static_configs:
    echo       - targets: ['localhost:9090']
    echo.
    echo   - job_name: 'n8n'
    echo     static_configs:
    echo       - targets: ['n8n:5678']
    echo     metrics_path: '/metrics'
    echo.
    echo   - job_name: 'grafana'
    echo     static_configs:
    echo       - targets: ['grafana:3000']
    echo.
    echo   - job_name: 'qdrant'
    echo     static_configs:
    echo       - targets: ['qdrant:6333']
    echo     metrics_path: '/metrics'
    ) > prometheus\prometheus.yml
    
    if "%INSTALL_OBSERVABILITY%"=="full" (
        (
        echo.
        echo   - job_name: 'loki'
        echo     static_configs:
        echo       - targets: ['loki:3100']
        echo.
        echo   - job_name: 'jaeger'
        echo     static_configs:
        echo       - targets: ['jaeger:8888']
        echo.
        echo   - job_name: 'otel-collector'
        echo     static_configs:
        echo       - targets: ['otel-collector:8888']
        ) >> prometheus\prometheus.yml
    )
)

REM ============================================================================
REM CREATE GRAFANA DATASOURCES
REM ============================================================================
if not "%INSTALL_OBSERVABILITY%"=="none" (
    (
    echo apiVersion: 1
    echo datasources:
    echo   - name: Prometheus
    echo     type: prometheus
    echo     access: proxy
    echo     url: http://prometheus:9090
    echo     isDefault: true
    ) > grafana\provisioning\datasources\datasources.yml
    
    if "%INSTALL_OBSERVABILITY%"=="full" (
        (
        echo   - name: Loki
        echo     type: loki
        echo     access: proxy
        echo     url: http://loki:3100
        echo   - name: Jaeger
        echo     type: jaeger
        echo     access: proxy
        echo     url: http://jaeger:16686
        ) >> grafana\provisioning\datasources\datasources.yml
    )
)

REM ============================================================================
REM CREATE LOKI CONFIG (Full observability only)
REM ============================================================================
if "%INSTALL_OBSERVABILITY%"=="full" (
    (
    echo auth_enabled: false
    echo.
    echo server:
    echo   http_listen_port: 3100
    echo.
    echo common:
    echo   path_prefix: /loki
    echo   storage:
    echo     filesystem:
    echo       chunks_directory: /loki/chunks
    echo       rules_directory: /loki/rules
    echo   replication_factor: 1
    echo   ring:
    echo     kvstore:
    echo       store: inmemory
    echo.
    echo schema_config:
    echo   configs:
    echo     - from: 2020-10-24
    echo       store: tsdb
    echo       object_store: filesystem
    echo       schema: v13
    echo       index:
    echo         prefix: index_
    echo         period: 24h
    echo.
    echo ruler:
    echo   storage:
    echo     type: local
    echo     local:
    echo       directory: /loki/rules
    echo   alertmanager_url: http://localhost:9093
    ) > loki\loki-config.yaml
)

REM ============================================================================
REM CREATE OTEL COLLECTOR CONFIG (Full observability only)
REM ============================================================================
if "%INSTALL_OBSERVABILITY%"=="full" (
    (
    echo receivers:
    echo   otlp:
    echo     protocols:
    echo       grpc:
    echo         endpoint: 0.0.0.0:4317
    echo       http:
    echo         endpoint: 0.0.0.0:4318
    echo.
    echo processors:
    echo   batch:
    echo     timeout: 1s
    echo     send_batch_size: 1024
    echo.
    echo exporters:
    echo   otlp/jaeger:
    echo     endpoint: jaeger:4317
    echo     tls:
    echo       insecure: true
    echo   prometheus:
    echo     endpoint: "0.0.0.0:8889"
    echo   debug:
    echo     verbosity: basic
    echo.
    echo service:
    echo   pipelines:
    echo     traces:
    echo       receivers: [otlp]
    echo       processors: [batch]
    echo       exporters: [otlp/jaeger]
    echo     metrics:
    echo       receivers: [otlp]
    echo       processors: [batch]
    echo       exporters: [prometheus]
    ) > otel-collector-config.yaml
)

REM ============================================================================
REM CREATE ALLOY CONFIG (Full observability only)
REM ============================================================================
if "%INSTALL_OBSERVABILITY%"=="full" (
    (
    echo discovery.docker "containers" {
    echo   host = "unix:///var/run/docker.sock"
    echo }
    echo.
    echo loki.source.docker "docker_logs" {
    echo   host = "unix:///var/run/docker.sock"
    echo   targets = discovery.docker.containers.targets
    echo   labels = { "job" = "docker" }
    echo   forward_to = [loki.write.local.receiver]
    echo }
    echo.
    echo loki.write "local" {
    echo   endpoint {
    echo     url = "http://loki:3100/loki/api/v1/push"
    echo   }
    echo }
    ) > alloy\config.alloy
)

REM ============================================================================
REM CREATE DOCKER-COMPOSE.YML
REM ============================================================================
echo [STEP] Creating Docker Compose configuration...

REM Base services
(
echo services:
echo   postgres:
echo     image: pgvector/pgvector:pg16
echo     container_name: %CLIENT_NAME_SAFE%-postgres
echo     ports:
echo       - "5432:5432"
echo     environment:
echo       - POSTGRES_DB=postgres
echo       - POSTGRES_USER=postgres
echo       - POSTGRES_PASSWORD=%POSTGRES_PASS%
echo     volumes:
echo       - postgres_data:/var/lib/postgresql/data
echo       - ./init-sql:/docker-entrypoint-initdb.d:ro
echo     healthcheck:
echo       test: ["CMD-SHELL", "pg_isready -U postgres"]
echo       interval: 10s
echo       timeout: 5s
echo       retries: 15
echo       start_period: 60s
echo     restart: unless-stopped
echo     networks:
echo       - rag-network
) > docker-compose.yml

REM Redis (if needed)
if "%INSTALL_REDIS%"=="true" (
    (
    echo.
    echo   redis:
    echo     image: redis:8.0-alpine
    echo     container_name: %CLIENT_NAME_SAFE%-redis
    echo     ports:
    echo       - "6379:6379"
    echo     command: redis-server --requirepass %REDIS_PASS% --appendonly yes
    echo     volumes:
    echo       - redis_data:/data
    echo     healthcheck:
    echo       test: ["CMD", "redis-cli", "-a", "%REDIS_PASS%", "ping"]
    echo       interval: 5s
    echo       timeout: 3s
    echo       retries: 5
    echo     restart: unless-stopped
    echo     networks:
    echo       - rag-network
    ) >> docker-compose.yml
)

REM N8N service
(
echo.
echo   n8n:
echo     image: n8nio/n8n:latest
echo     container_name: %CLIENT_NAME_SAFE%-n8n
echo     ports:
echo       - "5678:5678"
echo     environment:
echo       - N8N_HOST=%CLIENT_DOMAIN%
echo       - N8N_PROTOCOL=%PROTOCOL%
echo       - DB_TYPE=postgresdb
echo       - DB_POSTGRESDB_HOST=%CLIENT_NAME_SAFE%-postgres
echo       - DB_POSTGRESDB_DATABASE=n8n
echo       - DB_POSTGRESDB_USER=n8n_user
echo       - DB_POSTGRESDB_PASSWORD=%POSTGRES_N8N_PASS%
echo       - WEBHOOK_URL=%PROTOCOL%://%CLIENT_DOMAIN%:5678/
echo       - N8N_ENCRYPTION_KEY=%N8N_ENCRYPTION_KEY%
echo       - N8N_RUNNERS_ENABLED=true
) >> docker-compose.yml

REM N8N SSL config
if "%USE_SSL%"=="self-signed" (
    (
    echo       - N8N_SSL_CERT=/certs/fullchain.pem
    echo       - N8N_SSL_KEY=/certs/privkey.pem
    ) >> docker-compose.yml
)

REM N8N Queue mode config
if "%N8N_QUEUE_MODE%"=="true" (
    (
    echo       - EXECUTIONS_MODE=queue
    echo       - QUEUE_BULL_REDIS_HOST=%CLIENT_NAME_SAFE%-redis
    echo       - QUEUE_BULL_REDIS_PORT=6379
    echo       - QUEUE_BULL_REDIS_PASSWORD=%REDIS_PASS%
    echo       - QUEUE_BULL_REDIS_DB=0
    ) >> docker-compose.yml
)

REM N8N Metrics (when observability enabled)
if not "%INSTALL_OBSERVABILITY%"=="none" (
    (
    echo       - N8N_METRICS=true
    echo       - N8N_METRICS_INCLUDE_DEFAULT_METRICS=true
    echo       - N8N_METRICS_INCLUDE_CACHE_METRICS=true
    ) >> docker-compose.yml
)

REM N8N OTel (full observability)
if "%INSTALL_OBSERVABILITY%"=="full" (
    (
    echo       - OTEL_EXPORTER_OTLP_ENDPOINT=http://%CLIENT_NAME_SAFE%-otel-collector:4318
    echo       - OTEL_SERVICE_NAME=n8n
    ) >> docker-compose.yml
)

REM N8N volumes and depends
(
echo     volumes:
echo       - n8n_data:/home/node/.n8n
) >> docker-compose.yml

if "%USE_SSL%"=="self-signed" (
    echo       - ./ssl:/certs:ro >> docker-compose.yml
)

(
echo     depends_on:
echo       postgres:
echo         condition: service_healthy
) >> docker-compose.yml

if "%INSTALL_REDIS%"=="true" (
    if "%N8N_QUEUE_MODE%"=="true" (
        (
        echo       redis:
        echo         condition: service_healthy
        ) >> docker-compose.yml
    )
)

(
echo     restart: unless-stopped
echo     networks:
echo       - rag-network
) >> docker-compose.yml

REM N8N Workers (queue mode only)
if "%N8N_QUEUE_MODE%"=="true" (
    (
    echo.
    echo   n8n-worker:
    echo     image: n8nio/n8n:latest
    echo     container_name: %CLIENT_NAME_SAFE%-n8n-worker
    echo     command: worker
    echo     deploy:
    echo       replicas: %N8N_WORKERS%
    echo     environment:
    echo       - DB_TYPE=postgresdb
    echo       - DB_POSTGRESDB_HOST=%CLIENT_NAME_SAFE%-postgres
    echo       - DB_POSTGRESDB_DATABASE=n8n
    echo       - DB_POSTGRESDB_USER=n8n_user
    echo       - DB_POSTGRESDB_PASSWORD=%POSTGRES_N8N_PASS%
    echo       - N8N_ENCRYPTION_KEY=%N8N_ENCRYPTION_KEY%
    echo       - EXECUTIONS_MODE=queue
    echo       - QUEUE_BULL_REDIS_HOST=%CLIENT_NAME_SAFE%-redis
    echo       - QUEUE_BULL_REDIS_PORT=6379
    echo       - QUEUE_BULL_REDIS_PASSWORD=%REDIS_PASS%
    echo       - QUEUE_BULL_REDIS_DB=0
    echo     volumes:
    echo       - n8n_data:/home/node/.n8n
    echo     depends_on:
    echo       - n8n
    echo       - redis
    echo     restart: unless-stopped
    echo     networks:
    echo       - rag-network
    echo     profiles:
    echo       - n8n-queue
    ) >> docker-compose.yml
)

REM Chatwoot (optional)
if "%INSTALL_CHATWOOT%"=="y" (
    (
    echo.
    echo   chatwoot:
    echo     image: chatwoot/chatwoot:latest
    echo     container_name: %CLIENT_NAME_SAFE%-chatwoot
    echo     command: ["sh", "-c", "bundle exec rails db:chatwoot_prepare ^&^& bundle exec rails server -b 0.0.0.0 -p 3000"]
    echo     ports:
    echo       - "3000:3000"
    echo     environment:
    echo       - RAILS_ENV=production
    echo       - SECRET_KEY_BASE=%CHATWOOT_SECRET%
    echo       - POSTGRES_HOST=%CLIENT_NAME_SAFE%-postgres
    echo       - POSTGRES_USERNAME=chatwoot_user
    echo       - POSTGRES_PASSWORD=%POSTGRES_CHATWOOT_PASS%
    echo       - POSTGRES_DATABASE=chatwoot
    echo       - REDIS_URL=redis://:%REDIS_PASS%@%CLIENT_NAME_SAFE%-redis:6379/1
    echo       - FRONTEND_URL=%PROTOCOL%://%CLIENT_DOMAIN%:3000
    echo       - BRAND_NAME=%CLIENT_NAME%
    echo     volumes:
    echo       - chatwoot_data:/app/storage
    echo     depends_on:
    echo       postgres:
    echo         condition: service_healthy
    echo       redis:
    echo         condition: service_healthy
    echo     restart: unless-stopped
    echo     networks:
    echo       - rag-network
    ) >> docker-compose.yml
)

REM Qdrant
(
echo.
echo   qdrant:
echo     image: qdrant/qdrant:latest
echo     container_name: %CLIENT_NAME_SAFE%-qdrant
echo     ports:
echo       - "6333:6333"
echo       - "6334:6334"
echo     volumes:
echo       - qdrant_data:/qdrant/storage
echo     restart: unless-stopped
echo     networks:
echo       - rag-network
) >> docker-compose.yml

REM Observability services (lite and full)
if not "%INSTALL_OBSERVABILITY%"=="none" (
    (
    echo.
    echo   prometheus:
    echo     image: prom/prometheus:latest
    echo     container_name: %CLIENT_NAME_SAFE%-prometheus
    echo     ports:
    echo       - "9090:9090"
    echo     volumes:
    echo       - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    echo       - prometheus_data:/prometheus
    echo     command:
    echo       - '--config.file=/etc/prometheus/prometheus.yml'
    echo       - '--storage.tsdb.path=/prometheus'
    echo     restart: unless-stopped
    echo     networks:
    echo       - rag-network
    echo.
    echo   grafana:
    echo     image: grafana/grafana:latest
    echo     container_name: %CLIENT_NAME_SAFE%-grafana
    echo     ports:
    echo       - "3001:3000"
    echo     environment:
    echo       - GF_SECURITY_ADMIN_USER=admin
    echo       - GF_SECURITY_ADMIN_PASSWORD=%GRAFANA_PASS%
    echo       - GF_USERS_ALLOW_SIGN_UP=false
    echo     volumes:
    echo       - grafana_data:/var/lib/grafana
    echo       - ./grafana/provisioning:/etc/grafana/provisioning:ro
    echo     depends_on:
    echo       - prometheus
    echo     restart: unless-stopped
    echo     networks:
    echo       - rag-network
    ) >> docker-compose.yml
)

REM Full observability services
if "%INSTALL_OBSERVABILITY%"=="full" (
    (
    echo.
    echo   loki:
    echo     image: grafana/loki:3.0.0
    echo     container_name: %CLIENT_NAME_SAFE%-loki
    echo     ports:
    echo       - "3100:3100"
    echo     command: -config.file=/etc/loki/local-config.yaml
    echo     volumes:
    echo       - ./loki/loki-config.yaml:/etc/loki/local-config.yaml:ro
    echo       - loki_data:/loki
    echo     restart: unless-stopped
    echo     networks:
    echo       - rag-network
    echo.
    echo   jaeger:
    echo     image: jaegertracing/jaeger:2.1.0
    echo     container_name: %CLIENT_NAME_SAFE%-jaeger
    echo     ports:
    echo       - "16686:16686"
    echo       - "4317:4317"
    echo       - "4318:4318"
    echo     environment:
    echo       - COLLECTOR_OTLP_ENABLED=true
    echo       - SPAN_STORAGE_TYPE=badger
    echo       - BADGER_EPHEMERAL=false
    echo       - BADGER_DIRECTORY_VALUE=/badger/data
    echo       - BADGER_DIRECTORY_KEY=/badger/key
    echo     volumes:
    echo       - jaeger_data:/badger
    echo     restart: unless-stopped
    echo     networks:
    echo       - rag-network
    echo.
    echo   otel-collector:
    echo     image: otel/opentelemetry-collector-contrib:0.100.0
    echo     container_name: %CLIENT_NAME_SAFE%-otel-collector
    echo     command: ["--config=/etc/otelcol-contrib/otel-collector-config.yaml"]
    echo     ports:
    echo       - "4319:4317"
    echo       - "4320:4318"
    echo       - "8888:8888"
    echo     volumes:
    echo       - ./otel-collector-config.yaml:/etc/otelcol-contrib/otel-collector-config.yaml:ro
    echo     restart: unless-stopped
    echo     networks:
    echo       - rag-network
    echo.
    echo   alloy:
    echo     image: grafana/alloy:latest
    echo     container_name: %CLIENT_NAME_SAFE%-alloy
    echo     command: run /etc/alloy/config.alloy
    echo     volumes:
    echo       - ./alloy/config.alloy:/etc/alloy/config.alloy:ro
    echo       - //var/run/docker.sock:/var/run/docker.sock:ro
    echo     depends_on:
    echo       - loki
    echo     restart: unless-stopped
    echo     networks:
    echo       - rag-network
    ) >> docker-compose.yml
)

REM Volumes section
(
echo.
echo volumes:
echo   postgres_data:
echo     name: %CLIENT_NAME_SAFE%-postgres-data
echo   n8n_data:
echo     name: %CLIENT_NAME_SAFE%-n8n-data
echo   qdrant_data:
echo     name: %CLIENT_NAME_SAFE%-qdrant-data
) >> docker-compose.yml

if "%INSTALL_REDIS%"=="true" (
    (
    echo   redis_data:
    echo     name: %CLIENT_NAME_SAFE%-redis-data
    ) >> docker-compose.yml
)

if "%INSTALL_CHATWOOT%"=="y" (
    (
    echo   chatwoot_data:
    echo     name: %CLIENT_NAME_SAFE%-chatwoot-data
    ) >> docker-compose.yml
)

if not "%INSTALL_OBSERVABILITY%"=="none" (
    (
    echo   prometheus_data:
    echo     name: %CLIENT_NAME_SAFE%-prometheus-data
    echo   grafana_data:
    echo     name: %CLIENT_NAME_SAFE%-grafana-data
    ) >> docker-compose.yml
)

if "%INSTALL_OBSERVABILITY%"=="full" (
    (
    echo   loki_data:
    echo     name: %CLIENT_NAME_SAFE%-loki-data
    echo   jaeger_data:
    echo     name: %CLIENT_NAME_SAFE%-jaeger-data
    ) >> docker-compose.yml
)

REM Networks section
(
echo.
echo networks:
echo   rag-network:
echo     name: %CLIENT_NAME_SAFE%-rag-network
echo     driver: bridge
) >> docker-compose.yml

REM ============================================================================
REM CREATE MANAGEMENT SCRIPTS
REM ============================================================================
echo [STEP] Creating management scripts...

REM start.bat
(
echo @echo off
echo echo Starting RAG stack for %CLIENT_NAME%...
echo cd /d "%INSTALL_DIR%"
echo.
echo echo Starting databases first...
echo docker-compose up -d postgres
if "%INSTALL_REDIS%"=="true" echo docker-compose up -d redis
echo echo Waiting for databases ^(60 seconds^)...
echo timeout /t 60 /nobreak
echo.
echo echo Starting remaining services...
echo docker-compose up -d
echo.
echo echo Waiting for services to stabilize ^(30 seconds^)...
echo timeout /t 30 /nobreak
echo.
echo echo ===============================================================================
echo echo    RAG Stack is running for %CLIENT_NAME%!
echo echo ===============================================================================
echo echo.
echo echo Service URLs:
echo echo N8N:          %PROTOCOL%://%CLIENT_DOMAIN%:5678
if "%INSTALL_CHATWOOT%"=="y" echo echo Chatwoot:     http://%CLIENT_DOMAIN%:3000
if not "%INSTALL_OBSERVABILITY%"=="none" echo echo Grafana:      http://%CLIENT_DOMAIN%:3001
echo echo Qdrant:       http://%CLIENT_DOMAIN%:6333
if "%INSTALL_OBSERVABILITY%"=="full" echo echo Jaeger:       http://%CLIENT_DOMAIN%:16686
echo echo.
echo docker-compose ps
echo pause
) > start.bat

REM stop.bat
(
echo @echo off
echo echo Stopping RAG stack for %CLIENT_NAME%...
echo cd /d "%INSTALL_DIR%"
echo docker-compose down
echo echo All services stopped.
echo pause
) > stop.bat

REM status.bat
(
echo @echo off
echo cd /d "%INSTALL_DIR%"
echo echo ===============================================================================
echo echo    RAG Stack Status for %CLIENT_NAME%
echo echo ===============================================================================
echo echo.
echo echo Container Status:
echo docker-compose ps
echo echo.
echo echo Recent N8N logs:
echo docker-compose logs --tail=10 n8n
echo pause
) > status.bat

REM restart.bat
(
echo @echo off
echo echo Restarting RAG stack for %CLIENT_NAME%...
echo cd /d "%INSTALL_DIR%"
echo docker-compose restart
echo echo Services restarted.
echo pause
) > restart.bat

REM logs.bat
(
echo @echo off
echo cd /d "%INSTALL_DIR%"
echo echo.
echo echo Available services:
echo echo   1. n8n
echo echo   2. postgres
if "%INSTALL_REDIS%"=="true" echo echo   3. redis
if "%INSTALL_CHATWOOT%"=="y" echo echo   4. chatwoot
echo echo   5. qdrant
if not "%INSTALL_OBSERVABILITY%"=="none" echo echo   6. grafana
if "%INSTALL_OBSERVABILITY%"=="full" echo echo   7. jaeger
echo echo.
echo set /p SERVICE="Enter service name: "
echo docker-compose logs --tail=50 -f %%SERVICE%%
) > logs.bat

REM ============================================================================
REM CREATE ENHANCE.BAT (Full-featured version)
REM ============================================================================
echo [STEP] Creating enhancement script...

echo @echo off > enhance.bat
echo setlocal enabledelayedexpansion >> enhance.bat
echo. >> enhance.bat
echo echo =============================================================================== >> enhance.bat
echo echo    RAG Stack Enhancement Script v2.0 >> enhance.bat
echo echo =============================================================================== >> enhance.bat
echo echo. >> enhance.bat
echo. >> enhance.bat
echo cd /d "%INSTALL_DIR%" >> enhance.bat
echo. >> enhance.bat
echo if not exist ".env" ( >> enhance.bat
echo     echo [ERROR] .env file not found. Run from RAG stack directory. >> enhance.bat
echo     pause >> enhance.bat
echo     exit /b 1 >> enhance.bat
echo ) >> enhance.bat
echo. >> enhance.bat
echo echo Options: >> enhance.bat
echo echo   1. Add Redis/PostgreSQL Exporters + Dashboards >> enhance.bat
echo echo   2. Configure Windows Firewall >> enhance.bat
echo echo   3. Secure Qdrant with API Key >> enhance.bat
echo echo   4. All of the above >> enhance.bat
echo echo   5. Exit >> enhance.bat
echo echo. >> enhance.bat
echo set /p ECHOICE="Choose option (1-5) [4]: " >> enhance.bat
echo if "%%ECHOICE%%"=="" set ECHOICE=4 >> enhance.bat
echo. >> enhance.bat
echo if "%%ECHOICE%%"=="5" exit /b 0 >> enhance.bat
echo if "%%ECHOICE%%"=="1" goto exporters >> enhance.bat
echo if "%%ECHOICE%%"=="2" goto firewall >> enhance.bat
echo if "%%ECHOICE%%"=="3" goto qdrant >> enhance.bat
echo if "%%ECHOICE%%"=="4" goto all >> enhance.bat
echo goto endscript >> enhance.bat
echo. >> enhance.bat
echo :all >> enhance.bat
echo call :add_exporters >> enhance.bat
echo call :add_dashboards >> enhance.bat
echo call :configure_firewall >> enhance.bat
echo call :secure_qdrant >> enhance.bat
echo goto endscript >> enhance.bat
echo. >> enhance.bat
echo :exporters >> enhance.bat
echo call :add_exporters >> enhance.bat
echo call :add_dashboards >> enhance.bat
echo goto endscript >> enhance.bat
echo. >> enhance.bat
echo :firewall >> enhance.bat
echo call :configure_firewall >> enhance.bat
echo goto endscript >> enhance.bat
echo. >> enhance.bat
echo :qdrant >> enhance.bat
echo call :secure_qdrant >> enhance.bat
echo goto endscript >> enhance.bat
echo. >> enhance.bat
echo :add_exporters >> enhance.bat
echo echo. >> enhance.bat
echo echo [STEP] Adding monitoring exporters... >> enhance.bat
echo echo. >> enhance.bat
echo findstr /C:"redis-exporter" docker-compose.yml ^>nul 2^>^&1 >> enhance.bat
echo if not errorlevel 1 ( >> enhance.bat
echo     echo [INFO] Exporters already added >> enhance.bat
echo     exit /b 0 >> enhance.bat
echo ) >> enhance.bat
echo echo. >> enhance.bat
echo echo   # === MONITORING EXPORTERS === >> docker-compose.yml >> enhance.bat
echo echo   redis-exporter: >> docker-compose.yml >> enhance.bat
echo echo     image: oliver006/redis_exporter:latest >> docker-compose.yml >> enhance.bat
echo echo     container_name: %CLIENT_NAME_SAFE%-redis-exporter >> docker-compose.yml >> enhance.bat
echo echo     environment: >> docker-compose.yml >> enhance.bat
echo echo       - REDIS_ADDR=redis://%CLIENT_NAME_SAFE%-redis:6379 >> docker-compose.yml >> enhance.bat
echo echo       - REDIS_PASSWORD=${REDIS_PASSWORD} >> docker-compose.yml >> enhance.bat
echo echo     ports: >> docker-compose.yml >> enhance.bat
echo echo       - "9121:9121" >> docker-compose.yml >> enhance.bat
echo echo     restart: unless-stopped >> docker-compose.yml >> enhance.bat
echo echo     networks: >> docker-compose.yml >> enhance.bat
echo echo       - rag-network >> docker-compose.yml >> enhance.bat
echo echo     profiles: >> docker-compose.yml >> enhance.bat
echo echo       - monitoring >> docker-compose.yml >> enhance.bat
echo echo. >> docker-compose.yml >> enhance.bat
echo echo   postgres-exporter: >> docker-compose.yml >> enhance.bat
echo echo     image: prometheuscommunity/postgres-exporter:latest >> docker-compose.yml >> enhance.bat
echo echo     container_name: %CLIENT_NAME_SAFE%-postgres-exporter >> docker-compose.yml >> enhance.bat
echo echo     environment: >> docker-compose.yml >> enhance.bat
echo echo       - DATA_SOURCE_NAME=postgresql://postgres:${POSTGRES_PASSWORD}@%CLIENT_NAME_SAFE%-postgres:5432/postgres?sslmode=disable >> docker-compose.yml >> enhance.bat
echo echo     ports: >> docker-compose.yml >> enhance.bat
echo echo       - "9187:9187" >> docker-compose.yml >> enhance.bat
echo echo     restart: unless-stopped >> docker-compose.yml >> enhance.bat
echo echo     networks: >> docker-compose.yml >> enhance.bat
echo echo       - rag-network >> docker-compose.yml >> enhance.bat
echo echo     profiles: >> docker-compose.yml >> enhance.bat
echo echo       - monitoring >> docker-compose.yml >> enhance.bat
echo echo. >> enhance.bat
echo echo [OK] Exporters added to docker-compose.yml >> enhance.bat
echo echo. >> enhance.bat
echo echo Adding Prometheus scrape targets... >> enhance.bat
echo echo. >> prometheus\prometheus.yml >> enhance.bat
echo echo   - job_name: 'redis' >> prometheus\prometheus.yml >> enhance.bat
echo echo     static_configs: >> prometheus\prometheus.yml >> enhance.bat
echo echo       - targets: ['redis-exporter:9121'] >> prometheus\prometheus.yml >> enhance.bat
echo echo. >> prometheus\prometheus.yml >> enhance.bat
echo echo   - job_name: 'postgres' >> prometheus\prometheus.yml >> enhance.bat
echo echo     static_configs: >> prometheus\prometheus.yml >> enhance.bat
echo echo       - targets: ['postgres-exporter:9187'] >> prometheus\prometheus.yml >> enhance.bat
echo echo. >> enhance.bat
echo echo [OK] Prometheus scrape targets added >> enhance.bat
echo echo. >> enhance.bat
echo echo To start exporters: docker-compose --profile monitoring up -d >> enhance.bat
echo exit /b 0 >> enhance.bat
echo. >> enhance.bat
echo :add_dashboards >> enhance.bat
echo echo. >> enhance.bat
echo echo [STEP] Creating Grafana dashboard provisioning... >> enhance.bat
echo echo. >> enhance.bat
echo if not exist "grafana\provisioning\dashboards" mkdir grafana\provisioning\dashboards >> enhance.bat
echo ( >> enhance.bat
echo echo apiVersion: 1 >> enhance.bat
echo echo providers: >> enhance.bat
echo echo   - name: 'RAG Stack' >> enhance.bat
echo echo     orgId: 1 >> enhance.bat
echo echo     folder: 'RAG Stack' >> enhance.bat
echo echo     type: file >> enhance.bat
echo echo     options: >> enhance.bat
echo echo       path: /etc/grafana/provisioning/dashboards >> enhance.bat
echo ) ^> grafana\provisioning\dashboards\default.yaml >> enhance.bat
echo echo. >> enhance.bat
echo echo [OK] Dashboard provisioning configured >> enhance.bat
echo echo. >> enhance.bat
echo echo TIP: Download dashboards from grafana.com: >> enhance.bat
echo echo   Redis: https://grafana.com/grafana/dashboards/763 >> enhance.bat
echo echo   PostgreSQL: https://grafana.com/grafana/dashboards/9628 >> enhance.bat
echo exit /b 0 >> enhance.bat
echo. >> enhance.bat
echo :configure_firewall >> enhance.bat
echo echo. >> enhance.bat
echo echo [STEP] Configuring Windows Firewall... >> enhance.bat
echo echo. >> enhance.bat
echo echo Adding N8N firewall rule... >> enhance.bat
echo netsh advfirewall firewall add rule name="RAG-N8N" dir=in action=allow protocol=tcp localport=5678 >> enhance.bat
echo echo [OK] N8N port 5678 allowed >> enhance.bat
echo. >> enhance.bat
echo set /p ALLOW_GRAFANA="Allow Grafana (port 3001) externally? (y/N): " >> enhance.bat
echo if /i "%%ALLOW_GRAFANA%%"=="y" ( >> enhance.bat
echo     netsh advfirewall firewall add rule name="RAG-Grafana" dir=in action=allow protocol=tcp localport=3001 >> enhance.bat
echo     echo [OK] Grafana port 3001 allowed >> enhance.bat
echo ) >> enhance.bat
echo. >> enhance.bat
echo set /p ALLOW_JAEGER="Allow Jaeger (port 16686) externally? (y/N): " >> enhance.bat
echo if /i "%%ALLOW_JAEGER%%"=="y" ( >> enhance.bat
echo     netsh advfirewall firewall add rule name="RAG-Jaeger" dir=in action=allow protocol=tcp localport=16686 >> enhance.bat
echo     echo [OK] Jaeger port 16686 allowed >> enhance.bat
echo ) >> enhance.bat
echo. >> enhance.bat
echo set /p ALLOW_QDRANT="Allow Qdrant (port 6333) externally? (y/N): " >> enhance.bat
echo if /i "%%ALLOW_QDRANT%%"=="y" ( >> enhance.bat
echo     netsh advfirewall firewall add rule name="RAG-Qdrant" dir=in action=allow protocol=tcp localport=6333 >> enhance.bat
echo     echo [OK] Qdrant port 6333 allowed >> enhance.bat
echo ) >> enhance.bat
echo. >> enhance.bat
echo echo [OK] Firewall configuration complete >> enhance.bat
echo exit /b 0 >> enhance.bat
echo. >> enhance.bat
echo :secure_qdrant >> enhance.bat
echo echo. >> enhance.bat
echo echo [STEP] Securing Qdrant with API key... >> enhance.bat
echo echo. >> enhance.bat
echo set QKEY=qdrant_%%RANDOM%%%%RANDOM%%%%RANDOM%% >> enhance.bat
echo echo Generated API Key: %%QKEY%% >> enhance.bat
echo echo. >> enhance.bat
echo if not exist qdrant mkdir qdrant >> enhance.bat
echo ( >> enhance.bat
echo echo service: >> enhance.bat
echo echo   api_key: %%QKEY%% >> enhance.bat
echo echo storage: >> enhance.bat
echo echo   storage_path: /qdrant/storage >> enhance.bat
echo ) ^> qdrant\config.yaml >> enhance.bat
echo echo. >> enhance.bat
echo echo [OK] Created qdrant\config.yaml >> enhance.bat
echo echo. >> enhance.bat
echo REM Add to .env >> enhance.bat
echo findstr /C:"QDRANT_API_KEY" .env ^>nul 2^>^&1 >> enhance.bat
echo if errorlevel 1 ( >> enhance.bat
echo     echo.^>^>.env >> enhance.bat
echo     echo QDRANT_API_KEY=%%QKEY%%^>^>.env >> enhance.bat
echo     echo [OK] Added to .env >> enhance.bat
echo ) >> enhance.bat
echo echo. >> enhance.bat
echo REM Add to CREDENTIALS.txt >> enhance.bat
echo findstr /C:"QDRANT" CREDENTIALS.txt ^>nul 2^>^&1 >> enhance.bat
echo if errorlevel 1 ( >> enhance.bat
echo     echo.^>^>CREDENTIALS.txt >> enhance.bat
echo     echo === QDRANT ===^>^>CREDENTIALS.txt >> enhance.bat
echo     echo API Key: %%QKEY%%^>^>CREDENTIALS.txt >> enhance.bat
echo     echo [OK] Added to CREDENTIALS.txt >> enhance.bat
echo ) >> enhance.bat
echo echo. >> enhance.bat
echo echo IMPORTANT: Add this volume to docker-compose.yml under qdrant service: >> enhance.bat
echo echo   volumes: >> enhance.bat
echo echo     - ./qdrant/config.yaml:/qdrant/config/config.yaml:ro >> enhance.bat
echo echo. >> enhance.bat
echo echo Then restart Qdrant: docker-compose restart qdrant >> enhance.bat
echo exit /b 0 >> enhance.bat
echo. >> enhance.bat
echo :endscript >> enhance.bat
echo echo. >> enhance.bat
echo echo =============================================================================== >> enhance.bat
echo echo    Enhancement complete! >> enhance.bat
echo echo =============================================================================== >> enhance.bat
echo pause >> enhance.bat

REM ============================================================================
REM CREATE TOGGLE-N8N-QUEUE.BAT (Functional version)
REM ============================================================================
echo [STEP] Creating N8N queue toggle script...

echo @echo off > toggle-n8n-queue.bat
echo setlocal enabledelayedexpansion >> toggle-n8n-queue.bat
echo. >> toggle-n8n-queue.bat
echo echo =============================================================================== >> toggle-n8n-queue.bat
echo echo    N8N Queue Mode Toggle >> toggle-n8n-queue.bat
echo echo =============================================================================== >> toggle-n8n-queue.bat
echo echo. >> toggle-n8n-queue.bat
echo. >> toggle-n8n-queue.bat
echo cd /d "%INSTALL_DIR%" >> toggle-n8n-queue.bat
echo. >> toggle-n8n-queue.bat
echo REM Check current mode from .env >> toggle-n8n-queue.bat
echo set CURRENT_MODE=single >> toggle-n8n-queue.bat
echo for /f "tokens=2 delims==" %%%%a in ('findstr /C:"N8N_QUEUE_MODE" .env 2^>nul') do set QMODE=%%%%a >> toggle-n8n-queue.bat
echo if "%%QMODE%%"=="true" set CURRENT_MODE=queue >> toggle-n8n-queue.bat
echo. >> toggle-n8n-queue.bat
echo echo Current mode: %%CURRENT_MODE%% >> toggle-n8n-queue.bat
echo echo. >> toggle-n8n-queue.bat
echo. >> toggle-n8n-queue.bat
echo if "%%CURRENT_MODE%%"=="queue" ( >> toggle-n8n-queue.bat
echo     echo You are currently in QUEUE mode with workers. >> toggle-n8n-queue.bat
echo     echo. >> toggle-n8n-queue.bat
echo     set /p SWITCH="Switch to SINGLE INSTANCE mode? (y/N): " >> toggle-n8n-queue.bat
echo     if /i "%%SWITCH%%"=="y" ( >> toggle-n8n-queue.bat
echo         echo. >> toggle-n8n-queue.bat
echo         echo Updating configuration... >> toggle-n8n-queue.bat
echo         powershell -Command "(Get-Content .env) -replace 'N8N_QUEUE_MODE=true', 'N8N_QUEUE_MODE=false' | Set-Content .env" >> toggle-n8n-queue.bat
echo         echo. >> toggle-n8n-queue.bat
echo         echo Stopping workers... >> toggle-n8n-queue.bat
echo         docker-compose --profile n8n-queue stop n8n-worker >> toggle-n8n-queue.bat
echo         docker-compose --profile n8n-queue rm -f n8n-worker >> toggle-n8n-queue.bat
echo         echo. >> toggle-n8n-queue.bat
echo         echo Restarting N8N... >> toggle-n8n-queue.bat
echo         docker-compose restart n8n >> toggle-n8n-queue.bat
echo         echo. >> toggle-n8n-queue.bat
echo         echo [OK] Switched to Single Instance mode >> toggle-n8n-queue.bat
echo     ^) >> toggle-n8n-queue.bat
echo ) else ( >> toggle-n8n-queue.bat
echo     echo You are currently in SINGLE INSTANCE mode. >> toggle-n8n-queue.bat
echo     echo. >> toggle-n8n-queue.bat
echo     REM Check if Redis is installed >> toggle-n8n-queue.bat
echo     docker-compose ps redis 2^>nul ^| findstr "running" ^>nul >> toggle-n8n-queue.bat
echo     if errorlevel 1 ( >> toggle-n8n-queue.bat
echo         echo [ERROR] Redis is not running. Queue mode requires Redis. >> toggle-n8n-queue.bat
echo         echo Please reinstall with Redis support or start Redis first. >> toggle-n8n-queue.bat
echo         goto endtoggle >> toggle-n8n-queue.bat
echo     ^) >> toggle-n8n-queue.bat
echo     echo. >> toggle-n8n-queue.bat
echo     set /p SWITCH="Switch to QUEUE mode with workers? (y/N): " >> toggle-n8n-queue.bat
echo     if /i "%%SWITCH%%"=="y" ( >> toggle-n8n-queue.bat
echo         echo. >> toggle-n8n-queue.bat
echo         echo Updating configuration... >> toggle-n8n-queue.bat
echo         powershell -Command "(Get-Content .env) -replace 'N8N_QUEUE_MODE=false', 'N8N_QUEUE_MODE=true' | Set-Content .env" >> toggle-n8n-queue.bat
echo         echo. >> toggle-n8n-queue.bat
echo         echo Starting workers... >> toggle-n8n-queue.bat
echo         docker-compose --profile n8n-queue up -d n8n-worker >> toggle-n8n-queue.bat
echo         echo. >> toggle-n8n-queue.bat
echo         echo Restarting N8N... >> toggle-n8n-queue.bat
echo         docker-compose restart n8n >> toggle-n8n-queue.bat
echo         echo. >> toggle-n8n-queue.bat
echo         echo [OK] Switched to Queue mode with workers >> toggle-n8n-queue.bat
echo         echo. >> toggle-n8n-queue.bat
echo         echo TIP: Scale workers with: >> toggle-n8n-queue.bat
echo         echo   docker-compose --profile n8n-queue up -d --scale n8n-worker=N >> toggle-n8n-queue.bat
echo     ^) >> toggle-n8n-queue.bat
echo ) >> toggle-n8n-queue.bat
echo. >> toggle-n8n-queue.bat
echo :endtoggle >> toggle-n8n-queue.bat
echo echo. >> toggle-n8n-queue.bat
echo docker-compose ps ^| findstr n8n >> toggle-n8n-queue.bat
echo echo. >> toggle-n8n-queue.bat
echo pause >> toggle-n8n-queue.bat

REM ============================================================================
REM CREATE RENEW-SSL.BAT (Let's Encrypt only)
REM ============================================================================
if "%USE_SSL%"=="letsencrypt" (
    echo [STEP] Creating SSL renewal script...
    
    echo @echo off > renew-ssl.bat
    echo echo =============================================================================== >> renew-ssl.bat
    echo echo    SSL Certificate Renewal for %CLIENT_DOMAIN% >> renew-ssl.bat
    echo echo =============================================================================== >> renew-ssl.bat
    echo echo. >> renew-ssl.bat
    echo. >> renew-ssl.bat
    echo cd /d "%INSTALL_DIR%" >> renew-ssl.bat
    echo. >> renew-ssl.bat
    echo echo Stopping N8N to free port 443... >> renew-ssl.bat
    echo docker-compose stop n8n >> renew-ssl.bat
    echo. >> renew-ssl.bat
    echo echo Renewing certificate with Certbot... >> renew-ssl.bat
    echo docker run --rm -v "%%CD%%\letsencrypt:/etc/letsencrypt" -v "%%CD%%\ssl:/certs" -p 80:80 -p 443:443 certbot/certbot renew >> renew-ssl.bat
    echo. >> renew-ssl.bat
    echo echo Copying renewed certificates... >> renew-ssl.bat
    echo copy /Y "letsencrypt\live\%CLIENT_DOMAIN%\privkey.pem" "ssl\privkey.pem" >> renew-ssl.bat
    echo copy /Y "letsencrypt\live\%CLIENT_DOMAIN%\fullchain.pem" "ssl\fullchain.pem" >> renew-ssl.bat
    echo. >> renew-ssl.bat
    echo echo Restarting N8N... >> renew-ssl.bat
    echo docker-compose start n8n >> renew-ssl.bat
    echo. >> renew-ssl.bat
    echo echo Certificate renewal complete! >> renew-ssl.bat
    echo echo. >> renew-ssl.bat
    echo echo TIP: Add this to Windows Task Scheduler to run monthly: >> renew-ssl.bat
    echo echo      "%INSTALL_DIR%\renew-ssl.bat" >> renew-ssl.bat
    echo pause >> renew-ssl.bat
)

REM ============================================================================
REM CREATE .GITIGNORE
REM ============================================================================
echo [STEP] Creating .gitignore...

(
echo # Sensitive files
echo .env
echo CREDENTIALS.txt
echo *.log
echo.
echo # SSL certificates
echo ssl/
echo letsencrypt/
echo.
echo # Data directories
echo postgres_data/
echo redis_data/
echo n8n_data/
echo chatwoot_data/
echo qdrant_data/
echo prometheus_data/
echo grafana_data/
echo jaeger_data/
echo loki_data/
echo.
echo # Windows
echo Thumbs.db
echo Desktop.ini
echo.
echo # macOS
echo .DS_Store
) > .gitignore

REM ============================================================================
REM CREATE README.MD
REM ============================================================================
echo [STEP] Creating README.md...

(
echo # RAG Stack Installation for %CLIENT_NAME%
echo.
echo ## What's Installed
echo.
echo ### Base Services
echo - **PostgreSQL 16** with pgvector - Main database
echo - **N8N v2** - Workflow automation
echo - **Qdrant** - Vector database for RAG
) > README.md

if "%INSTALL_REDIS%"=="true" (
    echo - **Redis 8.0** - In-memory cache and queue >> README.md
)

if "%INSTALL_CHATWOOT%"=="y" (
    echo - **Chatwoot** - Customer support platform >> README.md
)

if "%INSTALL_OBSERVABILITY%"=="lite" (
    (
    echo.
    echo ### Observability ^(Lite^)
    echo - **Prometheus** - Metrics collection
    echo - **Grafana** - Dashboards and visualization
    ) >> README.md
)

if "%INSTALL_OBSERVABILITY%"=="full" (
    (
    echo.
    echo ### Observability ^(Full^)
    echo - **Prometheus** - Metrics collection
    echo - **Grafana** - Dashboards and visualization
    echo - **Jaeger** - Distributed tracing
    echo - **Loki** - Log aggregation
    echo - **OpenTelemetry Collector** - Telemetry hub
    echo - **Alloy** - Log collector
    ) >> README.md
)

(
echo.
echo ## Quick Start
echo.
echo ```batch
echo start.bat          # Start all services
echo stop.bat           # Stop all services
echo status.bat         # Check service status
echo logs.bat           # View service logs
echo restart.bat        # Restart all services
echo ```
echo.
echo ## Service URLs
echo.
echo ^| Service ^| URL ^|
echo ^|---------|-----^|
echo ^| N8N ^| %PROTOCOL%://%CLIENT_DOMAIN%:5678 ^|
echo ^| Qdrant ^| http://%CLIENT_DOMAIN%:6333 ^|
) >> README.md

if "%INSTALL_CHATWOOT%"=="y" (
    echo ^| Chatwoot ^| http://%CLIENT_DOMAIN%:3000 ^| >> README.md
)

if not "%INSTALL_OBSERVABILITY%"=="none" (
    echo ^| Grafana ^| http://%CLIENT_DOMAIN%:3001 ^| >> README.md
)

if "%INSTALL_OBSERVABILITY%"=="full" (
    (
    echo ^| Jaeger ^| http://%CLIENT_DOMAIN%:16686 ^|
    echo ^| Prometheus ^| http://%CLIENT_DOMAIN%:9090 ^|
    ) >> README.md
)

(
echo.
echo ## Important Files
echo.
echo ^| File ^| Purpose ^|
echo ^|------|---------|^|
echo ^| docker-compose.yml ^| Service definitions ^|
echo ^| .env ^| Environment variables ^(KEEP SECURE^) ^|
echo ^| CREDENTIALS.txt ^| All passwords ^(KEEP SECURE^) ^|
echo ^| welcome.html ^| Browser quick-start guide ^|
echo ^| start.bat ^| Start services with staged DB wait ^|
echo ^| stop.bat ^| Stop all services ^|
echo ^| status.bat ^| Check container status ^|
echo ^| logs.bat ^| Interactive log viewer ^|
echo ^| enhance.bat ^| Add firewall rules and Qdrant security ^|
echo ^| toggle-n8n-queue.bat ^| Switch N8N execution modes ^|
echo.
echo ## Configuration
echo.
echo - **N8N Queue Mode:** %N8N_QUEUE_MODE%
) >> README.md

if "%N8N_QUEUE_MODE%"=="true" (
    echo - **N8N Workers:** %N8N_WORKERS% >> README.md
)

(
echo - **Observability:** %INSTALL_OBSERVABILITY%
echo - **SSL:** %USE_SSL%
echo.
echo ## Connecting N8N to Qdrant
echo.
echo In N8N, add Qdrant credentials:
echo - **URL:** http://%CLIENT_NAME_SAFE%-qdrant:6333
echo - **API Key:** ^(optional, run enhance.bat to generate^)
echo.
echo ## Connecting N8N to LM Studio
echo.
echo If running LM Studio on the host machine:
echo ```
echo URL: http://host.docker.internal:1234/v1/chat/completions
echo ```
echo.
echo ## Troubleshooting
echo.
echo ### Service won't start
echo ```batch
echo status.bat              # Check container status
echo logs.bat                # View logs for specific service
echo docker-compose logs n8n # Direct log access
echo ```
echo.
echo ### Database connection issues
echo ```batch
echo docker exec %CLIENT_NAME_SAFE%-postgres pg_isready -U postgres
echo ```
) >> README.md

if "%INSTALL_REDIS%"=="true" (
    (
    echo.
    echo ### Redis connection issues
    echo ```batch
    echo docker exec %CLIENT_NAME_SAFE%-redis redis-cli -a %%REDIS_PASSWORD%% ping
    echo ```
    ) >> README.md
)

(
echo.
echo ### Clean restart
echo ```batch
echo stop.bat
echo docker-compose down
echo start.bat
echo ```
echo.
echo ## Security Recommendations
echo.
echo 1. Run `enhance.bat` to configure Windows Firewall
echo 2. Generate Qdrant API key via `enhance.bat`
echo 3. Keep `.env` and `CREDENTIALS.txt` secure
echo 4. Change Grafana admin password on first login
echo.
echo ## Resource Requirements
echo.
echo - **Minimum RAM:** 8GB
echo - **Recommended RAM:** 16GB
echo - **Disk Space:** 20GB+
echo.
echo ---
echo.
echo **Generated:** %date% %time%
echo **Location:** %INSTALL_DIR%
) >> README.md

REM ============================================================================
REM CREATE WELCOME.HTML
REM ============================================================================
echo [STEP] Creating welcome page...

(
echo ^<!DOCTYPE html^>
echo ^<html lang="en"^>
echo ^<head^>
echo     ^<meta charset="UTF-8"^>
echo     ^<meta name="viewport" content="width=device-width, initial-scale=1.0"^>
echo     ^<title^>RAG Stack - %CLIENT_NAME%^</title^>
echo     ^<style^>
echo         * { margin: 0; padding: 0; box-sizing: border-box; }
echo         body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: linear-gradient^(135deg, #1a1a2e 0%%, #16213e 50%%, #0f3460 100%%^); min-height: 100vh; color: #e0e0e0; padding: 40px 20px; }
echo         .container { max-width: 900px; margin: 0 auto; }
echo         h1 { font-size: 2.5rem; margin-bottom: 10px; background: linear-gradient^(90deg, #00d9ff, #00ff88^); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
echo         .subtitle { color: #888; margin-bottom: 30px; font-size: 1.1rem; }
echo         .card { background: rgba^(255,255,255,0.05^); border-radius: 16px; padding: 24px; margin-bottom: 20px; border: 1px solid rgba^(255,255,255,0.1^); }
echo         .card h2 { font-size: 1.3rem; margin-bottom: 16px; color: #00d9ff; }
echo         .service-grid { display: grid; grid-template-columns: repeat^(auto-fit, minmax^(250px, 1fr^)^); gap: 12px; }
echo         .service { background: rgba^(0,0,0,0.2^); border-radius: 10px; padding: 16px; display: flex; align-items: center; gap: 12px; }
echo         .service:hover { background: rgba^(0,217,255,0.1^); }
echo         .service-icon { width: 40px; height: 40px; border-radius: 8px; display: flex; align-items: center; justify-content: center; font-size: 1.2rem; }
echo         .service-info { flex: 1; }
echo         .service-name { font-weight: 600; color: #fff; }
echo         .service-url { font-size: 0.85rem; color: #888; }
echo         .service-link { color: #00d9ff; text-decoration: none; font-size: 0.9rem; padding: 6px 12px; border: 1px solid #00d9ff; border-radius: 6px; }
echo         .service-link:hover { background: #00d9ff; color: #1a1a2e; }
echo         .note { background: rgba^(255,200,0,0.1^); border-left: 3px solid #ffc800; padding: 12px 16px; border-radius: 0 8px 8px 0; margin-top: 16px; font-size: 0.9rem; }
echo         .checklist { list-style: none; }
echo         .checklist li { padding: 12px 0; border-bottom: 1px solid rgba^(255,255,255,0.1^); }
echo     ^</style^>
echo ^</head^>
echo ^<body^>
echo     ^<div class="container"^>
echo         ^<h1^>RAG Stack Ready!^</h1^>
echo         ^<p class="subtitle"^>Installation complete for %CLIENT_NAME%^</p^>
echo.
echo         ^<div class="card"^>
echo             ^<h2^>Your Services^</h2^>
echo             ^<div class="service-grid"^>
echo                 ^<div class="service"^>
echo                     ^<div class="service-icon" style="background: linear-gradient^(135deg, #ff6b6b, #ee5a5a^);"^>N8N^</div^>
echo                     ^<div class="service-info"^>
echo                         ^<div class="service-name"^>N8N Automation^</div^>
echo                         ^<div class="service-url"^>%PROTOCOL%://localhost:5678^</div^>
echo                     ^</div^>
echo                     ^<a href="%PROTOCOL%://localhost:5678" target="_blank" class="service-link"^>Open^</a^>
echo                 ^</div^>
echo                 ^<div class="service"^>
echo                     ^<div class="service-icon" style="background: linear-gradient^(135deg, #4ecdc4, #45b7aa^);"^>Q^</div^>
echo                     ^<div class="service-info"^>
echo                         ^<div class="service-name"^>Qdrant Vector DB^</div^>
echo                         ^<div class="service-url"^>http://localhost:6333^</div^>
echo                     ^</div^>
echo                     ^<a href="http://localhost:6333/dashboard" target="_blank" class="service-link"^>Open^</a^>
echo                 ^</div^>
) > welcome.html

if "%INSTALL_CHATWOOT%"=="y" (
    (
    echo                 ^<div class="service"^>
    echo                     ^<div class="service-icon" style="background: linear-gradient^(135deg, #667eea, #5a67d8^);"^>CW^</div^>
    echo                     ^<div class="service-info"^>
    echo                         ^<div class="service-name"^>Chatwoot^</div^>
    echo                         ^<div class="service-url"^>http://localhost:3000^</div^>
    echo                     ^</div^>
    echo                     ^<a href="http://localhost:3000" target="_blank" class="service-link"^>Open^</a^>
    echo                 ^</div^>
    ) >> welcome.html
)

if not "%INSTALL_OBSERVABILITY%"=="none" (
    (
    echo                 ^<div class="service"^>
    echo                     ^<div class="service-icon" style="background: linear-gradient^(135deg, #f093fb, #f5576c^);"^>G^</div^>
    echo                     ^<div class="service-info"^>
    echo                         ^<div class="service-name"^>Grafana^</div^>
    echo                         ^<div class="service-url"^>http://localhost:3001^</div^>
    echo                     ^</div^>
    echo                     ^<a href="http://localhost:3001" target="_blank" class="service-link"^>Open^</a^>
    echo                 ^</div^>
    ) >> welcome.html
)

if "%INSTALL_OBSERVABILITY%"=="full" (
    (
    echo                 ^<div class="service"^>
    echo                     ^<div class="service-icon" style="background: linear-gradient^(135deg, #43cea2, #185a9d^);"^>J^</div^>
    echo                     ^<div class="service-info"^>
    echo                         ^<div class="service-name"^>Jaeger Tracing^</div^>
    echo                         ^<div class="service-url"^>http://localhost:16686^</div^>
    echo                     ^</div^>
    echo                     ^<a href="http://localhost:16686" target="_blank" class="service-link"^>Open^</a^>
    echo                 ^</div^>
    ) >> welcome.html
)

(
echo             ^</div^>
echo         ^</div^>
echo.
echo         ^<div class="card"^>
echo             ^<h2^>Post-Install Checklist^</h2^>
echo             ^<ul class="checklist"^>
echo                 ^<li^>Open N8N and create your first admin user^</li^>
) >> welcome.html

if not "%INSTALL_OBSERVABILITY%"=="none" (
    echo                 ^<li^>Login to Grafana ^(admin / see CREDENTIALS.txt^) and change password^</li^> >> welcome.html
)

if "%INSTALL_CHATWOOT%"=="y" (
    echo                 ^<li^>Setup Chatwoot and create your admin account^</li^> >> welcome.html
)

(
echo                 ^<li^>Add Qdrant to N8N: URL = http://%CLIENT_NAME_SAFE%-qdrant:6333^</li^>
echo                 ^<li^>^(Optional^) Run enhance.bat for firewall and security^</li^>
echo             ^</ul^>
echo         ^</div^>
echo.
echo         ^<div class="card"^>
echo             ^<h2^>Important Files^</h2^>
echo             ^<div class="note"^>
echo                 ^<strong^>CREDENTIALS.txt^</strong^> - Contains all passwords. Keep secure!^<br^>
echo                 ^<strong^>Management:^</strong^> start.bat, stop.bat, status.bat, logs.bat, enhance.bat
echo             ^</div^>
echo         ^</div^>
echo     ^</div^>
echo ^</body^>
echo ^</html^>
) >> welcome.html

REM ============================================================================
REM CREATE CREDENTIALS.TXT
REM ============================================================================
(
echo RAG Stack Installation for %CLIENT_NAME%
echo Generated: %date% %time%
echo Version: 5.0 ^(Windows^)
echo.
echo === SERVICE URLS ===
echo N8N:          %PROTOCOL%://%CLIENT_DOMAIN%:5678
if "%INSTALL_CHATWOOT%"=="y" echo Chatwoot:     http://%CLIENT_DOMAIN%:3000
if not "%INSTALL_OBSERVABILITY%"=="none" echo Grafana:      http://%CLIENT_DOMAIN%:3001
echo Qdrant:       http://%CLIENT_DOMAIN%:6333
if "%INSTALL_OBSERVABILITY%"=="full" (
echo Jaeger:       http://%CLIENT_DOMAIN%:16686
echo Prometheus:   http://%CLIENT_DOMAIN%:9090
)
echo.
echo === CREDENTIALS ===
if not "%INSTALL_OBSERVABILITY%"=="none" echo Grafana:      admin / %GRAFANA_PASS%
echo PostgreSQL:   postgres / %POSTGRES_PASS%
echo N8N DB:       n8n_user / %POSTGRES_N8N_PASS%
if "%INSTALL_CHATWOOT%"=="y" echo Chatwoot DB:  chatwoot_user / %POSTGRES_CHATWOOT_PASS%
if "%INSTALL_REDIS%"=="true" echo Redis:        %REDIS_PASS%
echo.
echo === CONFIGURATION ===
echo N8N Queue Mode: %N8N_QUEUE_MODE%
if "%N8N_QUEUE_MODE%"=="true" echo N8N Workers: %N8N_WORKERS%
echo Observability: %INSTALL_OBSERVABILITY%
echo SSL: %USE_SSL%
echo.
echo === MANAGEMENT ===
echo Start:        start.bat
echo Stop:         stop.bat
echo Status:       status.bat
echo Logs:         logs.bat
echo Restart:      restart.bat
echo Enhance:      enhance.bat
echo Toggle Queue: toggle-n8n-queue.bat
echo Location:     %INSTALL_DIR%
echo.
echo KEEP THIS FILE SECURE!
) > CREDENTIALS.txt

if "%USE_SSL%"=="letsencrypt" (
    echo Renew SSL:    renew-ssl.bat >> CREDENTIALS.txt
)

REM ============================================================================
REM START SERVICES
REM ============================================================================
echo.
echo [STEP] Starting services...
echo.

echo Starting PostgreSQL...
docker-compose up -d postgres

if "%INSTALL_REDIS%"=="true" (
    echo Starting Redis...
    docker-compose up -d redis
)

echo Waiting for databases (60 seconds)...
timeout /t 60 /nobreak

echo Checking PostgreSQL...
docker exec %CLIENT_NAME_SAFE%-postgres pg_isready -U postgres
if errorlevel 1 (
    echo Waiting additional 30 seconds...
    timeout /t 30 /nobreak
)

echo Starting remaining services...
docker-compose up -d

echo Waiting for services to stabilize (60 seconds)...
timeout /t 60 /nobreak

echo.
echo [INFO] Service status:
docker-compose ps

REM ============================================================================
REM INSTALLATION COMPLETE
REM ============================================================================
echo.
echo ===============================================================================
echo    RAG Stack Installation Complete for %CLIENT_NAME%!
echo ===============================================================================
echo.
echo SERVICE URLS:
echo   N8N:          %PROTOCOL%://%CLIENT_DOMAIN%:5678
if "%INSTALL_CHATWOOT%"=="y" echo   Chatwoot:     http://%CLIENT_DOMAIN%:3000
if not "%INSTALL_OBSERVABILITY%"=="none" echo   Grafana:      http://%CLIENT_DOMAIN%:3001 (admin/%GRAFANA_PASS%)
echo   Qdrant:       http://%CLIENT_DOMAIN%:6333
if "%INSTALL_OBSERVABILITY%"=="full" (
echo   Jaeger:       http://%CLIENT_DOMAIN%:16686
echo   Prometheus:   http://%CLIENT_DOMAIN%:9090
)
echo.
echo CONFIGURATION:
echo   N8N Mode:     %N8N_QUEUE_MODE% queue mode
if "%N8N_QUEUE_MODE%"=="true" echo   Workers:      %N8N_WORKERS%
echo   Observability: %INSTALL_OBSERVABILITY%
echo   SSL:          %USE_SSL%
echo.
echo FILES:
echo   CREDENTIALS.txt       - All passwords (KEEP SECURE!)
echo   README.md             - Documentation
echo   welcome.html          - Open in browser for quick links
echo   .gitignore            - Protects sensitive files from git
echo   enhance.bat           - Add firewall rules and security
echo   toggle-n8n-queue.bat  - Switch N8N execution modes
if "%USE_SSL%"=="letsencrypt" echo   renew-ssl.bat         - Renew Let's Encrypt certificate
echo.
echo Location: %INSTALL_DIR%
echo.
echo ===============================================================================

set /p OPEN_WELCOME="Open welcome page in browser? (Y/n): "
if /i not "%OPEN_WELCOME%"=="n" (
    start "" "%INSTALL_DIR%\welcome.html"
)

set /p OPEN_N8N="Open N8N now? (Y/n): "
if /i not "%OPEN_N8N%"=="n" (
    start "" "%PROTOCOL%://%CLIENT_DOMAIN%:5678"
)

echo.
echo Installation complete! Check status.bat if any issues.
echo Log file: %logfile%
pause
