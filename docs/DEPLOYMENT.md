# AIFA SCENTIQUE — Production deployment

Deploy on a **Hetzner VPS** (Ubuntu 24.04) with **Docker**, **Nginx**, and **GitHub Actions** CI/CD.

## Domain

**https://aifascentique.shop** — single domain for both frontend and backend (Hostinger DNS).

| Path | Routed to |
|------|-----------|
| `/` (store, admin, BFF `/api/*`) | Next.js :3000 |
| `/health` | Go API :8080 |
| `/api/store/payments/webhook` | Go API :8080 (Razorpay) |

No separate API subdomain. The Next.js BFF proxies all other API calls to Go over the internal Docker network (`http://api:8080`).

## Architecture

```
GitHub → GitHub Actions → SSH → Hetzner VPS → Docker Compose → Nginx → aifascentique.shop
                                                              ├── Next.js (3000)
                                                              ├── Go API (8080, internal + webhook/health)
                                                              └── PostgreSQL
```

## Repository layout

Three git repositories under `/apps`:

```
/apps/
├── aifa-ecommerce-api/aifa_backend/    ← github.com/MohamedIdris-dev/aifa_backend
├── aifa-ecommerce-web/aifa_frontend/   ← github.com/MohamedIdris-dev/aifa_frontend
└── aifa-infra/                         ← nginx, compose, scripts
```

## Migrating from Vercel + IP-based API

You previously used the VPS IP (`46.224.239.61:8080`) on Vercel because the domain wasn't ready. Now:

1. Point `aifascentique.shop` DNS (Hostinger) → `46.224.239.61`
2. Deploy frontend to the VPS (this guide)
3. Update `infra/compose/.env`:
   - `NEXT_PUBLIC_APP_URL=https://aifascentique.shop`
   - `NEXT_PUBLIC_API_URL=https://aifascentique.shop`
   - `VERIFY_EMAIL_BASE_URL=https://aifascentique.shop`
4. Configure Nginx + SSL for `aifascentique.shop`
5. Remove Vercel deployment

The production compose reuses existing Docker volume names, so your database is preserved.

## First-time server setup

```bash
ssh root@46.224.239.61

git clone git@github.com:MohamedIdris-dev/aifa-infra.git /apps/aifa-infra
cd /apps/aifa-infra/scripts && chmod +x *.sh && ./server-bootstrap.sh

git clone git@github.com:MohamedIdris-dev/aifa_backend.git /apps/aifa-ecommerce-api/aifa_backend
git clone git@github.com:MohamedIdris-dev/aifa_frontend.git /apps/aifa-ecommerce-web/aifa_frontend
```

## Configure secrets

```bash
cd /apps/aifa-infra
cp .env.example .env
nano .env   # POSTGRES_PASSWORD, JWT_*, Razorpay, SMTP, Cloudinary

cp .env compose/.env
```

Copy secrets from your existing `/apps/aifa-ecommerce-api/aifa_backend/.env`.

**Never commit `.env` files.**

## Start the stack

```bash
# If migrating from backend-only compose:
cd /apps/aifa-ecommerce-api/aifa_backend && docker compose down

cd /apps/aifa-infra/compose
docker compose -f docker-compose.prod.yml up -d --build
docker compose -f docker-compose.prod.yml ps
```

## Nginx + SSL

```bash
sudo cp /apps/aifa-infra/nginx/aifascentique.shop.conf /etc/nginx/sites-available/
sudo ln -sf /etc/nginx/sites-available/aifascentique.shop.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# After DNS propagates:
sudo certbot --nginx -d aifascentique.shop -d www.aifascentique.shop
```

## Razorpay webhook URL

In the Razorpay dashboard, set the webhook URL to:

```
https://aifascentique.shop/api/store/payments/webhook
```

## GitHub Actions CI/CD

Add these secrets to **both** `aifa_frontend` and `aifa_backend` repos:

| Secret | Value |
|--------|-------|
| `VPS_HOST` | `46.224.239.61` |
| `VPS_USER` | `root` |
| `VPS_SSH_KEY` | Private SSH key (full PEM) |

Push to `main` auto-deploys the `web` or `api` container.

## Health checks

```bash
curl -sI https://aifascentique.shop
curl -s https://aifascentique.shop/health
docker compose -f /apps/aifa-infra/compose/docker-compose.prod.yml ps
```

## Logs

```bash
cd /apps/aifa-infra/compose
docker compose -f docker-compose.prod.yml logs -f web
docker compose -f docker-compose.prod.yml logs -f api
```

## Backups

```bash
/apps/aifa-infra/scripts/backup-db.sh
# Cron: 0 3 * * * /apps/aifa-infra/scripts/backup-db.sh
```

## Security checklist

- [ ] Strong `POSTGRES_PASSWORD`
- [ ] Unique `JWT_*` secrets (`openssl rand -hex 32`)
- [ ] `GO_ENV=production` on API (secure admin cookies)
- [ ] `VERIFY_EMAIL_BASE_URL=https://aifascentique.shop`
- [ ] API/Postgres bound to `127.0.0.1` only
- [ ] DNS A record for `aifascentique.shop` → VPS IP
- [ ] SSL via Certbot
- [ ] Razorpay webhook URL updated to new domain
- [ ] Vercel project removed after cutover
