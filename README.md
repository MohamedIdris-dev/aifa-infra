# AIFA infrastructure

Production hosting for **AIFA SCENTIQUE** on Hetzner VPS — Docker Compose, Nginx, SSL, and deploy scripts.

| Item | Value |
|------|-------|
| **Live site** | https://aifascentique.shop |
| **VPS** | `46.224.239.61` |
| **Frontend** | `127.0.0.1:3001` |
| **API** | `127.0.0.1:8080` |

## Documentation

**[DEPLOYMENT.md](DEPLOYMENT.md)** — full production guide (architecture, DNS, env vars, Nginx, Certbot, CI/CD, troubleshooting).

## Repository layout

```
aifa-infra/
├── DEPLOYMENT.md
├── .env.example
├── compose/
│   └── docker-compose.prod.yml   # web + api + postgres
├── nginx/
│   └── aifascentique.shop.conf
└── scripts/
    ├── deploy.sh
    ├── backup-db.sh
    └── server-bootstrap.sh
```

## Quick start (on server)

```bash
cp .env.example .env && nano .env
cp .env compose/.env
cd compose && docker compose -f docker-compose.prod.yml up -d --build
```

## Related repos

| Repo | Role |
|------|------|
| [aifa_backend](https://github.com/MohamedIdris-dev/aifa_backend) | Go API |
| [aifa_frontend](https://github.com/MohamedIdris-dev/aifa_frontend) | Next.js storefront + admin |

Push to `main` on frontend or backend triggers GitHub Actions deploy (see DEPLOYMENT.md).
