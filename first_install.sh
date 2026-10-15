#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly ENV_FILE="${SCRIPT_DIR}/.env"

die() {
  printf 'Fehler: %s\n' "$*" >&2
  exit 1
}

prompt() {
  local variable_name="$1"
  local question="$2"
  local default_value="$3"
  local answer

  read -r -p "${question} [${default_value}]: " answer
  printf -v "${variable_name}" '%s' "${answer:-${default_value}}"
}

command -v docker >/dev/null 2>&1 || die "Docker wurde nicht gefunden."
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 wurde nicht gefunden."
command -v openssl >/dev/null 2>&1 || die "OpenSSL wurde nicht gefunden."

if [[ -e "${ENV_FILE}" ]]; then
  read -r -p ".env existiert bereits. Überschreiben? [j/N]: " overwrite
  [[ "${overwrite,,}" == "j" || "${overwrite,,}" == "ja" ]] || die "Installation abgebrochen; .env blieb unverändert."
  cp -- "${ENV_FILE}" "${ENV_FILE}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
fi

printf '\nAuthentik-Grundkonfiguration\n'
prompt domain "Basisdomain" "example.com"
prompt authentik_fqdn "Hostname für Authentik" "authentik.${domain}"
prompt authentik_tag "Authentik-Version (Release-Zweig oder exakter Tag)" "2026.8"
prompt pg_db "PostgreSQL-Datenbank" "authentik"
prompt pg_user "PostgreSQL-Benutzer" "authentik"

printf '\nTraefik-Konfiguration\n'
prompt proxy_network "Name des vorhandenen externen Traefik-Netzwerks" "proxy"
prompt cert_resolver "Traefik-Certificate-Resolver" "cloudflare_resolver"
prompt trusted_proxies "Vertrauenswürdige Traefik-IP/CIDRs (kommagetrennt)" "172.31.191.254/32,fd00:1:be:a:7001:0:3e:7fff/128"
prompt server_proxy_ipv4 "IPv4 von authentik-server im Traefik-Netz" "172.31.191.128"
prompt server_proxy_ipv6 "IPv6 von authentik-server im Traefik-Netz" "fd00:1:be:a:7001:0:3e:7128"

pg_pass="$(openssl rand -base64 36 | tr -d '\n')"
secret_key="$(openssl rand -base64 60 | tr -d '\n')"

umask 077
{
  printf 'ABSOLUTE_PATH=%s\n' "${SCRIPT_DIR}"
  printf 'PG_DB=%s\n' "${pg_db}"
  printf 'PG_USER=%s\n' "${pg_user}"
  printf 'PG_PASS=%s\n' "${pg_pass}"
  printf 'AUTHENTIK_SECRET_KEY=%s\n' "${secret_key}"
  printf 'AUTHENTIK_TAG=%s\n' "${authentik_tag}"
  printf 'AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS=%s\n' "${trusted_proxies}"
  printf 'NETWORKS_PROXY_NAME=%s\n' "${proxy_network}"
  printf 'NETWORKS_AUTHENTIK_NAME=authentik\n'
  printf 'NETWORKS_AUTHENTIK_SOCKET_NAME=authentik-socket\n'
  printf 'NETWORKS_AUTHENTIK_SUBNET_IPV4=172.30.0.0/24\n'
  printf 'NETWORKS_AUTHENTIK_SUBNET_IPV6=fd00:dead:beef:f0::/64\n'
  printf 'NETWORKS_AUTHENTIK_SOCKET_SUBNET_IPV4=172.30.1.0/24\n'
  printf 'NETWORKS_AUTHENTIK_SOCKET_SUBNET_IPV6=fd00:dead:beef:f1::/64\n'
  printf 'SERVICES_SERVER_IPV4=172.30.0.2\n'
  printf 'SERVICES_SERVER_IPV6=fd00:dead:beef:f0::2\n'
  printf 'SERVICES_WORKER_IPV4=172.30.0.3\n'
  printf 'SERVICES_WORKER_IPV6=fd00:dead:beef:f0::3\n'
  printf 'SERVICES_DATABASE_IPV4=172.30.0.4\n'
  printf 'SERVICES_DATABASE_IPV6=fd00:dead:beef:f0::4\n'
  printf 'SERVICES_SOCKET_PROXY_IPV4=172.30.1.2\n'
  printf 'SERVICES_SOCKET_PROXY_IPV6=fd00:dead:beef:f1::2\n'
  printf 'SERVICES_WORKER_SOCKET_IPV4=172.30.1.3\n'
  printf 'SERVICES_WORKER_SOCKET_IPV6=fd00:dead:beef:f1::3\n'
  printf 'SERVICES_SERVER_PROXY_IPV4=%s\n' "${server_proxy_ipv4}"
  printf 'SERVICES_SERVER_PROXY_IPV6=%s\n' "${server_proxy_ipv6}"
  printf 'TRAEFIK_CERTRESOLVER=%s\n' "${cert_resolver}"
  printf 'TRAEFIK_CERT_DOMAIN=%s\n' "${domain}"
  printf 'TRAEFIK_CERT_WILDCARD=*.%s\n' "${domain}"
  printf 'SERVICES_AUTHENTIK_LABELS_AUTHENTIK_HOST=Host(`%s`)\n' "${authentik_fqdn}"
} > "${ENV_FILE}"

mkdir -p -- "${SCRIPT_DIR}/data" "${SCRIPT_DIR}/certs" \
  "${SCRIPT_DIR}/custom-templates" "${SCRIPT_DIR}/blueprints"

docker network inspect "${proxy_network}" >/dev/null 2>&1 || die "Das externe Docker-Netzwerk '${proxy_network}' existiert nicht. .env wurde erstellt; lege das Netzwerk an oder korrigiere NETWORKS_PROXY_NAME."

(
  cd -- "${SCRIPT_DIR}"
  docker compose config --quiet
) || die "Die erzeugte Compose-Konfiguration ist ungültig."

printf '\nKonfiguration erfolgreich erstellt: %s\n' "${ENV_FILE}"
printf 'Start: cd %q && docker compose pull && docker compose up -d\n' "${SCRIPT_DIR}"
printf 'Ersteinrichtung: https://%s/if/flow/initial-setup/\n' "${authentik_fqdn}"
