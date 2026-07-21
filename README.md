# BBSMC

> 网站地址: https://bbsmc.org.cn

BBSMC 是一个基于 Modrinth 开源项目二次开发的 Minecraft 模组/资源分享平台，提供模组、整合包、资源包、光影包等资源的托管与分发。

## 目录

- [项目结构](#项目结构)
- [技术栈](#技术栈)
- [环境要求](#环境要求)
- [快速开始（一键部署）](#快速开始一键部署)
- [手动部署（Docker Compose）](#手动部署docker-compose)
- [本地开发](#本地开发)
- [环境变量说明](#环境变量说明)
- [Nginx 反向代理配置](#nginx-反向代理配置)
- [常见问题](#常见问题)
- [许可证](#许可证)

## 项目结构

```
app-main/
├── apps/
│   ├── frontend/          # 前端 (Nuxt 3 / Vue 3 / TypeScript)
│   │   ├── src/
│   │   │   ├── components/   # Vue 组件
│   │   │   ├── pages/        # 页面路由
│   │   │   ├── layouts/      # 布局
│   │   │   ├── composables/  # 组合式函数
│   │   │   └── plugins/      # Nuxt 插件
│   │   ├── .env               # 前端环境变量
│   │   └── nuxt.config.ts     # Nuxt 配置
│   ├── labrinth/          # 后端 API (Rust / actix-web)
│   │   ├── src/
│   │   │   ├── routes/        # API 路由 (v2 / v3)
│   │   │   ├── models/        # 数据模型
│   │   │   ├── database/      # 数据库交互
│   │   │   └── auth/          # 认证模块
│   │   ├── migrations/        # SQL 数据库迁移
│   │   ├── .env                # 后端环境变量
│   │   └── Dockerfile          # 后端 Docker 构建
│   └── docs/              # 文档站点 (Astro)
├── packages/
│   ├── api-client/        # API 客户端 (TypeScript)
│   ├── app-lib/           # 应用库 (Rust)
│   ├── daedalus/          # Daedalus 库 (Rust)
│   └── utils/             # 工具库 (TypeScript)
├── deploy.sh              # 一键部署脚本
├── docker-compose.yml     # Docker Compose 配置
├── Cargo.toml             # Rust workspace 配置
└── package.json           # Node.js monorepo 配置
```

## 技术栈

| 分类       | 技术                                                 |
| ---------- | ---------------------------------------------------- |
| **前端**   | Nuxt 3, Vue 3, TypeScript, Tailwind CSS, pnpm        |
| **后端**   | Rust, actix-web 4.x, sqlx, tokio                     |
| **数据库** | PostgreSQL 16, Redis 7, Meilisearch 1.12, ClickHouse |
| **部署**   | Docker, Docker Compose, Nginx                        |
| **存储**   | 本地文件系统 / Backblaze B2 / S3 兼容存储            |

## 环境要求

### 生产环境部署（Docker 方式）

- **操作系统**: Linux (Ubuntu 20.04+ / Debian 11+ / CentOS 8+)
- **Docker**: 24.0+
- **Docker Compose**: v2.20+
- **内存**: 4GB+（推荐 8GB）
- **磁盘**: 50GB+（含数据库和上传文件存储）
- **域名**: 至少 1 个（推荐 3 个：主站、API、CDN）

### 本地开发

- **Node.js**: 18.0+（推荐 20.x LTS）
- **pnpm**: 9.0+
- **Rust**: stable（最新稳定版）
- **PostgreSQL**: 14+
- **Redis**: 7+
- **Meilisearch**: 1.x
- **ClickHouse**: 最新稳定版

## 快速开始（一键部署）

BBSMC 提供了一键部署脚本 `deploy.sh`，适用于全新的 Linux 服务器。

### 步骤 1：克隆仓库

```bash
git clone https://github.com/StarsevenMeow/app.git
cd app
```

### 步骤 2：运行部署脚本

```bash
chmod +x deploy.sh
sudo ./deploy.sh
```

脚本会自动完成以下操作：

1. ✅ 检查并安装 Docker（支持 Ubuntu/Debian/CentOS）
2. ✅ 停止占用端口（5432/6379/7700/8123/80/443）的冲突服务
3. ✅ 清理旧的 Docker 容器
4. ✅ 创建数据持久化目录
5. ✅ 生成随机密钥和 `.env` 配置文件
6. ✅ 生成 `docker-compose.yml` 和 Nginx 配置
7. ✅ 构建并启动所有 Docker 服务
8. ✅ 输出访问地址和管理密钥

### 步骤 3：配置域名解析

将以下域名 DNS A 记录指向你的服务器 IP：

| 域名               | 用途         |
| ------------------ | ------------ |
| `bbsmc.org.cn`     | 主站（前端） |
| `api.bbsmc.org.cn` | API 接口     |
| `cdn.bbsmc.org.cn` | 静态资源 CDN |

### 步骤 4：配置 SSL 证书（推荐）

部署脚本默认使用 HTTP，建议配置 HTTPS：

```bash
# 安装 certbot
sudo apt install certbot python3-certbot-nginx

# 申请证书（需先完成域名解析）
sudo certbot --nginx -d bbsmc.org.cn -d www.bbsmc.org.cn -d api.bbsmc.org.cn -d cdn.bbsmc.org.cn

# 证书自动续期
sudo crontab -e
# 添加: 0 3 * * * certbot renew --quiet
```

## 手动部署（Docker Compose）

如果你需要更精细的控制，可以手动配置 Docker Compose 部署。

### 步骤 1：克隆仓库

```bash
git clone https://github.com/StarsevenMeow/app.git
cd app
```

### 步骤 2：配置后端环境变量

```bash
cp apps/labrinth/.env apps/labrinth/.env.local
```

编辑 `apps/labrinth/.env`，参考下方 [后端环境变量](#后端环境变量-labrinthenv) 说明，根据实际情况修改：

```bash
# 关键配置项（必须修改）
SITE_URL=https://your-domain.com
CDN_URL=https://cdn.your-domain.com/bbsmc
SELF_ADDR=https://api.your-domain.com

# 数据库（使用 Docker 内部网络）
DATABASE_URL=postgresql://labrinth:YOUR_PASSWORD@postgres:5432/labrinth

# Redis
REDIS_URL=redis://redis:6379

# Meilisearch
MEILISEARCH_ADDR=http://meilisearch:7700
MEILISEARCH_KEY=YOUR_MEILI_KEY

# ClickHouse
CLICKHOUSE_URL=http://clickhouse:8123
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=YOUR_CLICKHOUSE_PASSWORD

# 管理员密钥（请使用随机字符串）
LABRINTH_ADMIN_KEY=YOUR_ADMIN_KEY
RATE_LIMIT_IGNORE_KEY=YOUR_RATE_LIMIT_KEY

# 绑定地址（Docker 内需监听所有接口）
BIND_ADDR=0.0.0.0:8000
```

### 步骤 3：配置前端环境变量

编辑 `apps/frontend/.env`：

```bash
BASE_URL=https://api.your-domain.com/v2/
BROWSER_BASE_URL=https://api.your-domain.com/v2/
```

### 步骤 4：创建 docker-compose.yml

在项目根目录创建 `docker-compose.yml`（参考下方完整配置），或直接使用：

```bash
docker-compose up -d
```

### 步骤 5：初始化数据库

首次启动后，后端会自动运行数据库迁移。如需手动操作：

```bash
# 进入后端容器
docker exec -it bbsmc-labrinth bash

# 运行迁移
./labrinth
```

## 本地开发

### 1. 安装依赖

**Node.js / pnpm（前端）**

```bash
# 安装 pnpm
npm install -g pnpm@9

# 安装前端依赖
pnpm install
```

**Rust（后端）**

```bash
# 安装 Rust（如未安装）
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env

# 安装 sqlx-cli（数据库迁移工具）
cargo install --git https://github.com/launchbadge/sqlx sqlx-cli \
  --no-default-features --features postgres,rustls
```

### 2. 启动基础服务

使用 Docker Compose 启动 PostgreSQL、Redis、Meilisearch、ClickHouse：

```bash
docker-compose up -d postgres_db redis meilisearch clickhouse
```

### 3. 配置环境变量

**后端** (`apps/labrinth/.env`):

```bash
# 本地开发配置（使用 localhost）
DATABASE_URL=postgresql://labrinth:labrinth@localhost/labrinth
REDIS_URL=redis://localhost
MEILISEARCH_ADDR=http://localhost:7700
CLICKHOUSE_URL=http://localhost:8123
BIND_ADDR=127.0.0.1:8000
```

**前端** (`apps/frontend/.env`):

```bash
# 本地开发指向本地后端
BASE_URL=http://localhost:8000/v2/
BROWSER_BASE_URL=http://localhost:8000/v2/
```

### 4. 初始化数据库

```bash
cd apps/labrinth

# 创建数据库
sqlx database create

# 运行迁移
sqlx migrate run

# 回到根目录
cd ../..
```

### 5. 启动开发服务器

**前端开发服务器（热重载）**

```bash
pnpm web:dev
# 访问 http://localhost:3000
```

**后端开发服务器**

```bash
cd apps/labrinth
cargo run
# API 地址 http://localhost:8000
```

### 6. 构建生产版本

**前端构建**

```bash
pnpm web:build
# 输出到 apps/frontend/.output/
```

**后端构建**

```bash
cd apps/labrinth
cargo build --release
# 二进制文件在 target/release/labrinth
```

## 环境变量说明

### 前端环境变量 (`apps/frontend/.env`)

```bash
# API 基础地址（服务端请求用）
BASE_URL=https://api.bbsmc.org.cn/v2/

# API 基础地址（浏览器端请求用）
BROWSER_BASE_URL=https://api.bbsmc.org.cn/v2/
```

| 变量名             | 说明                        | 示例                           |
| ------------------ | --------------------------- | ------------------------------ |
| `BASE_URL`         | 服务端渲染时调用的 API 地址 | `https://api.bbsmc.org.cn/v2/` |
| `BROWSER_BASE_URL` | 浏览器端调用的 API 地址     | `https://api.bbsmc.org.cn/v2/` |

### 后端环境变量 (`apps/labrinth/.env`)

```bash
# ==================== 基础配置 ====================
DEBUG=false                                    # 调试模式（生产环境设为 false）
RUST_LOG=info,sqlx::query=warn                 # 日志级别
SENTRY_DSN=none                               # Sentry 错误监控 DSN

# ==================== 站点配置 ====================
SITE_URL=https://bbsmc.org.cn                  # 主站地址
CDN_URL=https://cdn.bbsmc.org.cn/bbsmc         # CDN 资源地址
CDN_PRIVATE_URL=none                           # 私有 CDN 地址
SELF_ADDR=https://api.bbsmc.org.cn             # API 自身地址

# ==================== 管理密钥 ====================
LABRINTH_ADMIN_KEY=your_admin_key              # 管理员 API 密钥（务必修改）
RATE_LIMIT_IGNORE_KEY=your_rate_limit_key      # 速率限制豁免密钥

# ==================== 数据库 ====================
DATABASE_URL=postgresql://labrinth:password@localhost/labrinth
DATABASE_MIN_CONNECTIONS=0                     # 最小连接数
DATABASE_MAX_CONNECTIONS=16                    # 最大连接数

# ==================== Meilisearch 搜索 ====================
MEILISEARCH_ADDR=http://localhost:7700
MEILISEARCH_KEY=modrinth                        # Meilisearch 主密钥

# ==================== Redis 缓存 ====================
REDIS_URL=redis://localhost
REDIS_MAX_CONNECTIONS=10000
REDIS_NAMESPACE=none                            # 缓存键命名空间
REDIS_WAIT_TIMEOUT_MS=none

# ==================== 服务绑定 ====================
BIND_ADDR=127.0.0.1:8000                       # 监听地址（Docker 内用 0.0.0.0:8000）

# ==================== 文件存储 ====================
STORAGE_BACKEND=local                           # 存储后端: local / s3 / backblaze
MOCK_FILE_PATH=/tmp/modrinth                    # 本地存储路径

# S3 存储（可选）
S3_ACCESS_TOKEN=none
S3_SECRET=none
S3_URL=none
S3_REGION=none
S3_BUCKET_NAME=none
S3_PRIVATE_BUCKET_NAME=none

# Backblaze B2 存储（可选）
BACKBLAZE_KEY_ID=none
BACKBLAZE_KEY=none
BACKBLAZE_BUCKET_ID=none

# ==================== 索引间隔 ====================
LOCAL_INDEX_INTERVAL=3600                       # 本地索引间隔（秒）
VERSION_INDEX_INTERVAL=1800                     # 版本索引间隔（秒）

# ==================== 速率限制 ====================
RATE_LIMIT_IGNORE_IPS='["127.0.0.1"]'           # 豁免速率限制的 IP

# ==================== 域名白名单 ====================
WHITELISTED_MODPACK_DOMAINS='["cdn.bbsmc.org.cn", "github.com", "raw.githubusercontent.com"]'
ALLOWED_CALLBACK_URLS='["localhost", ".bbsmc.org.cn", "127.0.0.1"]'

# ==================== OAuth 登录（可选） ====================
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

# ==================== 支付（可选） ====================
PAYPAL_API_URL=https://api-m.sandbox.paypal.com/v1/
PAYPAL_WEBHOOK_ID=none
PAYPAL_CLIENT_ID=none
PAYPAL_CLIENT_SECRET=none

STRIPE_API_KEY=none
STRIPE_WEBHOOK_SECRET=none

# 七支付（国内支付）
SEVENPAY_API_URL=none
SEVENPAY_CREATE_ORDER_PATH=none
SEVENPAY_QUERY_ORDER_PATH=none
SEVENPAY_VERIFY_MERCHANT_PATH=none
SEVENPAY_KEYCODE=none
SEVENPAY_ALLOWED_IPS=none

# ==================== ClickHouse 分析 ====================
CLICKHOUSE_URL=http://localhost:8123
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=
CLICKHOUSE_DATABASE=staging_ariadne

# ==================== 邮件 SMTP ====================
SMTP_USERNAME=none
SMTP_PASSWORD=none
SMTP_HOST=none

# ==================== 验证码 ====================
HCAPTCHA_SECRET=none                           # hCaptcha 密钥
TAC_URL=none                                   # 腾讯验证码地址

# ==================== 分析与监控 ====================
ANALYTICS_ALLOWED_ORIGINS='["http://127.0.0.1:3000", "http://localhost:3000", "https://bbsmc.org.cn", "https://www.bbsmc.org.cn", "*"]'

MAXMIND_LICENSE_KEY=none                        # MaxMind GeoIP 许可证
FLAME_ANVIL_URL=none                           # Flame Anvil 地址

# ==================== 其他第三方服务 ====================
ADITUDE_API_KEY=none                           # 广告
PYRO_API_KEY=none                              # Pyro 服务
BEEHIIV_PUBLICATION_ID=none                    # 邮件订阅
BEEHIIV_API_KEY=none

STEAM_API_KEY=none                             # Steam

TREMENDOUS_API_URL=https://testflight.tremendous.com/api/v2/
TREMENDOUS_API_KEY=none
TREMENDOUS_PRIVATE_KEY=none
TREMENDOUS_CAMPAIGN_ID=none

# ==================== 通知 ====================
MODERATION_SLACK_WEBHOOK=                      # Slack 审核通知
PUBLIC_DISCORD_WEBHOOK=                        # Discord 公开通知
FEISHU_BOT_WEBHOOK=none                        # 飞书机器人

# ==================== 阿里云短信 ====================
ALIYUN_SMS_ACCESS_KEYID=none
ALIYUN_SMS_ACCESS_KEY_SECRET=none
ALIYUN_SMS_REGION=none
ALIYUN_SMS_REPORT_TEMPLETE_CODE=none
ALIYUN_SMS_SIGN_NAME=none

# ==================== 火山引擎 ====================
HUOSHAN_AK=none
HUOSHAN_SK=none

# ==================== 安全 ====================
ENCRYPTION_KEY=none                            # 敏感数据加密密钥（32字节 Base64）

# ==================== 开发模式 ====================
DEV=false                                      # 开发模式（生产环境设为 false）
```

## Nginx 反向代理配置

生产环境推荐使用 Nginx 作为反向代理，以下是参考配置：

```nginx
# 前端站点
server {
    listen 80;
    server_name bbsmc.org.cn www.bbsmc.org.cn;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name bbsmc.org.cn www.bbsmc.org.cn;

    ssl_certificate /etc/letsencrypt/live/bbsmc.org.cn/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/bbsmc.org.cn/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# API 站点
server {
    listen 443 ssl http2;
    server_name api.bbsmc.org.cn;

    ssl_certificate /etc/letsencrypt/live/api.bbsmc.org.cn/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.bbsmc.org.cn/privkey.pem;

    client_max_body_size 1000M;  # 允许大文件上传

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
    }
}

# CDN 站点
server {
    listen 443 ssl http2;
    server_name cdn.bbsmc.org.cn;

    ssl_certificate /etc/letsencrypt/live/cdn.bbsmc.org.cn/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/cdn.bbsmc.org.cn/privkey.pem;

    root /var/www/uploads;

    location / {
        expires 30d;
        add_header Cache-Control "public, immutable";
        try_files $uri $uri/ =404;
    }
}
```

## 常见问题

### 1. 端口被占用

如果启动时遇到端口冲突，可使用以下命令排查：

```bash
# 查看端口占用
sudo lsof -i :5432   # PostgreSQL
sudo lsof -i :6379   # Redis
sudo lsof -i :7700   # Meilisearch
sudo lsof -i :8123   # ClickHouse
sudo lsof -i :80     # Nginx

# 停止占用端口的系统服务（宝塔面板常见）
sudo systemctl stop redis
sudo systemctl stop clickhouse-server
```

### 2. 数据库迁移失败

```bash
# 手动运行迁移
docker exec -it bbsmc-labrinth bash
./labrinth

# 或使用 sqlx-cli（本地开发）
cd apps/labrinth
sqlx migrate run
```

### 3. 前端构建失败

```bash
# 清理缓存
rm -rf apps/frontend/.nuxt apps/frontend/.output node_modules

# 重新安装依赖
pnpm install

# 重新构建
pnpm web:build
```

### 4. Docker 服务无法启动

```bash
# 查看日志
docker compose logs -f labrinth
docker compose logs -f frontend

# 重启服务
docker compose restart labrinth

# 完全重建
docker compose down
docker compose up -d --build
```

### 5. 修改域名

如需修改域名，需更新以下文件：

1. `apps/labrinth/.env` — `SITE_URL`、`CDN_URL`、`SELF_ADDR`、`ALLOWED_CALLBACK_URLS`
2. `apps/frontend/.env` — `BASE_URL`、`BROWSER_BASE_URL`
3. `apps/frontend/nuxt.config.ts` — 域名相关配置
4. Nginx 配置 — `server_name`

### 6. 查看服务状态

```bash
# 查看所有容器状态
docker compose ps

# 查看资源使用
docker stats

# 查看特定服务日志
docker compose logs -f --tail=100 labrinth
```

## 许可证

本项目基于 Modrinth 开源项目二次开发，遵循 LGPL 协议。

- Modrinth 原项目: https://github.com/modrinth/code
- BBSMC 仓库: https://github.com/StarsevenMeow/app
