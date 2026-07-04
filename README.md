# AIFA infrastructure

Nginx configs, production Docker Compose, and server scripts for Hetzner VPS deployment.

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for the full guide.

## Quick start (on server)

```bash
cp .env.example .env && nano .env
cp .env compose/.env
cd compose && docker compose -f docker-compose.prod.yml up -d --build
```

## Publish as its own git repo

```bash
cd infra
git init
git add .
git commit -m "Initial AIFA infra"
git remote add origin git@github.com:MohamedIdris-dev/aifa-infra.git
git push -u origin main
```
