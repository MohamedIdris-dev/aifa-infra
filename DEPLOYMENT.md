# AIFA SCENTIQUE — Production Deployment Guide

Complete reference for hosting the AIFA storefront and API on a **Hetzner VPS** with **Docker**, **Nginx**, **Let's Encrypt SSL**, and **GitHub Actions** CI/CD.

> **Live site:** https://aifascentique.shop  
> **Pattern:** Same architecture as [Counter by Novaan](https://counter.novaan.in) — unified VPS, auto-deploy on push to `main`.

---

## Table of contents

1. [Architecture overview](#architecture-overview)
2. [Infrastructure](#infrastructure)
3. [Domain and DNS](#domain-and-dns)
4. [Repository layout](#repository-layout)
5. [Server directory structure](#server-directory-structure)
6. [Docker services and ports](#docker-services-and-ports)
7. [Environment variables](#environment-variables)
8. [First-time deployment](#first-time-deployment)
9. [Nginx and SSL](#nginx-and-ssl)
10. [GitHub Actions CI/CD](#github-actions-cicd)
11. [Deploying updates](#deploying-updates)
12. [Health checks and monitoring](#health-checks-and-monitoring)
13. [Backups](#backups)
14. [Razorpay webhook](#razorpay-webhook)
15. [Troubleshooting](#troubleshooting)
16. [Security checklist](#security-checklist)
17. [Local development](#local-development)

---

## Architecture overview

```
┌─────────────┐     push to main      ┌──────────────────┐
│   GitHub    │ ───────────────────►  │  GitHub Actions  │
│  repos (3)  │                       │  SSH deploy      │
└─────────────┘                       └────────┬─────────┘
                                               │ SSH
                                               ▼
┌──────────────────────────────────────────────────────────────────┐
│  Hetzner VPS — Ubuntu 24.04 (46.224.239.61)                      │
│                                                                  │
│  Nginx (443/80) ──► aifascentique.shop                           │
│       │                                                          │
│       ├── /                              ──► Next.js  :3001      │
│       ├── /health                        ──► Go API   :8080      │
│       ├── /api/store/payments/webhook    ──► Go API   :8080      │
│       └── /api/* (all other)             ──► Next.js BFF ──► Go  │
│                                              (internal api:8080) │
│                                                                  │
│  Docker Compose (aifa-infra/compose)                             │
│       ├── aifa-ecommerce-web      (Next.js 14 standalone)        │
│       ├── aifa-ecommerce-api      (Go API)                       │
│       └── aifa-ecommerce-postgres (PostgreSQL 16)                │
└──────────────────────────────────────────────────────────────────┘
```

### Single-domain design

Everything is served from **one domain** — `https://aifascentique.shop`. There is **no** separate API subdomain.

| Traffic | Handler | Why |
|---------|---------|-----|
| Store pages, admin UI | Next.js | SSR + React |
| Browser `/api/*` calls | Next.js BFF routes | Same-origin, no CORS |
| Server-side BFF → Go | Internal `http://api:8080` | Docker network |
| Razorpay webhooks | Nginx → Go directly | External provider must hit Go |
| Load balancer health | Nginx → Go `/health` | Simple probe |

The frontend uses a **BFF (Backend For Frontend)** pattern: the browser never talks to Go directly. Next.js API routes proxy requests server-to-server inside Docker.

---

## Infrastructure

| Item | Value |
|------|-------|
| **Provider** | Hetzner Cloud VPS |
| **OS** | Ubuntu 24.04 LTS |
| **Hostname** | `backend-platform-prod-1` |
| **Public IP** | `46.224.239.61` |
| **SSH user** | `root` |
| **Reverse proxy** | Nginx |
| **SSL** | Let's Encrypt (Certbot) |
| **Containers** | Docker + Docker Compose v2 |

This VPS also runs other projects (Counter on port 3000, Prince on 8081). AIFA uses **port 3001** for the frontend to avoid conflicts.

---

## Domain and DNS

| Item | Value |
|------|-------|
| **Domain** | `aifascentique.shop` |
| **Registrar / DNS** | Hostinger |
| **Production URL** | https://aifascentique.shop |

### DNS records (Hostinger)

| Type | Name | Value | Notes |
|------|------|-------|-------|
| A | `@` | `46.224.239.61` | Root domain |
| A | `www` | `46.224.239.61` | Redirects to apex via Nginx |

**Remove** old Vercel records before going live:

- A record `@` → `76.76.21.21`
- CNAME `www` → `cname.vercel-dns.com`

### Verify DNS

```bash
dig aifascentique.shop +short
dig www.aifascentique.shop +short
# Both should return: 46.224.239.61
```

---

## Repository layout

Three separate Git repositories:

| Repository | GitHub | Purpose |
|------------|--------|---------|
| `aifa_backend` | [MohamedIdris-dev/aifa_backend](https://github.com/MohamedIdris-dev/aifa_backend) | Go API |
| `aifa_frontend` | [MohamedIdris-dev/aifa_frontend](https://github.com/MohamedIdris-dev/aifa_frontend) | Next.js storefront + admin |
| `aifa-infra` | [MohamedIdris-dev/aifa-infra](https://github.com/MohamedIdris-dev/aifa-infra) | Nginx, prod compose, scripts |

Each repo has a `.github/workflows/deploy.yml` that SSH-deploys on push to `main`.

---

## Server directory structure

```
/apps/
├── aifa-ecommerce-api/
│   └── aifa_backend/          # Go API source (legacy standalone compose also here)
├── aifa-ecommerce-web/
│   └── aifa_frontend/         # Next.js source
└── aifa-infra/
    ├── DEPLOYMENT.md            # This guide
    ├── compose/
    │   ├── docker-compose.prod.yml
    │   └── .env                 # Production secrets (never commit)
    ├── nginx/
    │   └── aifascentique.shop.conf
    └── scripts/
        ├── deploy.sh
        ├── backup-db.sh
        └── server-bootstrap.sh
```

---

## Docker services and ports

Production stack is defined in `aifa-infra/compose/docker-compose.prod.yml`.

| Container | Image | Host port | Internal | Access |
|-----------|-------|-----------|----------|--------|
| `aifa-ecommerce-web` | `aifa-ecommerce-web:latest` | `127.0.0.1:3001` | 3000 | Nginx only |
| `aifa-ecommerce-api` | `aifa-ecommerce-api:latest` | `127.0.0.1:8080` | 8080 | Nginx + internal |
| `aifa-ecommerce-postgres` | `postgres:16` | `127.0.0.1:5432` | 5432 | Localhost only |

### Persistent volumes

| Volume name | Purpose |
|-------------|---------|
| `aifa-ecommerce-postgres-data` | PostgreSQL data |
| `aifa-ecommerce-invoice-data` | Generated invoice PDFs |

> **Important:** Volume names match the original backend-only deployment. Migrating to the unified stack preserves your database.

### Port 3001 (not 3000)

Port **3000** is used by **Counter** (`compose-web-1`) on this VPS. AIFA frontend is published on **3001**. Nginx must proxy to `127.0.0.1:3001`.

---

## Environment variables

Copy `aifa-infra/.env.example` to `.env`, fill secrets, then:

```bash
cp .env compose/.env
```

### Required variables

| Variable | Description | Example |
|----------|-------------|---------|
| `POSTGRES_USER` | DB user (must match existing volume) | `postgres` |
| `POSTGRES_PASSWORD` | DB password (must match existing volume) | *(from backend `.env`)* |
| `POSTGRES_DB` | Database name (must match existing volume) | `aifa_db` |
| `JWT_SECRET` | General JWT signing | `openssl rand -hex 32` |
| `JWT_ADMIN_SECRET` | Admin JWT signing | `openssl rand -hex 32` |
| `JWT_CUSTOMER_SECRET` | Customer JWT signing | `openssl rand -hex 32` |
| `NEXT_PUBLIC_APP_URL` | Public storefront URL | `https://aifascentique.shop` |
| `NEXT_PUBLIC_API_URL` | Public API URL (same domain) | `https://aifascentique.shop` |
| `VERIFY_EMAIL_BASE_URL` | Email verification links | `https://aifascentique.shop` |
| `WEB_PUBLISH_PORT` | Host port for Next.js | `3001` |

### Optional variables

| Variable | Description |
|----------|-------------|
| `NEXT_PUBLIC_STORE_NAME` | Display name (default: AIFA SCENTIQUE) |
| `CLOUDINARY_*` | Admin image uploads |
| `SMTP_*` | Real order/verification emails |
| `RAZORPAY_*` | Payment gateway |
| `INVOICE_PDF_DIR` | PDF output (default: `/app/invoices`) |

### Production database credentials

The live database was initialized with:

```env
POSTGRES_USER=postgres
POSTGRES_DB=aifa_db
```

`POSTGRES_PASSWORD` must **exactly match** the password used when the Postgres volume was first created. Changing it in `.env` alone does **not** update the database — the API will fail with:

```
FATAL: password authentication failed for user "postgres"
```

Always copy Postgres credentials from `/apps/aifa-ecommerce-api/aifa_backend/.env`.

### Internal vs public URLs

| Context | `API_URL` / `NEXT_PUBLIC_API_URL` |
|---------|-----------------------------------|
| Docker runtime (BFF → Go) | `http://api:8080` (set automatically in compose) |
| Browser / build args | `https://aifascentique.shop` |

---

## First-time deployment

### Prerequisites

- [ ] DNS A records point to `46.224.239.61`
- [ ] SSH access: `ssh root@46.224.239.61`
- [ ] Docker installed on VPS
- [ ] Code pushed to all three GitHub repos

### Step 1 — Clone repositories

```bash
ssh root@46.224.239.61

mkdir -p /apps/aifa-ecommerce-api /apps/aifa-ecommerce-web

git clone git@github.com:MohamedIdris-dev/aifa-infra.git /apps/aifa-infra
git clone git@github.com:MohamedIdris-dev/aifa_backend.git /apps/aifa-ecommerce-api/aifa_backend
git clone git@github.com:MohamedIdris-dev/aifa_frontend.git /apps/aifa-ecommerce-web/aifa_frontend
```

### Step 2 — Bootstrap server (first time only)

Skip if Docker and Nginx are already installed.

```bash
cd /apps/aifa-infra/scripts
chmod +x *.sh
./server-bootstrap.sh
```

### Step 3 — Configure environment

```bash
cd /apps/aifa-infra
cp .env.example .env
nano .env
```

Copy values from the existing backend:

```bash
grep -E '^(POSTGRES_|JWT_|RAZORPAY|CLOUDINARY|SMTP)' /apps/aifa-ecommerce-api/aifa_backend/.env
```

Ensure these are set:

```env
POSTGRES_USER=postgres
POSTGRES_PASSWORD=<from backend .env>
POSTGRES_DB=aifa_db
WEB_PUBLISH_PORT=3001

NEXT_PUBLIC_APP_URL=https://aifascentique.shop
NEXT_PUBLIC_API_URL=https://aifascentique.shop
VERIFY_EMAIL_BASE_URL=https://aifascentique.shop
```

```bash
cp .env compose/.env
```

### Step 4 — Stop legacy backend-only stack

```bash
cd /apps/aifa-ecommerce-api/aifa_backend
docker compose down
```

This stops the old API + Postgres containers but **keeps volumes**.

### Step 5 — Start unified production stack

```bash
cd /apps/aifa-infra/compose
docker compose -f docker-compose.prod.yml up -d --build
```

First build takes **10–15 minutes**.

```bash
docker compose -f docker-compose.prod.yml ps
curl -s http://127.0.0.1:8080/health    # → ok
curl -sI http://127.0.0.1:3001/         # → HTTP 200
```

### Step 6 — Nginx and SSL

See [Nginx and SSL](#nginx-and-ssl) below.

---

## Nginx and SSL

Config file: `aifa-infra/nginx/aifascentique.shop.conf`

### Upstreams (critical)

```nginx
upstream aifa_web {
    server 127.0.0.1:3001;   # AIFA Next.js — NOT 3000 (Counter uses 3000)
}

upstream aifa_api {
    server 127.0.0.1:8080;   # AIFA Go API — NOT 3001
}
```

### Install site config

```bash
sudo cp /apps/aifa-infra/nginx/aifascentique.shop.conf /etc/nginx/sites-available/
sudo ln -sf /etc/nginx/sites-available/aifascentique.shop.conf /etc/nginx/sites-enabled/
```

### SSL with Certbot

If certificates do **not** exist yet, use an **HTTP-only** config first (no `ssl_certificate` lines), then:

```bash
sudo mkdir -p /var/www/certbot
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d aifascentique.shop -d www.aifascentique.shop
```

Certbot adds SSL and HTTP→HTTPS redirect automatically.

After Certbot, verify upstream ports are still **3001** and **8080**:

```bash
grep -A1 "upstream aifa" /etc/nginx/sites-available/aifascentique.shop.conf
sudo nginx -t && sudo systemctl reload nginx
```

### SSL renewal

Certbot installs a systemd timer. Test renewal:

```bash
sudo certbot renew --dry-run
```

Certificate path: `/etc/letsencrypt/live/aifascentique.shop/`

---

## GitHub Actions CI/CD

### How it works

```
git push main  →  GitHub Actions  →  SSH to VPS  →  git pull  →  docker compose build  →  up -d
```

Each repo deploys **only its service** (`--no-deps`) so Postgres is not restarted.

| Repo | Workflow | Service rebuilt |
|------|----------|-----------------|
| `aifa_frontend` | Deploy Web (Production) | `web` |
| `aifa_backend` | Deploy API (Production) | `api` |

### Required GitHub secrets

Add to **both** `aifa_frontend` and `aifa_backend`:

| Secret | Value |
|--------|-------|
| `VPS_HOST` | `46.224.239.61` |
| `VPS_USER` | `root` |
| `VPS_SSH_KEY` | Full private SSH key (PEM, including `BEGIN`/`END` lines) |

**Settings → Secrets and variables → Actions → Repository secrets**

### Manual trigger

GitHub → repo → **Actions** → **Deploy Web/API (Production)** → **Run workflow**

### VPS paths (used by workflows)

| Variable | Path |
|----------|------|
| Frontend | `/apps/aifa-ecommerce-web/aifa_frontend` |
| Backend | `/apps/aifa-ecommerce-api/aifa_backend` |
| Compose | `/apps/aifa-infra/compose` |

---

## Deploying updates

### Automatic (recommended)

```bash
# On your laptop
git push origin main
```

GitHub Actions handles the rest.

### Manual (full stack)

```bash
cd /apps/aifa-infra/scripts
./deploy.sh
```

### Manual (single service)

```bash
cd /apps/aifa-infra/compose

# Frontend only
docker compose -f docker-compose.prod.yml build web
docker compose -f docker-compose.prod.yml up -d --no-deps web

# API only
docker compose -f docker-compose.prod.yml build api
docker compose -f docker-compose.prod.yml up -d --no-deps api
```

### Rebuild from scratch (cache issues)

```bash
cd /apps/aifa-infra/compose
docker compose -f docker-compose.prod.yml down
docker compose -f docker-compose.prod.yml build --no-cache
docker compose -f docker-compose.prod.yml up -d
```

> Do **not** run `docker volume rm` unless you intend to wipe the database.

---

## Health checks and monitoring

### Public (via Nginx)

```bash
curl -sI https://aifascentique.shop
curl -s https://aifascentique.shop/health
```

### Local (on VPS)

```bash
curl -s http://127.0.0.1:8080/health
curl -sI http://127.0.0.1:3001/
```

### Container status

```bash
cd /apps/aifa-infra/compose
docker compose -f docker-compose.prod.yml ps
```

Expected:

```
aifa-ecommerce-web        Up
aifa-ecommerce-api        Up (healthy)
aifa-ecommerce-postgres   Up (healthy)
```

### Logs

```bash
cd /apps/aifa-infra/compose
docker compose -f docker-compose.prod.yml logs -f web
docker compose -f docker-compose.prod.yml logs -f api
docker compose -f docker-compose.prod.yml logs -f postgres
```

### Nginx

```bash
sudo nginx -t
sudo systemctl status nginx
```

---

## Backups

### Manual backup

```bash
/apps/aifa-infra/scripts/backup-db.sh
```

Backups are stored in `/var/backups/aifa/` (14-day retention).

### Schedule daily backups

```bash
crontab -e
```

Add:

```
0 3 * * * /apps/aifa-infra/scripts/backup-db.sh
```

---

## Razorpay webhook

In **Razorpay Dashboard → Settings → Webhooks**, set:

```
https://aifascentique.shop/api/store/payments/webhook
```

Nginx routes this path directly to the Go API (bypassing Next.js).

Ensure `RAZORPAY_WEBHOOK_SECRET` in `compose/.env` matches the dashboard.

---

## Troubleshooting

### API unhealthy — password authentication failed

**Symptom:**

```
FATAL: password authentication failed for user "postgres"
```

**Cause:** `POSTGRES_USER`, `POSTGRES_PASSWORD`, or `POSTGRES_DB` in `compose/.env` does not match the existing Postgres volume.

**Fix:**

```bash
grep -E '^(POSTGRES_|DATABASE_URL)' /apps/aifa-ecommerce-api/aifa_backend/.env
nano /apps/aifa-infra/compose/.env   # match exactly
cp /apps/aifa-infra/compose/.env /apps/aifa-infra/.env
cd /apps/aifa-infra/compose && docker compose -f docker-compose.prod.yml up -d api web
```

---

### Wrong site loads (Counter instead of AIFA)

**Cause:** Nginx `aifa_web` upstream points to port **3000** instead of **3001**.

**Fix:**

```bash
sudo nano /etc/nginx/sites-available/aifascentique.shop.conf
# aifa_web → 127.0.0.1:3001
# aifa_api → 127.0.0.1:8080
sudo nginx -t && sudo systemctl reload nginx
```

---

### Nginx fails — SSL certificate not found

**Symptom:**

```
cannot load certificate "/etc/letsencrypt/live/aifascentique.shop/fullchain.pem"
```

**Fix:** Use HTTP-only config first, then run Certbot:

```bash
sudo certbot --nginx -d aifascentique.shop -d www.aifascentique.shop
```

---

### Port 3001 already in use

```bash
sudo ss -tlnp | grep 3001
docker ps
```

Change `WEB_PUBLISH_PORT` in `.env` and update Nginx upstream to match.

---

### Web container won't start — API dependency failed

API must be healthy before web starts. Check API logs:

```bash
docker compose -f docker-compose.prod.yml logs --tail=50 api
```

---

### GitHub Actions deploy fails — SSH

| Error | Fix |
|-------|-----|
| Permission denied | Verify `VPS_SSH_KEY` is the **private** key; public key is in `/root/.ssh/authorized_keys` |
| Missing secret | Names must be `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY` |
| compose/.env not found | Complete [first-time deployment](#first-time-deployment) |

---

### Build fails — frontend out of memory

Next.js build needs ~2 GB RAM. If the VPS is tight on memory:

```bash
# Add swap temporarily
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

Then rebuild.

---

## Security checklist

- [ ] Strong unique `POSTGRES_PASSWORD`
- [ ] Unique `JWT_*` secrets (`openssl rand -hex 32` each)
- [ ] `GO_ENV=production` on API (set in prod compose — enables secure admin cookies)
- [ ] `VERIFY_EMAIL_BASE_URL=https://aifascentique.shop`
- [ ] API, web, and Postgres bound to `127.0.0.1` only (not `0.0.0.0`)
- [ ] SSL enabled (HTTPS redirect)
- [ ] `.env` files never committed to git
- [ ] GitHub secrets use deploy SSH key (not your personal key if possible)
- [ ] Razorpay webhook secret configured
- [ ] Daily database backups scheduled
- [ ] Vercel project removed after cutover

---

## Local development

Unchanged from before VPS deployment:

```bash
# Terminal 1 — API + Postgres
cd backend
cp .env.example .env
docker compose up -d

# Terminal 2 — Frontend
cd frontend
cp .env.example .env
npm install && npm run dev
```

Frontend `.env`:

```env
API_URL=http://localhost:8080
NEXT_PUBLIC_API_URL=http://localhost:8080
```

Open http://localhost:3000

---

## Quick reference

| Task | Command |
|------|---------|
| SSH to server | `ssh root@46.224.239.61` |
| Stack status | `docker compose -f /apps/aifa-infra/compose/docker-compose.prod.yml ps` |
| Restart all | `cd /apps/aifa-infra/compose && docker compose -f docker-compose.prod.yml up -d` |
| API logs | `docker compose -f docker-compose.prod.yml logs -f api` |
| Web logs | `docker compose -f docker-compose.prod.yml logs -f web` |
| Health check | `curl -s https://aifascentique.shop/health` |
| Reload Nginx | `sudo nginx -t && sudo systemctl reload nginx` |
| Backup DB | `/apps/aifa-infra/scripts/backup-db.sh` |

---

*Last updated: July 2026 — reflects live production on `backend-platform-prod-1` (Hetzner).*
