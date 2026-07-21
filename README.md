# BBSMC

网站地址: https://bbsmc.org.cn

BBSMC 是一个基于 Modrinth 开源项目二次开发的 Minecraft 模组/资源分享平台。

## 项目结构

```
app-main/
├── apps/
│   ├── frontend/      # 前端 (Nuxt.js / Vue 3)
│   ├── labrinth/      # 后端 (Rust / actix-web)
│   └── docs/          # 文档站点 (Astro)
├── packages/
│   ├── api-client/    # API 客户端
│   ├── app-lib/       # 应用库 (Rust)
│   ├── daedalus/      # Daedalus 库
│   └── utils/         # 工具库
└── docker-compose.yml # Docker 编排配置
```

## 技术栈

- **前端**: Nuxt 3, Vue 3, TypeScript, Tailwind CSS
- **后端**: Rust, actix-web, sqlx, PostgreSQL, Redis, Meilisearch, ClickHouse
- **部署**: Docker, Docker Compose, Nginx

## 快速开始

### 一键部署

```bash
./deploy.sh
```

详细说明请参考 [一键部署脚本](#一键部署脚本)。

### 手动部署

#### 前置要求

- Docker & Docker Compose
- Node.js 18+
- pnpm
- Rust (stable)
- PostgreSQL 14+
- Redis 7+
- Meilisearch 1.x
- ClickHouse

#### 前端开发

```bash
pnpm install
pnpm web:dev
```

#### 后端开发

```bash
cd apps/labrinth
cargo run
```

## 部署

### 使用 Docker Compose

```bash
docker-compose up -d
```

### 环境变量

前端环境变量参考 `apps/frontend/.env.example`
后端环境变量参考 `apps/labrinth/.env`

## 许可证

本项目基于 Modrinth 开源项目二次开发，遵循 LGPL 协议。
