#!/bin/bash
set -e

# BBSMC 一键部署脚本
# 适用于 Linux 服务器 (Ubuntu/Debian/CentOS)
# 部署方式: Docker Compose + Nginx 反向代理

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/docker-data"
DOMAIN="bbsmc.org.cn"
API_DOMAIN="api.bbsmc.org.cn"
CDN_DOMAIN="cdn.bbsmc.org.cn"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  BBSMC 一键部署脚本${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then 
    echo -e "${YELLOW}请使用 root 用户或 sudo 运行此脚本${NC}"
    sudo -v || { echo -e "${RED}获取 root 权限失败${NC}"; exit 1; }
fi

# ==================== 步骤 1: 检查系统环境 ====================
echo -e "${GREEN}[1/8] 检查系统环境...${NC}"

# 检测系统发行版
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
else
    echo -e "${RED}无法检测操作系统版本${NC}"
    exit 1
fi

echo -e "操作系统: $OS $OS_VERSION"

# 检查 Docker
if command -v docker &> /dev/null; then
    echo -e "${GREEN}✓ Docker 已安装: $(docker --version)${NC}"
else
    echo -e "${YELLOW}Docker 未安装，正在安装...${NC}"
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        apt-get update -qq
        apt-get install -y -qq ca-certificates curl gnupg
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS $(. /etc/os-release && echo $VERSION_CODENAME) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update -qq
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ]; then
        yum install -y -q yum-utils
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y -q docker-ce docker-ce-cli containerd.io docker-compose-plugin
        systemctl start docker
        systemctl enable docker
    else
        echo -e "${RED}不支持的操作系统: $OS${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Docker 安装完成${NC}"
fi

# 检查 Docker Compose
if docker compose version &> /dev/null; then
    echo -e "${GREEN}✓ Docker Compose 已安装${NC}"
elif command -v docker-compose &> /dev/null; then
    echo -e "${GREEN}✓ Docker Compose 已安装${NC}"
else
    echo -e "${RED}Docker Compose 未安装，请先安装 Docker Compose${NC}"
    exit 1
fi

# ==================== 步骤 2: 停止可能冲突的服务 ====================
echo -e "${GREEN}[2/8] 检查并停止端口冲突的服务...${NC}"

stop_service() {
    local service=$1
    if systemctl is-active --quiet $service 2>/dev/null; then
        echo -e "${YELLOW}停止 $service 服务...${NC}"
        systemctl stop $service 2>/dev/null || true
        systemctl disable $service 2>/dev/null || true
    fi
}

# 停止可能占用端口的系统服务
stop_service redis
stop_service meilisearch
stop_service clickhouse-server
stop_service postgresql
stop_service nginx

# 检查端口占用
check_port() {
    local port=$1
    if command -v lsof &> /dev/null; then
        local pid=$(lsof -t -i:$port -sTCP:LISTEN 2>/dev/null | head -1)
        if [ -n "$pid" ]; then
            echo -e "${YELLOW}端口 $port 被进程 $pid 占用，正在终止...${NC}"
            kill -9 $pid 2>/dev/null || true
        fi
    elif command -v ss &> /dev/null; then
        local pid=$(ss -tlnp | grep ":$port " | grep -oP 'pid=\K[0-9]+' | head -1)
        if [ -n "$pid" ]; then
            echo -e "${YELLOW}端口 $port 被进程 $pid 占用，正在终止...${NC}"
            kill -9 $pid 2>/dev/null || true
        fi
    fi
}

check_port 5432  # PostgreSQL
check_port 6379  # Redis
check_port 7700  # Meilisearch
check_port 8123  # ClickHouse
check_port 80    # Nginx
check_port 443   # Nginx HTTPS

# ==================== 步骤 3: 清理旧容器 ====================
echo -e "${GREEN}[3/8] 清理旧的 Docker 容器...${NC}"

cd "$SCRIPT_DIR"
if [ -f docker-compose.yml ]; then
    docker compose down --remove-orphans 2>/dev/null || true
fi

# 清理旧容器
docker rm -f bbsmc-labrinth bbsmc-frontend bbsmc-postgres bbsmc-redis bbsmc-meilisearch bbsmc-clickhouse bbsmc-nginx 2>/dev/null || true

