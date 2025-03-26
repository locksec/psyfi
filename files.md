# Files and Directories Reference

## Configuration Files

| File/Directory | Purpose | Location |
|----------------|---------|----------|
| `sshd_config` | SSH server configuration | `/etc/ssh/sshd_config` |
| `vault.hcl` | HashiCorp Vault configuration | `/etc/vault.d/vault.hcl` |
| `traefik.yml` | Traefik static configuration | `~/docker-sites/traefik/config/traefik.yml` |
| `acme.json` | Let's Encrypt certificates storage | `~/docker-sites/traefik/data/acme.json` |
| `docker-compose.yml` (Traefik) | Traefik container configuration | `~/docker-sites/traefik/docker-compose.yml` |
| `docker-compose.yml` (Site) | Site-specific container configuration | `~/docker-sites/$SITE_NAME/docker-compose.yml` |
| `nginx.conf` | NGINX configuration for site | `~/docker-sites/$SITE_NAME/nginx/nginx.conf` |
| `Dockerfile` | Jekyll build container configuration | `~/docker-sites/$SITE_NAME/build/Dockerfile` |
| `$SITE_NAME-webhook.json` | Webhook configuration for site | `/etc/webhooks/$SITE_NAME-webhook.json` |

## Scripts

| Script | Purpose | Location |
|--------|---------|----------|
| `generate-site.sh` | Creates configuration for a new Jekyll site | `/usr/local/bin/generate-site.sh` |
| `initialize-$SITE_NAME.sh` | Initializes a site (Git clone) | `/usr/local/bin/initialize-$SITE_NAME.sh` |
| `build-$SITE_NAME.sh` | Builds the Jekyll site | `/usr/local/bin/build-$SITE_NAME.sh` |
| `restart-site.sh` | Starts or restarts a site | `/usr/local/bin/restart-site.sh` |
| `delete-site.sh` | Removes a site | `/usr/local/bin/delete-site.sh` |

## Directories

| Directory | Purpose | Location |
|-----------|---------|----------|
| `docker-sites/` | Root directory for all site configurations | `~/docker-sites/` |
| `traefik/` | Traefik configuration and data | `~/docker-sites/traefik/` |
| `templates/` | Template files used by generate-site.sh | `~/docker-sites/templates/` |
| `$SITE_NAME/` | Site-specific configuration | `~/docker-sites/$SITE_NAME/` |
| `build/` | Jekyll build container files | `~/docker-sites/$SITE_NAME/build/` |
| `nginx/` | NGINX configuration | `~/docker-sites/$SITE_NAME/nginx/` |
| `vault/data` | Vault data storage | `/opt/vault/data` |

## Log Files

| Log File | Purpose | Location |
|----------|---------|----------|
| `webhook_$SITE_NAME.log` | Build and webhook logs for site | `/var/log/webhook_$SITE_NAME.log` |
| Traefik logs | Traefik routing and certificate logs | Docker container logs |

## Network Resources

| Resource | Purpose | Notes |
|----------|---------|-------|
| `traefik-public` | Docker network for Traefik | Created with `docker network create traefik-public` |
| Port 80 | HTTP | Mapped to Traefik container |
| Port 443 | HTTPS | Mapped to Traefik container |
| Port 9000 | Webhook | Only accessible from Docker subnets |
| Port 8200 | Vault API | Only accessible locally `127.0.0.1:8200` |

## Vault Resources

| Resource | Purpose | Example |
|----------|---------|---------|
| `sites/$SITE_NAME` | GitHub token storage | `vault kv put sites/$SITE_NAME github_token="PAT"` |