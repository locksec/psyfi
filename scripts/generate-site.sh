#!/bin/bash
# /usr/local/bin/generate-site.sh

# Initialize variables
SITE_NAME=""
DOMAIN=""
GITHUB_REPO=""
SUBDOMAINS=()
INCLUDE_APEX=true
WEBHOOK_SECRET=""
SKIP_WEBHOOK=false

# Global webhook configuration - requires environment variable
if [ -z "$WEBHOOK_DOMAIN" ]; then
  echo "Error: WEBHOOK_DOMAIN environment variable must be set (e.g. export WEBHOOK_DOMAIN=hooks.example.com)"
  exit 1
fi

# Function to apply template
apply_template() {
    local template="$1"
    local output="$2"
    local content=$(cat "$template")
    
    # Replace template variables with actual values
    content="${content//\{\{SITE_NAME\}\}/$SITE_NAME}"
    content="${content//\{\{GITHUB_REPO\}\}/$GITHUB_REPO}"
    content="${content//\{\{DOMAIN\}\}/$DOMAIN}"
    content="${content//\{\{WEBHOOK_SECRET\}\}/$WEBHOOK_SECRET}"
    
    echo "$content" | sudo tee "$output" > /dev/null
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --site-name)
      SITE_NAME="$2"
      shift 2
      ;;
    --domain)
      DOMAIN="$2"
      shift 2
      ;;
    --github-repo)
      GITHUB_REPO="$2"
      shift 2
      ;;
    --webhook-secret)
      WEBHOOK_SECRET="$2"
      shift 2
      ;;
    --skip-webhook)
      SKIP_WEBHOOK=true
      shift
      ;;

    --sub-domain)
      shift
      while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
        SUBDOMAINS+=("$1")
        shift
      done
      ;;
    --no-apex)
      INCLUDE_APEX=false
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 --site-name <site_name> --domain <domain> --github-repo <repo> [--webhook-secret <secret>] [--skip-webhook] [--sub-domain sub1 sub2 ...] [--no-apex]"
      exit 1
      ;;
  esac
done

# Validate required inputs
if [[ -z "$SITE_NAME" || -z "$DOMAIN" || -z "$GITHUB_REPO" ]]; then
  echo "Error: --site-name, --domain, and --github-repo are required"
  echo "Usage: $0 --site-name <site_name> --domain <domain> --github-repo <repo> [--webhook-secret <secret>] [--skip-webhook] [--sub-domain sub1 sub2 ...] [--no-apex]"
  exit 1
fi

# Generate webhook secret if not provided and webhooks are not skipped
if [[ -z "$WEBHOOK_SECRET" && "$SKIP_WEBHOOK" == "false" ]]; then
  WEBHOOK_SECRET=$(openssl rand -hex 16)
  echo "Generated webhook secret: $WEBHOOK_SECRET"
fi

# Check for reserved site names
RESERVED_NAMES=("traefik" "vault" "webhook" "templates" "template")
for RESERVED in "${RESERVED_NAMES[@]}"; do
  if [[ "$SITE_NAME" == "$RESERVED" ]]; then
    echo "Error: '$SITE_NAME' is a reserved name and cannot be used as a site name"
    exit 1
  fi
done