# ==================== 步骤 4: 创建数据目录 ====================
echo -e "${GREEN}[4/8] 创建数据目录...${NC}"

mkdir -p "$DATA_DIR/postgres"
mkdir -p "$DATA_DIR/redis"
mkdir -p "$DATA_DIR/meilisearch"
mkdir -p "$DATA_DIR/clickhouse"
mkdir -p "$DATA_DIR/nginx/conf.d"
mkdir -p "$DATA_DIR/nginx/cert"
mkdir -p "$DATA_DIR/uploads"

# ==================== 步骤 5: 生成环境变量配置 ====================
echo -e "${GREEN}[5/8] 生成环境变量配置...${NC}"

# 生成随机密钥
generate_secret() {
    openssl rand -hex 16 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(16))" 2>/dev/null || echo "$(date +%s)$RANDOM"
}

ADMIN_KEY=$(generate_secret)
RATE_LIMIT_KEY=$(generate_secret)
POSTGRES_PASSWORD=$(generate_secret)
MEILI_KEY=$(generate_secret)

# 创建后端 .env
cat > "$SCRIPT_DIR/apps/labrinth/.env" << EOF
DEBUG=false
RUST_LOG=info,sqlx::query=warn
SENTRY_DSN=none

SITE_URL=https://$DOMAIN
CDN_URL=https://$CDN_DOMAIN/bbsmc
CDN_PRIVATE_URL=none
SELF_ADDR=https://$API_DOMAIN
LABRINTH_ADMIN_KEY=$ADMIN_KEY
RATE_LIMIT_IGNORE_KEY=$RATE_LIMIT_KEY

DATABASE_URL=postgresql://labrinth:$POSTGRES_PASSWORD@postgres:5432/labrinth
DATABASE_MIN_CONNECTIONS=0
DATABASE_MAX_CONNECTIONS=16

MEILISEARCH_ADDR=http://meilisearch:7700
MEILISEARCH_KEY=$MEILI_KEY

REDIS_URL=redis://redis:6379
REDIS_MAX_CONNECTIONS=10000
REDIS_NAMESPACE=none
REDIS_WAIT_TIMEOUT_MS=none

BIND_ADDR=0.0.0.0:8000

MODERATION_SLACK_WEBHOOK=
PUBLIC_DISCORD_WEBHOOK=
CLOUDFLARE_INTEGRATION=false

STORAGE_BACKEND=local
MOCK_FILE_PATH=/data/uploads

BACKBLAZE_KEY_ID=none
BACKBLAZE_KEY=none
BACKBLAZE_BUCKET_ID=none

S3_ACCESS_TOKEN=none
S3_SECRET=none
S3_URL=none
S3_REGION=none
S3_BUCKET_NAME=none
S3_PRIVATE_BUCKET_NAME=none

LOCAL_INDEX_INTERVAL=3600
VERSION_INDEX_INTERVAL=1800

RATE_LIMIT_IGNORE_IPS='["127.0.0.1", "172."]'

WHITELISTED_MODPACK_DOMAINS='["$CDN_DOMAIN", "github.com", "raw.githubusercontent.com"]'

ALLOWED_CALLBACK_URLS='["localhost", ".$DOMAIN", "127.0.0.1"]'

GITHUB_CLIENT_ID=none
GITHUB_CLIENT_SECRET=none

GITLAB_CLIENT_ID=none
GITLAB_CLIENT_SECRET=none

DISCORD_CLIENT_ID=none
DISCORD_CLIENT_SECRET=none

MICROSOFT_CLIENT_ID=none
MICROSOFT_CLIENT_SECRET=none

GOOGLE_CLIENT_ID=none
GOOGLE_CLIENT_SECRET=none

PAYPAL_API_URL=https://api-m.sandbox.paypal.com/v1/
PAYPAL_WEBHOOK_ID=none
PAYPAL_CLIENT_ID=none
PAYPAL_CLIENT_SECRET=none

STEAM_API_KEY=none

TREMENDOUS_API_URL=https://testflight.tremendous.com/api/v2/
TREMENDOUS_API_KEY=none
TREMENDOUS_PRIVATE_KEY=none
TREMENDOUS_CAMPAIGN_ID=none

