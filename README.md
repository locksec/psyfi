# PsyFi - Secure Jekyll Hosting Platform
# Version 0.1.4-beta

A comprehensive solution for hosting multiple Jekyll sites on a single server with automated deployments, HTTPS, and secure management.

## Table of Contents
- [PsyFi - Secure Jekyll Hosting Platform](#psyfi---secure-jekyll-hosting-platform)
- [Version 0.1.4-beta](#version-014-beta)
  - [Table of Contents](#table-of-contents)
- [Overview](#overview)
  - [Features](#features)
  - [Prerequisites](#prerequisites)
  - [Architecture](#architecture)
- [Server Installation](#server-installation)
  - [Overview](#overview-1)
  - [1. Initial Setup](#1-initial-setup)
  - [2. Automated Setup with the Setup Script](#2-automated-setup-with-the-setup-script)
    - [Cloning the PsyFi Repository](#cloning-the-psyfi-repository)
    - [Running the Setup Script](#running-the-setup-script)
  - [3. HashiCorp Vault Initialization](#3-hashicorp-vault-initialization)
- [Site Management](#site-management)
  - [Add a Site](#add-a-site)
    - [Generate Site](#generate-site)
      - [Examples](#examples)
      - [Options](#options)
    - [Initialize Site (Git Clone)](#initialize-site-git-clone)
    - [GitHub Webhook Setup](#github-webhook-setup)
  - [CloudFlare Rules](#cloudflare-rules)
  - [LetsEncrypt ACME Challenge](#letsencrypt-acme-challenge)
    - [Step 1: Create a Configuration Rule](#step-1-create-a-configuration-rule)
    - [Step 2: Create a Cache Rule](#step-2-create-a-cache-rule)
- [Maintenance](#maintenance)
  - [HashiCorp Vault](#hashicorp-vault)
  - [SSL Certificates](#ssl-certificates)
  - [WebHooks \& Jekyll Builds](#webhooks--jekyll-builds)
  - [Site Deployment](#site-deployment)
  - [Webhook Domain Configuration](#webhook-domain-configuration)
    - [Setting Up Your Webhook Domain](#setting-up-your-webhook-domain)
- [Congratulations!](#congratulations)


# Overview
This project provides a complete setup for a self-hosted Jekyll platform, giving you full control over your infrastructure. It uses Docker, Traefik, and HashiCorp Vault to create a robust, secure hosting environment for multiple static sites.

## Features
- Multi-site Support: Host multiple Jekyll sites on a single server
- Automated Deployments: Push to GitHub, and webhooks trigger your site to rebuild automatically
- HTTPS Support: Automatic SSL certificates via Let's Encrypt
- Secure Secret Management: GitHub tokens and other secrets stored in HashiCorp Vault
- Docker Containerization: Each site isolated in its own container
- Reverse Proxy: Traefik handles routing, SSL termination, and load balancing
- Optimized Web Performance: Each site includes Nginx with gzip compression and cache headers for static assets

## Prerequisites
- Ubuntu 24.04 server (Digital Ocean droplet recommended)
- Domain names with proper DNS configuration (www, staging, apex)
- GitHub repositories containing Jekyll sites
- GitHub personal access tokens (PAT) for private repositories

## Architecture
Each site consists of:

- A web container running Nginx to serve the static files
- A build container that runs Jekyll to build the site
- Webhook configurations to trigger rebuilds on GitHub push events

The system also includes:
- A centralized webhook proxy that routes GitHub webhook events through a dedicated domain
- Traefik for SSL termination and routing requests to the appropriate containers
- HashiCorp Vault for secure storage of GitHub tokens and other secrets

[Files & Directories](files.md)

# Server Installation

## Overview
1. Build Ubuntu 24.04 VPS on Digital Ocean with an SSH key for access
2. Login as `root` with SSH key (generated and provided to Digital Ocean)
3. Create new user and add to `sudo`
4. Create `~/.ssh` directory and copy `/root/.ssh/authorized_keys` to `~/.ssh/authorized_keys`
5. Login with new user
6. Run the automated setup script to install and configure everything

## 1. Initial Setup
**Add user**
```bash
adduser new_user
usermod -aG sudo new_user
```

**Copy `authorized_keys` to user**
```bash
su - new_user
mkdir -p ~/.ssh
chmod 700 ~/.ssh
sudo cat /root/.ssh/authorized_keys > ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

**Disable root and password login via ssh**
```bash
sudo vi /etc/ssh/sshd_config
PermitRootLogin no
PasswordAuthentication no
```

**Restart SSH**
```bash
sudo systemctl restart ssh
```

**Add Firewall Rules**:
```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Allow port 9000 from Docker subnets for Webhook
sudo ufw allow from 172.17.0.0/16 to any port 9000
sudo ufw allow from 172.18.0.0/16 to any port 9000
```

**Enable firewall**
```bash
sudo ufw enable
sudo ufw status
sudo systemctl daemon-reload
```

```diff
- Note: Now exit and log back in as the new user to continue.
```

## 2. Automated Setup with the Setup Script
The setup script handles all installation and configuration tasks automatically, including:
- Installing required packages (Docker, webhook, Vault, etc.)
- Setting up Traefik configuration
- Configuring the webhook proxy
- Setting up HashiCorp Vault
- Creating the necessary directory structure

### Cloning the PsyFi Repository
First, clone the PsyFi repository to get the necessary scripts and templates:

```bash
cd ~
git clone https://github.com/locksec/psyfi.git
```

**Alternatively, if using SSH authentication:**
```bash
git clone git@github.com:locksec/psyfi.git
```

### Running the Setup Script

Set your admin email for Let's Encrypt certificates:

```bash
export ADMIN_EMAIL=your@email.com
```

Run the setup script:

```bash
# After cloning, navigate to the psyfi directory (wherever you cloned it)
cd psyfi
chmod +x setup.sh
./setup.sh
```

```diff
- Note: Log out and log back in for docker permissions to take effect.
```

After logging back in, you don't need to manually create the Docker network or start Traefik - the `generate-site.sh` script will check for these services and start them automatically when needed.

## 3. HashiCorp Vault Initialization

```bash
export VAULT_ADDR='http://127.0.0.1:8200'
echo 'export VAULT_ADDR="http://127.0.0.1:8200"' >> ~/.bashrc
```

**Initialize Vault:**
```bash
vault operator init

# Save the output - you'll get 5 unseal keys and a root token
# Example output:
# Unseal Key 1: xxxxx
# Unseal Key 2: xxxxx
# Unseal Key 3: xxxxx
# Unseal Key 4: xxxxx
# Unseal Key 5: xxxxx
# Initial Root Token: xxxxx
```

**Note**: Save this somewhere safe such as a password manager

**Check Vault Status**
```bash
vault status
```

**Unseal vault (need 3 of 5 keys):**
```
vault operator unseal
```

**Enable secrets engine:**
```bash
vault login  # Use root token
vault secrets enable -path=sites kv
```

# Site Management
## Add a Site

**Assign Site Variables**
```bash
export SITE_NAME=example
export DOMAIN=example.com
export GITHUB_REPO=user/example
export WEBHOOK_DOMAIN=hooks.example.com
```

Optionally you can set a manual webhook secret:
```bash
export WEBHOOK_SECRET=123456789
```

**Note**: If you already have a webhook secret, assign it above and use with `--webhook-secret $WEBHOOK_SECRET` in the `generate-site.sh` script below. Otherwise, just omit `--webhook-secret`, and the script will generate one for you.

 **Create GitHub Personal Access Token:**
 1. Go to https://github.com/settings/tokens?type=beta
 2. Generate new token with access to the correct site repo
 3. Copy token value

**Store GitHub token in Vault**
```bash
vault kv put sites/$SITE_NAME github_token="PAT"
```

**Check token**
```bash
vault kv get sites/$SITE_NAME
```

### Generate Site
```bash
/usr/local/bin/generate-site.sh --site-name "$SITE_NAME" --domain "$DOMAIN" --github-repo $GITHUB_REPO --sub-domain "${SUBDOMAINS[@]}"
```

The script will automatically:
- Check and create the Traefik network if needed
- Start Traefik if it's not already running
- Start the webhook proxy if it's not already running
- Generate all necessary configuration files for your site

#### Examples

**Apex domain (example.com) with www subdomain:**
```bash
/usr/local/bin/generate-site.sh --site-name $SITE_NAME --domain $DOMAIN --github-repo $GITHUB_REPO --sub-domain www
```

**Multiple subdomains with apex:**
```bash
# Using direct parameters
/usr/local/bin/generate-site.sh --site-name $SITE_NAME --domain $DOMAIN --github-repo $GITHUB_REPO --sub-domain www staging test

# Using an array variable
SUBDOMAINS=("www" "staging" "test")
/usr/local/bin/generate-site.sh --site-name $SITE_NAME --domain $DOMAIN --github-repo $GITHUB_REPO --sub-domain "${SUBDOMAINS[@]}"
```

**Staging subdomain without apex domain:**
```bash
/usr/local/bin/generate-site.sh --site-name $SITE_NAME --domain $DOMAIN --github-repo $GITHUB_REPO --sub-domain staging --no-apex
```

**Staging Only**
```bash
/usr/local/bin/generate-site.sh --site-name "$SITE_NAME" --domain "$DOMAIN" --github-repo $GITHUB_REPO --sub-domain staging --no-apex
```

#### Options
```bash
--site-name # Mandatory (E.g. mysite)
--domain # Mandatory (E.g. example.com)
--sub-domain www staging test # Add multiple sub-domains, no quotes
--sub-domain "${SUBDOMAINS[@]}" # Uses array (E.g. SUBDOMAINS=("www" "staging" "test"))
--no-apex # Skips apex domain
--webhook-secret # Provide webhook secret, otherwise it will generate one
--github-repo # Specify the GitHub repo (E.g. /user/mysite)
--skip-webhook # Skips webhook configuration (useful if you are updating an existing site)
```

**Note**: Be sure to save the output, especially `Webhook secret` unless you provided one directly with `--webhook-secret`.


### Initialize Site (Git Clone)
```bash
/usr/local/bin/initialize-$SITE_NAME.sh
```

The site should now be online, and Traefik will attempt to obtain certificates for each sub-domain and apex (if applicable) from LetsEncrypt.

### GitHub Webhook Setup
1. Go to your GitHub repository: https://github.com/username/repo/settings/hooks
   - Payload URL: `https://hooks.example.com/hooks/jekyll-sitename`
   - Content type: `application/json`
   - Secret: `123456789` (Get this from `generate-site.sh` output)
   - Events: "Just the push event"
2. Add webhook

**Monitor webhook**:
```bash
tail -f /var/log/webhook_$SITE_NAME.log
```

**Each site should have a `-hooks` entry in `webhook.service`**:
```bash
cat /etc/systemd/system/webhook.service
```

**Each site has it's own webhook JSON**:
```bash
cat /etc/webhooks/$SITE_NAME-webhook.json
```

**Restart WebHook Service**:
```bash
sudo systemctl daemon-reload
sudo systemctl restart webhook
```

The generate-site.sh script should have restarted the service.

## CloudFlare Rules
Cloudflare is a pain, and if you turn on proxying (orange cloud) then it'll break Webhooks and LetsEncrypt unless you add exception rules as follows:

## LetsEncrypt ACME Challenge
### Step 1: Create a Configuration Rule
1. Log into your Cloudflare account
2. Select your domain (sourcepotential.org)
3. Click on "Rules" in the left sidebar > Overview
4. Click on "Create Rule" and choose "Configuration Rules"
5. Click "Create rule"
6. Enter these settings:
    - Rule name: "ACME Challenge"
    - Field: URI Path
    - Operator: Starts With
    - Value: `/.well-known/acme-challenge/`
    - Expression: `starts_with(http.request.uri.path, "/.well-known/acme-challenge/")`
    - Then adjust these settings:
        - Automatic HTTPS Rewrites: Off
        - Browser Integrity Check: Off
        - Opportunistic Encryption: Off
        - Security Level: Essentially Off
        - SSL: Off
7. Click "Deploy"

### Step 2: Create a Cache Rule
1. In the left sidebar, click on "Caching"
2. Click on "Cache Rules"
3. Click "Create rule"
4. Enter these settings:
    - Rule name: "ACME Challenge"
    - Field: URI Path
    - Operator: Starts With
    - Value: `/.well-known/acme-challenge/`
    - Expression: `starts_with(http.request.uri.path, "/.well-known/acme-challenge/")`
    - Cache eligibility: Bypass cache
5. Click "Deploy"

# Maintenance

## HashiCorp Vault
Remember to unseal the Vault after server reboots!

**Run 3 times with different keys**
```bash
vault operator unseal  
```
**Check Vault Status**
```bash
vault status
```

**List all sites stored in vault**
```bash
vault kv list sites/
```

**List vault entry for /sites/mysite**
```bash
vault kv get sites/mysite
```

## SSL Certificates

**Check Traefik Logs**
```bash
cd ~/docker-sites/traefik
docker-compose logs -f | grep certificate
```

**Check certificate status in acme.json:**
```bash
docker-compose exec traefik cat /etc/traefik/acme/acme.json | jq .
```

## WebHooks & Jekyll Builds
**Webhook Build Log**
```bash
tail -f /var/log/webhook_$SITE_NAME.log
```

**Trigger a manual build:**
```bash
cd ~/docker-sites/$SITE_NAME
docker-compose run --rm build
```

**Check versions**
```bash
cd ~/docker-sites/$SITE_NAME
docker-compose run --rm build ruby -v
docker-compose run --rm build bundle list | grep liquid
docker-compose run --rm build bundle list | grep jekyll
```

## Site Deployment
**Assign Site Variables**
```bash
export SITE_NAME=mysite
export DOMAIN=mysite.com
export GITHUB_REPO=user/mysite
```

Optionally you can set a manual webhook secret:
```bash
export WEBHOOK_SECRET=123456789
```

 **Create GitHub Personal Access Token:**
 1. Go to https://github.com/settings/tokens?type=beta
 2. Generate new token with access to the correct site repo
 3. Copy token value

**Start / Restart Site**
```bash
/usr/local/bin/restart-site.sh --site-name $SITE_NAME
```

**Deleting a Site**
```bash
/usr/local/bin/delete-site.sh --site-name $SITE_NAME
```

## Webhook Domain Configuration
All webhooks require a dedicated domain for receiving GitHub webhook events. You must set this using the `WEBHOOK_DOMAIN` environment variable before running any scripts. This domain will be used for all webhook traffic.

### Setting Up Your Webhook Domain

1. Choose a subdomain to use for webhooks (e.g., `hooks.example.com`)
2. Set up DNS for this subdomain to point to your server
3. Export the environment variable:
   ```bash
   export WEBHOOK_DOMAIN="hooks.example.com"
   ```
4. For persistence, add it to your `.bashrc` file:
   ```bash
   echo 'export WEBHOOK_DOMAIN="hooks.yourdomain.com"' >> ~/.bashrc
   source ~/.bashrc
   ```

**Note**: Ensure your webhook domain is configured in Traefik and that SSL certificates are properly obtained

Remember that all sites will use this same webhook domain with different paths. For example, if your webhook domain is `hooks.example.com`, GitHub webhooks would be configured as:
- `https://hooks.example.com/hooks/jekyll-site1`
- `https://hooks.example.com/hooks/jekyll-site2`
- and so on...

This domain will be set in the webhook proxy configuration: `~/docker-sites/webhook/docker-compose.yml`.

# Congratulations!

You've successfully set up your own Jekyll hosting platform with:
- ✅ Automated builds triggered by Git pushes
- ✅ Secure HTTPS certificates via Let's Encrypt
- ✅ Docker containerization for isolation and repeatability
- ✅ Traefik for efficient reverse proxying
- ✅ HashiCorp Vault for secrets management
- ✅ Multi-site support on a single server

Your self-hosted solution gives you complete control over your Jekyll sites while maintaining the convenience of platforms like Netlify or GitHub Pages. You can now easily deploy, update, and manage multiple sites from a single server.

Happy deploying!