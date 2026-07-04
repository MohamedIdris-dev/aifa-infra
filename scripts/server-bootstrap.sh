#!/usr/bin/env bash
# One-time Ubuntu 24.04 server setup for AIFA on Hetzner VPS.
# Run as root or with sudo.
set -euo pipefail

echo "==> Updating packages"
apt-get update && apt-get upgrade -y

echo "==> Installing Docker, Nginx, Certbot"
apt-get install -y ca-certificates curl gnupg ufw nginx certbot python3-certbot-nginx git
install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
fi
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

echo "==> Firewall (SSH + HTTP/S)"
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

echo "==> Certbot webroot"
mkdir -p /var/www/certbot

echo "==> Application directories"
mkdir -p /apps/aifa-ecommerce-api
mkdir -p /apps/aifa-ecommerce-web
mkdir -p /apps/aifa-infra

echo "Done. Next steps:"
echo "  1. Clone aifa_backend, aifa_frontend, and aifa-infra under /apps"
echo "  2. Copy nginx configs from aifa-infra/nginx/ to /etc/nginx/sites-available/"
echo "  3. Configure compose/.env from aifa-infra/.env.example"
echo "  4. See docs/DEPLOYMENT.md"