# Validate site name for security (alphanumeric, dash, underscore only)
if ! [[ "$SITE_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "Error: Site name can only contain letters, numbers, dashes, and underscores"
  exit 1
fi

# Prevent path traversal and other shell tricks
if [[ "$SITE_NAME" == *"/"* || "$SITE_NAME" == *".."* || "$SITE_NAME" == *"*"* || 
      "$SITE_NAME" == *"&"* || "$SITE_NAME" == *";"* || "$SITE_NAME" == *"|"* ||
      "$SITE_NAME" == *">"* || "$SITE_NAME" == *"<"* || "$SITE_NAME" == *"\`"* ]]; then
  echo "Error: Site name contains invalid characters"
  exit 1
fi

# Check and create Traefik network if it doesn't exist
if ! docker network inspect traefik-public >/dev/null 2>&1; then
  echo "Creating Traefik network..."
  docker network create traefik-public
  if [ $? -ne 0 ]; then
    echo "Error: Failed to create Traefik network"
    exit 1
  fi
  echo "Traefik network created successfully"
else
  echo "Traefik network already exists"
fi

# Check if Traefik is running, if not start it
if ! docker ps | grep -q traefik; then
  echo "Traefik is not running. Attempting to start it..."
  if [ -d ~/docker-sites/traefik ]; then
    (cd ~/docker-sites/traefik && docker-compose up -d)
    if [ $? -ne 0 ]; then
      echo "Warning: Failed to start Traefik. Some functionality may not work correctly."
      echo "You may need to start it manually with: cd ~/docker-sites/traefik && docker-compose up -d"
    else
      echo "Traefik started successfully."
    fi
  else
    echo "Warning: Traefik directory not found at ~/docker-sites/traefik."
    echo "Traefik must be running for sites to work properly."
  fi
fi

# Check if webhook proxy is running, if not start it
if ! docker ps | grep -q webhook-service; then
  echo "Webhook proxy is not running. Attempting to start it..."
  if [ -d ~/docker-sites/webhook ]; then
    (cd ~/docker-sites/webhook && docker-compose up -d)
    if [ $? -ne 0 ]; then
      echo "Warning: Failed to start webhook proxy. Webhook functionality may not work correctly."
      echo "You may need to start it manually with: cd ~/docker-sites/webhook && docker-compose up -d"
    else
      echo "Webhook proxy started successfully."
    fi
  else
    echo "Warning: Webhook proxy directory not found at ~/docker-sites/webhook."
    echo "Webhooks may not be accessible without the proxy."
  fi
fi

# Validate domain format
if ! [[ "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
  echo "Error: Invalid domain format"
  exit 1
fi

# Validate GitHub repo format
if ! [[ "$GITHUB_REPO" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$ ]]; then
  echo "Error: Invalid GitHub repo format. Should be 'username/repo'"
  exit 1
fi

# Validate subdomains
for SUBDOMAIN in "${SUBDOMAINS[@]}"; do
  if ! [[ "$SUBDOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
    echo "Error: Invalid subdomain format: $SUBDOMAIN"
    exit 1
  fi
done

# Error check: must have either apex or at least one subdomain
if [[ "$INCLUDE_APEX" == "false" && ${#SUBDOMAINS[@]} -eq 0 ]]; then
  echo "Error: When using --no-apex, at least one subdomain must be specified with --sub-domain"
  exit 1
fi

# Create necessary directories
mkdir -p ~/docker-sites/$SITE_NAME
mkdir -p ~/docker-sites/$SITE_NAME/nginx
mkdir -p ~/docker-sites/$SITE_NAME/build

# Build Host rule
if [[ "$INCLUDE_APEX" == "true" ]]; then
  HOST_RULE="Host(\`$DOMAIN\`)"
  prefix=" || "
else
  HOST_RULE=""
  prefix=""
fi

# Add each subdomain to the rule
for SUBDOMAIN in "${SUBDOMAINS[@]}"; do
  HOST_RULE="${HOST_RULE}${prefix}Host(\`$SUBDOMAIN.$DOMAIN\`)"
  prefix=" || "
done

# Debug output
echo "Generating Docker Compose for $SITE_NAME"
echo "Domain: $DOMAIN"
echo "GitHub Repo: $GITHUB_REPO"
echo "Apex domain included: $INCLUDE_APEX"
echo "Subdomains: ${SUBDOMAINS[*]}"
echo "Host rule: $HOST_RULE"
if [[ "$SKIP_WEBHOOK" == "false" ]]; then
  echo "Webhook domain: $WEBHOOK_DOMAIN"
else
  echo "Webhooks: SKIPPED"
fi

# Start of docker-compose.yml content
docker_compose_content="services:
  web:
    image: nginx:alpine
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - /var/www/$SITE_NAME/_site:/usr/share/nginx/html:ro
    labels:
      - \"traefik.enable=true\"

      # ACME Challenge Router (NO REDIRECTION)
      - \"traefik.http.routers.$SITE_NAME-acme.rule=PathPrefix(\`/.well-known/acme-challenge/\`)\"
      - \"traefik.http.routers.$SITE_NAME-acme.entrypoints=web\"
      - \"traefik.http.routers.$SITE_NAME-acme.tls=false\"

      # Main router for all domains
      - \"traefik.http.routers.$SITE_NAME.rule=$HOST_RULE\"
      - \"traefik.http.routers.$SITE_NAME.entrypoints=websecure\"
      - \"traefik.http.routers.$SITE_NAME.tls=true\"
      - \"traefik.http.routers.$SITE_NAME.tls.certresolver=default\"
      - \"traefik.http.services.$SITE_NAME.loadbalancer.server.port=80\"

      # Redirect HTTP to HTTPS (except ACME)
      - \"traefik.http.routers.$SITE_NAME-redirect.rule=$HOST_RULE\"
      - \"traefik.http.routers.$SITE_NAME-redirect.entrypoints=web\"
      - \"traefik.http.routers.$SITE_NAME-redirect.middlewares=$SITE_NAME-https-redirect\"

      # Middleware for HTTP -> HTTPS redirection
      - \"traefik.http.middlewares.$SITE_NAME-https-redirect.redirectscheme.scheme=https\"
"

# Write the initial docker-compose.yml content
echo "$docker_compose_content" > ~/docker-sites/$SITE_NAME/docker-compose.yml

# Add www to apex redirect if apex is included and www is in subdomains
if [[ "$INCLUDE_APEX" == "true" && " ${SUBDOMAINS[*]} " == *" www "* ]]; then
  # First, add the middleware to the main HTTPS router
  sed -i "/traefik.http.services.$SITE_NAME.loadbalancer.server.port=80/a\\      # Apply the www->apex middleware to the HTTPS router\\n      - \"traefik.http.routers.$SITE_NAME.middlewares=$SITE_NAME-www-to-apex\"" ~/docker-sites/$SITE_NAME/docker-compose.yml
  
  # Then add the www-to-apex middleware configuration
  cat >> ~/docker-sites/$SITE_NAME/docker-compose.yml << EOF

      # Middleware for www -> apex redirect
      - "traefik.http.middlewares.$SITE_NAME-www-to-apex.redirectregex.regex=^https://www\\\\.$DOMAIN/(.*)"
      - "traefik.http.middlewares.$SITE_NAME-www-to-apex.redirectregex.replacement=https://$DOMAIN/\$\${1}"
EOF
fi

# Complete the docker-compose.yml file
cat >> ~/docker-sites/$SITE_NAME/docker-compose.yml << EOF
    networks:
      - traefik-public
    restart: always

  build:
    build:
      context: /var/www/$SITE_NAME
      dockerfile: /home/nux/docker-sites/$SITE_NAME/build/Dockerfile
    mem_limit: 512M
    volumes:
      - /var/www/$SITE_NAME:/site
    command: ["bundle", "exec", "jekyll", "build", "--source", "/site", "--destination", "/site/_site"]

networks:
  traefik-public:
    external: true
EOF

# Generate nginx.conf with optimizations - NO webhook path anymore!
nginx_conf="server {
    listen 80;
    root /usr/share/nginx/html;
    
    # Enable compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1000;
    gzip_proxied expired no-cache no-store private auth;
    gzip_types text/plain text/css application/json application/javascript application/x-javascript text/xml application/xml application/xml+rss text/javascript image/svg+xml;
    gzip_comp_level 6;
    
    # Add caching headers for static assets
    location ~* \\.(jpg|jpeg|png|gif|ico|css|js|svg)$ {
        expires 7d;
        add_header Cache-Control \"public, max-age=604800, immutable\";
    }
    
    location / {
        try_files \$uri \$uri/ \$uri.html =404;
        
        # Add cache headers for HTML
        add_header Cache-Control \"public, max-age=3600\";
    }

    error_page 404 /404.html;
    location = /404.html {
        internal;
    }
}
"

# Write the nginx.conf file
echo "$nginx_conf" > ~/docker-sites/$SITE_NAME/nginx/nginx.conf

# Generate Dockerfile (always overwrite) 
cat > ~/docker-sites/$SITE_NAME/build/Dockerfile << EOF
FROM ruby:3.2.3-alpine
RUN apk add --no-cache build-base gcc cmake git g++ musl-dev make
WORKDIR /site
COPY Gemfile Gemfile.lock ./
RUN gem install bundler && \\
    gem install sass-embedded -v "~> 1.69.5" && \\
    bundle config set --local force_ruby_platform true && \\
    bundle install
CMD ["jekyll", "build"]
EOF

# Skip webhook configuration if requested
if [[ "$SKIP_WEBHOOK" == "false" ]]; then
  # Create a modified webhook template for this site
  WEBHOOK_TEMPLATE="/tmp/$SITE_NAME-webhook-template.json"
  cat > $WEBHOOK_TEMPLATE << EOF
[
    {
        "id": "jekyll-$SITE_NAME",
        "execute-command": "/usr/local/bin/build-$SITE_NAME.sh",
        "command-working-directory": "/var/www/$SITE_NAME",
        "trigger-rule": {
            "match": {
                "type": "payload-hash-sha1",
                "secret": "{{WEBHOOK_SECRET}}",
                "parameter": {
                    "source": "header",
                    "name": "X-Hub-Signature"
                }
            }
        },
        "response-message": "Executing build script for $SITE_NAME",
        "pass-arguments-to-command": [
            {
                "source": "entire-payload"
            }
        ]
    }
]
EOF

  # Create webhooks directory if it doesn't exist
  sudo mkdir -p /etc/webhooks

  # Generate webhook configuration from customized template
  apply_template $WEBHOOK_TEMPLATE /etc/webhooks/$SITE_NAME-webhook.json
  rm $WEBHOOK_TEMPLATE

  # Setup Webhook logging and fix permissions
  sudo touch /var/log/webhook_$SITE_NAME.log
  sudo chown $USER:$USER /var/log/webhook_$SITE_NAME.log
  sudo chmod 644 /var/log/webhook_$SITE_NAME.log

  # Set proper permissions on webhook config file
  sudo chown $USER:$USER /etc/webhooks/$SITE_NAME-webhook.json
  sudo chmod 644 /etc/webhooks/$SITE_NAME-webhook.json

  # Generate updated build script template
  BUILD_TEMPLATE="/tmp/$SITE_NAME-build-template.sh"
  cat > $BUILD_TEMPLATE << 'EOF'
#!/bin/bash
LOG_FILE="/var/log/webhook_{{SITE_NAME}}.log"

# Get GitHub token from Vault
export VAULT_ADDR='http://127.0.0.1:8200'
GITHUB_TOKEN=$(vault kv get -field=github_token sites/{{SITE_NAME}})

log() {
   echo "$(date): $1" >> "$LOG_FILE"
}

get_branch() {
   BRANCH=$(echo $1 | jq -r '.ref // empty' | sed 's/^refs\/heads\///' || echo "")
   if [ -z "$BRANCH" ]; then
       BRANCH="master"
       log "No branch specified, defaulting to: $BRANCH"
   fi
   echo "$BRANCH"
}

log "Build script started"
log "Request headers: $HTTP_HOST $HTTP_X_ORIGINAL_URI"
cd /var/www/{{SITE_NAME}}
BRANCH=$(get_branch "$1")
log "Processing branch: $BRANCH"

REPO_URL="https://${GITHUB_TOKEN}@github.com/{{GITHUB_REPO}}"
if git ls-remote --exit-code --heads $REPO_URL $BRANCH >> "$LOG_FILE" 2>&1; then
   log "Branch $BRANCH exists on remote"
   if git fetch $REPO_URL $BRANCH >> "$LOG_FILE" 2>&1 && \
      git reset --hard FETCH_HEAD >> "$LOG_FILE" 2>&1; then
       log "Git sync successful"
   else
       log "Git sync failed"
       exit 1
   fi
else
   log "Branch $BRANCH does not exist on remote"
   exit 1
fi

log "Starting Jekyll build"
cd /home/nux/docker-sites/{{SITE_NAME}}

if docker-compose run --rm build >> "$LOG_FILE" 2>&1; then
   log "Jekyll build successful"
else
   log "Jekyll build failed"
   log "Build logs: $(docker-compose logs build 2>&1)"
   exit 1
fi

log "Build completed successfully"
EOF

  # Generate build script from template
  apply_template $BUILD_TEMPLATE /usr/local/bin/build-$SITE_NAME.sh
  rm $BUILD_TEMPLATE

  # Make build script executable
  sudo chmod +x /usr/local/bin/build-$SITE_NAME.sh
  sudo chown $USER:$USER /usr/local/bin/build-$SITE_NAME.sh

  # Check if webhook service exists
  if [ ! -f /etc/systemd/system/webhook.service ]; then
    echo "Creating new webhook service configuration..."
    # Create initial service file with first site
    cat << EOF | sudo tee /etc/systemd/system/webhook.service
[Unit]
Description=Webhook Server
After=network.target

[Service]
ExecStart=/usr/bin/webhook \\
  -hooks /etc/webhooks/$SITE_NAME-webhook.json \\
  -verbose -port 9000 \\
  -header-delimiter=: \\
  -pass-header-to-command=true
User=$USER
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable webhook
    sudo systemctl restart webhook
  else
    echo "Updating existing webhook service configuration..."
    # Check if this hook already exists in the file
    if ! sudo grep -q "/etc/webhooks/$SITE_NAME-webhook.json" /etc/systemd/system/webhook.service; then
      # Add the new hook line before "-verbose"
      sudo sed -i "/-verbose/i\\  -hooks /etc/webhooks/$SITE_NAME-webhook.json \\\\" /etc/systemd/system/webhook.service
      
      # Check if pass-header-to-command is already in the service config
      if ! sudo grep -q "\-pass-header-to-command=true" /etc/systemd/system/webhook.service; then
        sudo sed -i "/-verbose/a\\  -header-delimiter=: \\\\\\n  -pass-header-to-command=true" /etc/systemd/system/webhook.service
      fi
      
      echo "Added hook for $SITE_NAME to webhook service"
      sudo systemctl daemon-reload
      sudo systemctl restart webhook
    else
      echo "Hook for $SITE_NAME already exists in webhook service, skipping..."
      
      # Still check if pass-header-to-command is in the config
      if ! sudo grep -q "\-pass-header-to-command=true" /etc/systemd/system/webhook.service; then
        sudo sed -i "/-verbose/a\\  -header-delimiter=: \\\\\\n  -pass-header-to-command=true" /etc/systemd/system/webhook.service
        sudo systemctl daemon-reload
        sudo systemctl restart webhook
      fi
    fi
  fi
fi

# Generate site initialization script from template
apply_template ~/docker-sites/templates/initialize-site-template.sh /usr/local/bin/initialize-$SITE_NAME.sh

# Make site initialization script executable
sudo chmod +x /usr/local/bin/initialize-$SITE_NAME.sh
sudo chown $USER:$USER /usr/local/bin/initialize-$SITE_NAME.sh

# Output summary
echo "Docker Compose file generated at ~/docker-sites/$SITE_NAME/docker-compose.yml"
echo "NGINX configuration file generated at ~/docker-sites/$SITE_NAME/nginx/nginx.conf"
echo "Dockerfile generated at ~/docker-sites/$SITE_NAME/build/Dockerfile"
echo "Site initialization script generated at /usr/local/bin/initialize-$SITE_NAME.sh"

if [[ "$SKIP_WEBHOOK" == "false" ]]; then
  echo "Webhook configuration generated at /etc/webhooks/$SITE_NAME-webhook.json"
  echo "Build script generated at /usr/local/bin/build-$SITE_NAME.sh"
  echo "Webhook secret: $WEBHOOK_SECRET"
  echo ""
  # Updated URL format for dedicated webhook domain
  echo "GitHub webhook URL: https://$WEBHOOK_DOMAIN/hooks/jekyll-$SITE_NAME"
else
  echo "Webhook configuration SKIPPED as requested"
fi

echo ""
echo "To initialize the site, run:"
echo "/usr/local/bin/initialize-$SITE_NAME.sh"
echo ""
echo "Don't forget to add the GitHub token to Vault:"
echo "vault kv put sites/$SITE_NAME github_token=\"YOUR_GITHUB_TOKEN\""