HCAPTCHA_SECRET=none
TAC_URL=none
SMTP_USERNAME=none
SMTP_PASSWORD=none
SMTP_HOST=none

SITE_VERIFY_EMAIL_PATH=none
SITE_RESET_PASSWORD_PATH=none
SITE_BILLING_PATH=none

BEEHIIV_PUBLICATION_ID=none
BEEHIIV_API_KEY=none

ANALYTICS_ALLOWED_ORIGINS='["http://127.0.0.1:3000", "http://localhost:3000", "https://$DOMAIN", "https://www.$DOMAIN", "*"]'

CLICKHOUSE_URL=http://clickhouse:8123
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=default
CLICKHOUSE_DATABASE=bbsmc

MAXMIND_LICENSE_KEY=none

FLAME_ANVIL_URL=none

STRIPE_API_KEY=none
STRIPE_WEBHOOK_SECRET=none

ADITUDE_API_KEY=none

PYRO_API_KEY=none

DEV=false

FEISHU_BOT_WEBHOOK=none

ALIYUN_SMS_ACCESS_KEYID=none
ALIYUN_SMS_ACCESS_KEY_SECRET=none
ALIYUN_SMS_REGION=none
ALIYUN_SMS_REPORT_TEMPLETE_CODE=none
ALIYUN_SMS_SIGN_NAME=none

HUOSHAN_AK=none
HUOSHAN_SK=none

ENCRYPTION_KEY=none

SEVENPAY_API_URL=none
SEVENPAY_CREATE_ORDER_PATH=none
SEVENPAY_QUERY_ORDER_PATH=none
SEVENPAY_VERIFY_MERCHANT_PATH=none
SEVENPAY_KEYCODE=none
SEVENPAY_ALLOWED_IPS=none
EOF

# 创建前端 .env
cat > "$SCRIPT_DIR/apps/frontend/.env" << EOF
BASE_URL=https://$API_DOMAIN/v2/
BROWSER_BASE_URL=https://$API_DOMAIN/v2/
EOF

# ==================== 步骤 6: 生成 docker-compose.yml ====================
echo -e "${GREEN}[6/8] 生成 docker-compose.yml...${NC}"

cat > "$SCRIPT_DIR/docker-compose.yml" << 'EOF'
services:
  postgres:
    image: postgres:16-alpine
    container_name: bbsmc-postgres
    restart: unless-stopped
    volumes:
      - ./docker-data/postgres:/var/lib/postgresql/data
    environment:
      POSTGRES_USER: labrinth
      POSTGRES_PASSWORD: labrinth
      POSTGRES_DB: labrinth
      POSTGRES_HOST_AUTH_METHOD: trust
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U labrinth']
      interval: 5s
      timeout: 5s
      retries: 10
    networks:
      - bbsmc

  redis:
    image: redis:7-alpine
    container_name: bbsmc-redis
    restart: unless-stopped
    volumes:
      - ./docker-data/redis:/data
    healthcheck:
      test: ['CMD', 'redis-cli', 'PING']
      interval: 5s
      timeout: 5s
      retries: 10
    networks:
      - bbsmc

  meilisearch:
    image: getmeili/meilisearch:v1.12.0
    container_name: bbsmc-meilisearch
    restart: unless-stopped
    volumes:
      - ./docker-data/meilisearch:/meili_data
    environment:
      MEILI_MASTER_KEY: modrinth
      MEILI_HTTP_PAYLOAD_SIZE_LIMIT: 107374182400
      MEILI_LOG_LEVEL: warn
    healthcheck:
      test: ['CMD', 'curl', '--fail', 'http://localhost:7700/health']
      interval: 5s
      timeout: 5s
      retries: 10
    networks:
      - bbsmc

  clickhouse:
    image: clickhouse/clickhouse-server:24-alpine
    container_name: bbsmc-clickhouse
    restart: unless-stopped
    volumes:
      - ./docker-data/clickhouse:/var/lib/clickhouse
    environment:
      CLICKHOUSE_USER: default
      CLICKHOUSE_PASSWORD: default
    healthcheck:
      test: ['CMD', 'clickhouse-client', '--query', 'SELECT 1']
      interval: 5s
      timeout: 5s
      retries: 10
    networks:
      - bbsmc

  labrinth:
    build:
      context: .
      dockerfile: apps/labrinth/Dockerfile
    container_name: bbsmc-labrinth
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      meilisearch:
        condition: service_healthy
      clickhouse:
        condition: service_healthy
    env_file:
      - ./apps/labrinth/.env
    volumes:
      - ./docker-data/uploads:/data/uploads
    healthcheck:
      test: ['CMD', 'curl', '--fail', 'http://localhost:8000/']
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
    networks:
      - bbsmc

  frontend:
    image: node:20-alpine
    container_name: bbsmc-frontend
    restart: unless-stopped
    working_dir: /app
    depends_on:
      - labrinth
    command: sh -c "npm install -g pnpm && pnpm install --no-frozen-lockfile && pnpm web:build && pnpm --filter frontend preview --host 0.0.0.0 --port 3000"
    volumes:
      - ./apps/frontend:/app/apps/frontend:ro
      - ./packages:/app/packages:ro
      - ./package.json:/app/package.json:ro
      - ./pnpm-workspace.yaml:/app/pnpm-workspace.yaml:ro
    environment:
      - NODE_ENV=production
    env_file:
      - ./apps/frontend/.env
    healthcheck:
      test: ['CMD', 'curl', '--fail', 'http://localhost:3000/']
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 120s
    networks:
      - bbsmc

  nginx:
    image: nginx:alpine
    container_name: bbsmc-nginx
    restart: unless-stopped
    depends_on:
      - labrinth
      - frontend
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./docker-data/nginx/conf.d:/etc/nginx/conf.d:ro
      - ./docker-data/nginx/cert:/etc/nginx/cert:ro
      - ./docker-data/uploads:/var/www/uploads:ro
    healthcheck:
      test: ['CMD', 'nginx', '-t']
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - bbsmc

