#!/usr/bin/env bash
# Apply or diff the repo nginx site config against the live VPS file.
# Run on the server from aifa-infra (typically /apps/aifa-infra).
#
# Usage:
#   sudo ./scripts/apply-nginx.sh --diff   # print live vs repo, no changes
#   sudo ./scripts/apply-nginx.sh          # backup, install, nginx -t, reload
set -euo pipefail

SITE_NAME="aifascentique.shop.conf"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_CONF="${REPO_ROOT}/nginx/${SITE_NAME}"
LIVE_AVAILABLE="/etc/nginx/sites-available/${SITE_NAME}"
LIVE_ENABLED="/etc/nginx/sites-enabled/${SITE_NAME}"

usage() {
  cat <<'EOF'
Usage: sudo ./scripts/apply-nginx.sh [--diff]

  --diff   Show diff between live and repo config; make no changes.
  (default) Backup live config, copy repo file into place, ensure
            sites-enabled symlink, run nginx -t, reload on success.
            On nginx -t failure, restore the backup and exit non-zero.
EOF
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root (sudo)." >&2
    exit 1
  fi
}

require_repo_conf() {
  if [[ ! -f "${REPO_CONF}" ]]; then
    echo "Missing repo config: ${REPO_CONF}" >&2
    exit 1
  fi
}

mode_diff() {
  require_repo_conf
  if [[ ! -f "${LIVE_AVAILABLE}" ]]; then
    echo "Live file missing: ${LIVE_AVAILABLE}" >&2
    echo "Repo file would be installed from: ${REPO_CONF}" >&2
    exit 1
  fi
  echo "diff -u ${LIVE_AVAILABLE} ${REPO_CONF}"
  if diff -u "${LIVE_AVAILABLE}" "${REPO_CONF}"; then
    echo "No differences."
  fi
}

mode_apply() {
  require_root
  require_repo_conf

  local backup=""
  if [[ -f "${LIVE_AVAILABLE}" ]]; then
    backup="${LIVE_AVAILABLE}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
    cp -a "${LIVE_AVAILABLE}" "${backup}"
    echo "Backed up live config to ${backup}"
  else
    echo "No existing live config at ${LIVE_AVAILABLE}; installing fresh."
  fi

  cp "${REPO_CONF}" "${LIVE_AVAILABLE}"
  ln -sfn "${LIVE_AVAILABLE}" "${LIVE_ENABLED}"
  echo "Installed ${LIVE_AVAILABLE} and ensured ${LIVE_ENABLED} → ${LIVE_AVAILABLE}"

  if nginx -t; then
    systemctl reload nginx
    echo "nginx -t OK; nginx reloaded."
    return 0
  fi

  echo "nginx -t failed." >&2
  if [[ -n "${backup}" && -f "${backup}" ]]; then
    cp -a "${backup}" "${LIVE_AVAILABLE}"
    echo "Restored backup ${backup} → ${LIVE_AVAILABLE}" >&2
  else
    echo "No backup to restore (fresh install failed validation)." >&2
  fi
  exit 1
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  --diff)
    mode_diff
    ;;
  "")
    mode_apply
    ;;
  *)
    echo "Unknown option: $1" >&2
    usage >&2
    exit 1
    ;;
esac