networks:
  bbsmc:
    driver: bridge
EOF

# ==================== 步骤 7: 生成 Nginx 配置 ====================
echo -e "${GREEN}[7/8] 生成 Nginx 配置...${NC}"

cat > "$DATA_DIR/nginx/conf.d/bbsmc.conf" << EOF
# 前端站点
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;

    location / {
        proxy_pass http://frontend:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# API 站点
server {
    listen 80;
    server_name $API_DOMAIN;

    client_max_body_size 1000M;

    location / {
        proxy_pass http://labrinth:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
    }
}

# CDN 站点
server {
    listen 80;
    server_name $CDN_DOMAIN;

    root /var/www/uploads;

    location / {
        expires 30d;
        add_header Cache-Control "public, immutable";
        try_files \$uri \$uri/ =404;
    }
}
EOF

# ==================== 步骤 8: 启动服务 ====================
echo -e "${GREEN}[8/8] 启动 Docker 服务...${NC}"

cd "$SCRIPT_DIR"

echo -e "${YELLOW}正在构建和启动服务，这可能需要几分钟...${NC}"
docker compose up -d --build

# 等待服务启动
echo ""
echo -e "${YELLOW}等待服务启动...${NC}"
sleep 30

# 检查服务状态
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  部署完成!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "服务地址:"
echo -e "  网站:   http://$DOMAIN"
echo -e "  API:    http://$API_DOMAIN"
echo -e "  CDN:    http://$CDN_DOMAIN"
echo ""
echo -e "管理密钥:"
echo -e "  管理员密钥: $ADMIN_KEY"
echo -e "  PostgreSQL 密码: $POSTGRES_PASSWORD"
echo -e "  Meilisearch 密钥: $MEILI_KEY"
echo ""
echo -e "常用命令:"
echo -e "  查看服务状态: docker compose ps"
echo -e "  查看日志:     docker compose logs -f"
echo -e "  停止服务:     docker compose down"
echo -e "  重启服务:     docker compose restart"
echo ""
echo -e "${YELLOW}提示: 请将域名 DNS 解析到本服务器 IP，并配置 SSL 证书${NC}"
echo -e "${YELLOW}配置文件保存在: $DATA_DIR/nginx/conf.d/${NC}"
echo ""
