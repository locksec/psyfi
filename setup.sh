#!/bin/bash
# PsyFi Setup Script
# This script automates the setup of PsyFi after the basic server installation
# PLEASE REFER TO THE README!

# Script version
SCRIPT_VERSION="1.1.0"

# Initialize flags
UPDATE_MODE=false
FORCE_MODE=false
LOG_DIR="$HOME/.psyfi/logs"
LOG_FILE="$LOG_DIR/setup_$(date +%Y%m%d_%H%M%S).log"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print section headers
print_header() {
    local message="$1"
    echo -e "\n${GREEN}==== $message ====${NC}\n"
    log_message "HEADER: $message"
}

# Function to print status messages
print_status() {
    local message="$1"
    echo -e "${YELLOW}$message${NC}"
    log_message "STATUS: $message"
}

# Function to print info messages
print_info() {
    local message="$1"
    echo -e "${BLUE}$message${NC}"
    log_message "INFO: $message"
}

# Function to print error messages and exit
print_error() {
    local message="$1"
    echo -e "${RED}ERROR: $message${NC}"
    log_message "ERROR: $message"
    exit 1
}

# Function to check if command succeeded
check_success() {
    if [ $? -ne 0 ]; then
        print_error "$1"
    fi
}

# Function to log messages to file
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Function to ask for confirmation
confirm() {
    local prompt="$1"
    local default="$2"
    
    if [ "$UPDATE_MODE" = true ]; then
        # In update mode, follow the default without asking
        [ "$default" = "y" ] && return 0 || return 1
    fi
    
    if [ "$FORCE_MODE" = true ]; then
        # In force mode, always proceed
        return 0
    fi
    
    local default_prompt
    if [ "$default" = "y" ]; then
        default_prompt="Y/n"
    else
        default_prompt="y/N"
    fi
    
    read -p "$prompt [$default_prompt]: " response
    response=${response:-$default}
    
    case "$response" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# Function to check if a package is installed
is_package_installed() {
    local package_name="$1"
    dpkg -l | grep -q "ii  $package_name "
    return $?
}

# Function to check if a service is enabled
is_service_enabled() {
    local service_name="$1"
    systemctl is-enabled --quiet "$service_name" 2>/dev/null
    return $?
}

# Function to check if a directory exists
does_directory_exist() {
    local dir_path="$1"
    [ -d "$dir_path" ]
    return $?
}

# Function to apply template (from generate-site.sh)
apply_template() {
    local template="$1"
    local output="$2"
    local vars="${@:3}"  # All additional arguments are variable replacements
    
    # Read template file
    local content
    if [ -f "$template" ]; then
        content=$(cat "$template")
    else
        print_error "Template file not found: $template"
    fi
    
    # Process variable replacements if provided
    if [ -n "$vars" ]; then
        for var in $vars; do
            local key="${var%%=*}"
            local value="${var#*=}"
            content="${content//\{\{$key\}\}/$value}"
        done
    fi
    
    # Check if output file exists and confirm overwrite if not in update mode
    if [ -f "$output" ] && ! confirm "File $output already exists. Overwrite?" "n"; then
        print_info "Skipping file: $output"
        return 0
    fi
    
    # Use sudo only if necessary (if output path requires it)
    if [[ "$output" == /etc/* || "$output" == /usr/* ]]; then
        echo "$content" | sudo tee "$output" > /dev/null
    else
        echo "$content" > "$output"
    fi
    
    print_info "Generated: $output"
    log_message "Generated file: $output"
    return 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --update)
            UPDATE_MODE=true
            print_info "Running in UPDATE mode (only updating scripts and templates)"
            shift
            ;;
        --force)
            FORCE_MODE=true
            print_info "Running in FORCE mode (overwriting all files without confirmation)"
            shift
            ;;
        --log-dir)
            LOG_DIR="$2"
            LOG_FILE="$LOG_DIR/setup_$(date +%Y%m%d_%H%M%S).log"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --update     Only update scripts and templates, skip installations"
            echo "  --force      Force installation/overwrite without prompts"
            echo "  --log-dir DIR Specify log directory (default: ~/.psyfi/logs)"
            echo "  --help       Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            ;;
    esac
done

# Create log directory and initialize log file
mkdir -p "$LOG_DIR"
echo "PsyFi Setup Log - Version $SCRIPT_VERSION - $(date)" > "$LOG_FILE"
log_message "Script started with arguments: $@"
log_message "UPDATE_MODE=$UPDATE_MODE, FORCE_MODE=$FORCE_MODE"

# Check if script is run as the correct user (not root)
if [ "$(id -u)" -eq 0 ]; then
    print_error "This script should NOT be run as root. Please run as your regular user with sudo privileges."
fi

# Function to install a package if not already installed
install_package() {
    local package="$1"
    
    if [ "$UPDATE_MODE" = true ]; then
        print_info "Skipping package installation in update mode: $package"
        return 0
    fi
    
    if is_package_installed "$package"; then
        print_info "Package already installed: $package"
        return 0
    fi
    
    print_status "Installing package: $package"
    sudo apt install -y "$package"
    check_success "Failed to install package: $package"
    print_info "Successfully installed: $package"
}

# Function to setup directories
setup_directory() {
    local dir_path="$1"
    local owner="${2:-$USER:$USER}"
    local perms="${3:-755}"
    
    if does_directory_exist "$dir_path"; then
        print_info "Directory already exists: $dir_path"
    else
        print_status "Creating directory: $dir_path"
        if [[ "$dir_path" == /etc/* || "$dir_path" == /var/* || "$dir_path" == /usr/* ]]; then
            sudo mkdir -p "$dir_path"
            sudo chown "$owner" "$dir_path"
            sudo chmod "$perms" "$dir_path"
        else
            mkdir -p "$dir_path"
            chown "$owner" "$dir_path"
            chmod "$perms" "$dir_path"
        fi
        check_success "Failed to create directory: $dir_path"
    fi
}

# Function to setup a service
setup_service() {
    local service_name="$1"
    
    if [ "$UPDATE_MODE" = true ]; then
        print_info "Skipping service setup in update mode: $service_name"
        return 0
    fi
    
    if is_service_enabled "$service_name"; then
        print_info "Service already enabled: $service_name"
    else
        print_status "Enabling service: $service_name"
        sudo systemctl enable "$service_name"
        check_success "Failed to enable service: $service_name"
    fi
    
    print_status "Starting service: $service_name"
    sudo systemctl start "$service_name"
    check_success "Failed to start service: $service_name"
}

# Install packages
if [ "$UPDATE_MODE" = false ]; then
    print_header "Checking and Installing Required Packages"
    
    print_status "Updating system package lists..."
    sudo apt update
    check_success "Failed to update system package lists"
    
    if confirm "Do you want to upgrade system packages?" "n"; then
        print_status "Upgrading system packages..."
        sudo apt upgrade -y
        check_success "Failed to upgrade system packages"
    fi
    
    print_status "Checking core packages..."
    
    CORE_PACKAGES=("apt-transport-https" "ca-certificates" "curl" "software-properties-common" "net-tools" "webhook")
    for pkg in "${CORE_PACKAGES[@]}"; do
        install_package "$pkg"
    done
    
    # HashiCorp Vault setup
    if ! is_package_installed "vault"; then
        print_status "Installing HashiCorp Vault..."
        
        # Update package sources if needed
        if confirm "Update package sources to use archive.ubuntu.com instead of mirrors.digitalocean.com?" "y"; then
            sudo sed -i 's/mirrors.digitalocean.com/archive.ubuntu.com/g' /etc/apt/sources.list
            sudo apt update
            check_success "Failed to update package sources"
        fi
        
        # Install Vault
        print_status "Adding HashiCorp repository..."
        curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt update && sudo apt install -y vault
        check_success "Failed to install HashiCorp Vault"
    else
        print_info "HashiCorp Vault already installed"
    fi
    
    # Docker setup
    if ! is_package_installed "docker-ce"; then
        print_status "Installing Docker..."
        
        # Add Docker repository
        print_status "Adding Docker repository..."
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        check_success "Failed to add Docker repository"
        
        # Install Docker packages
        sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io
        check_success "Failed to install Docker"
        
        # Install docker-compose
        if [ ! -f "/usr/local/bin/docker-compose" ]; then
            print_status "Installing docker-compose..."
            sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
            check_success "Failed to install docker-compose"
        else
            print_info "docker-compose already installed"
        fi
        
        # Enable Docker service
        print_status "Enabling Docker service..."
        sudo systemctl enable docker
        check_success "Failed to enable Docker service"
        
        # Add user to docker group
        if ! groups $USER | grep -q "docker"; then
            print_status "Adding user to docker group..."
            sudo usermod -aG docker $USER
            check_success "Failed to add user to docker group"
            print_info "NOTE: You will need to log out and log back in for docker group membership to take effect"
        else
            print_info "User already in docker group"
        fi
    else
        print_info "Docker already installed"
    fi
fi

# Configure HashiCorp Vault
if [ "$UPDATE_MODE" = false ]; then
    print_header "Configuring HashiCorp Vault"
    
    # Create Vault configuration directory if needed
    setup_directory "/etc/vault.d" "root:root" "755"
    
    # Create Vault data directory
    setup_directory "/opt/vault/data" "root:root" "755"
    
    # Create or update Vault configuration file
    VAULT_CONF_TEMPLATE="/tmp/vault_config_template.hcl"
    cat > "$VAULT_CONF_TEMPLATE" << 'EOF'
storage "file" {
  path = "/opt/vault/data"
}

listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_disable = 1
}

api_addr = "http://127.0.0.1:8200"
EOF
    
    apply_template "$VAULT_CONF_TEMPLATE" "/etc/vault.d/vault.hcl"
    sudo chmod 640 "/etc/vault.d/vault.hcl"
    rm "$VAULT_CONF_TEMPLATE"
    
    # Setup Vault service if not already enabled
    if ! is_service_enabled "vault"; then
        print_status "Setting up Vault service..."
        setup_service "vault"
    else
        print_info "Vault service already enabled"
    fi
fi

# Ensure ADMIN_EMAIL is set
if [ -z "$ADMIN_EMAIL" ] && [ "$UPDATE_MODE" = false ]; then
    read -p "Enter admin email for Let's Encrypt: " ADMIN_EMAIL
    if [ -z "$ADMIN_EMAIL" ]; then
        print_error "Admin email is required for Let's Encrypt. Please set it with export ADMIN_EMAIL=your@email.com"
    fi
    log_message "ADMIN_EMAIL set to: $ADMIN_EMAIL"
fi

# Setup directory structure
print_header "Setting up PsyFi Directory Structure"

# Create required directories if they don't exist
if [ "$UPDATE_MODE" = false ]; then
    print_status "Creating directory structure..."
    setup_directory "$HOME/docker-sites/templates"
    setup_directory "$HOME/docker-sites/traefik/config"
    setup_directory "$HOME/docker-sites/traefik/data"
    
    # Ensure proper ownership of the docker-sites directory tree
    print_status "Setting ownership for docker-sites directory..."
    chown -R $USER:$USER "$HOME/docker-sites"
fi

# Copy or update template files
print_header "Updating Template Files"

print_status "Updating site initialization template..."
initialize_site_template="./templates/initialize-site-template.sh"
if [ -f "$initialize_site_template" ]; then
    apply_template "$initialize_site_template" "$HOME/docker-sites/templates/initialize-site-template.sh"
    chmod 644 "$HOME/docker-sites/templates/initialize-site-template.sh"
else
    print_error "Template file not found: $initialize_site_template"
fi

# Setup Traefik configuration
print_header "Setting up Traefik Configuration"

# Update Traefik configuration
traefik_yml_template="./templates/traefik.yml"
if [ -f "$traefik_yml_template" ]; then
    # We need to substitute ADMIN_EMAIL manually here
    traefik_output="$HOME/docker-sites/traefik/config/traefik.yml"
    
    if [ -f "$traefik_output" ] && [ "$UPDATE_MODE" = false ] && ! confirm "Traefik config already exists. Overwrite?" "n"; then
        print_info "Skipping Traefik configuration update"
    else
        print_status "Updating Traefik configuration..."
        cat "$traefik_yml_template" | ADMIN_EMAIL="$ADMIN_EMAIL" envsubst > "$traefik_output"
        check_success "Failed to create Traefik configuration"
    fi
else
    print_info "Traefik template not found, using embedded template"
    TRAEFIK_TEMPLATE="/tmp/traefik_template.yml"
    cat > "$TRAEFIK_TEMPLATE" << 'EOF'
api:
  dashboard: true
  insecure: false

entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

certificatesResolvers:
  default:
    acme:
      email: "{{ADMIN_EMAIL}}"
      storage: /etc/traefik/acme/acme.json
      httpChallenge:
        entryPoint: web

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: traefik-public

log:
  level: DEBUG
  format: json
EOF
    apply_template "$TRAEFIK_TEMPLATE" "$HOME/docker-sites/traefik/config/traefik.yml" "ADMIN_EMAIL=$ADMIN_EMAIL"
    rm "$TRAEFIK_TEMPLATE"
fi

# Create acme.json if it doesn't exist
acme_json="$HOME/docker-sites/traefik/data/acme.json"
if [ ! -f "$acme_json" ]; then
    print_status "Creating acme.json for certificates..."
    touch "$acme_json"
    chmod 600 "$acme_json"
    check_success "Failed to set up acme.json"
else
    print_info "acme.json already exists"
fi

# Create or update Traefik docker-compose.yml
TRAEFIK_COMPOSE_TEMPLATE="/tmp/traefik_compose_template.yml"
cat > "$TRAEFIK_COMPOSE_TEMPLATE" << 'EOF'
services:
  traefik:
    image: traefik:v3.3.4
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./config/traefik.yml:/etc/traefik/traefik.yml:ro
      - ./data/acme.json:/etc/traefik/acme/acme.json
    networks:
      - traefik-public

networks:
  traefik-public:
    external: true
EOF

apply_template "$TRAEFIK_COMPOSE_TEMPLATE" "$HOME/docker-sites/traefik/docker-compose.yml"
rm "$TRAEFIK_COMPOSE_TEMPLATE"

# Copy/update utility scripts
print_header "Installing Utility Scripts"
print_status "Updating scripts in /usr/local/bin..."

for script in "./scripts/generate-site.sh" "./scripts/delete-site.sh" "./scripts/restart-site.sh"; do
    if [ -f "$script" ]; then
        script_name=$(basename "$script")
        target="/usr/local/bin/$script_name"
        
        if sudo [ -f "$target" ] && [ "$UPDATE_MODE" = false ] && ! confirm "Script $target already exists. Update it?" "y"; then
            print_info "Skipping update of $target"
        else
            print_status "Updating $target..."
            sudo cp "$script" "$target"
            sudo chmod +x "$target"
            sudo chown "$USER:$USER" "$target"
            check_success "Failed to update $target"
        fi
    else
        print_info "Script file not found: $script"
    fi
done

# Set up webhook configuration
if [ "$UPDATE_MODE" = false ]; then
    print_header "Setting up Webhook Configuration"
    
    # Set up webhook log directory with proper permissions
    print_status "Setting up webhook log directory..."
    setup_directory "/var/log/webhooks" "$USER:$USER" "755"
    
    if [ ! -f "/var/log/webhooks/webhook.log" ]; then
        sudo touch "/var/log/webhooks/webhook.log"
        sudo chown "$USER:$USER" "/var/log/webhooks/webhook.log"
        sudo chmod 644 "/var/log/webhooks/webhook.log"
        check_success "Failed to set up webhook log file"
    fi
    
    # Create webhooks directory if it doesn't exist
    print_status "Setting up webhooks directory..."
    setup_directory "/etc/webhooks" "$USER:$USER" "755"
    
    # Set up webhook proxy configuration
    print_status "Setting up webhook proxy configuration..."
    setup_directory "$HOME/docker-sites/webhook/nginx"
    
    # Create nginx config for webhook proxy
    WEBHOOK_NGINX_TEMPLATE="/tmp/webhook_nginx_template.conf"
    cat > "$WEBHOOK_NGINX_TEMPLATE" << 'EOF'
server {
    listen 80;
    
    location / {
        proxy_pass http://172.18.0.1:9000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Original-URI $request_uri;
    }
}
EOF
    
    apply_template "$WEBHOOK_NGINX_TEMPLATE" "$HOME/docker-sites/webhook/nginx/nginx.conf"
    rm "$WEBHOOK_NGINX_TEMPLATE"
    
    # Create docker-compose.yml for webhook proxy
    WEBHOOK_COMPOSE_TEMPLATE="/tmp/webhook_compose_template.yml"
    cat > "$WEBHOOK_COMPOSE_TEMPLATE" << 'EOF'
services:
  webhook:
    image: nginx:alpine
    container_name: webhook-service
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    labels:
      - "traefik.enable=true"
      
      # ACME Challenge Router (NO REDIRECTION)
      - "traefik.http.routers.webhook-acme.rule=Host(`hooks.psysecure.com`) && PathPrefix(`/.well-known/acme-challenge/`)"
      - "traefik.http.routers.webhook-acme.entrypoints=web"
      - "traefik.http.routers.webhook-acme.tls=false"
      
      # Main webhook router
      - "traefik.http.routers.webhook.rule=Host(`hooks.psysecure.com`)"
      - "traefik.http.routers.webhook.entrypoints=websecure"
      - "traefik.http.routers.webhook.tls=true"
      - "traefik.http.routers.webhook.tls.certresolver=default"
      - "traefik.http.services.webhook.loadbalancer.server.port=80"
      
      # Redirect HTTP to HTTPS
      - "traefik.http.routers.webhook-redirect.rule=Host(`hooks.psysecure.com`)"
      - "traefik.http.routers.webhook-redirect.entrypoints=web"
      - "traefik.http.routers.webhook-redirect.middlewares=webhook-https-redirect"
      - "traefik.http.middlewares.webhook-https-redirect.redirectscheme.scheme=https"
    networks:
      - traefik-public
    restart: always

networks:
  traefik-public:
    external: true
EOF
    
    apply_template "$WEBHOOK_COMPOSE_TEMPLATE" "$HOME/docker-sites/webhook/docker-compose.yml"
    rm "$WEBHOOK_COMPOSE_TEMPLATE"
fi

print_header "Setup Complete!"
if [ "$UPDATE_MODE" = true ]; then
    echo -e "${GREEN}PsyFi scripts and templates have been updated successfully!${NC}"
else
    echo -e "${GREEN}The PsyFi environment has been set up successfully!${NC}"
    echo ""
    echo -e "${YELLOW}IMPORTANT: You need to log out and log back in for docker group permissions to take effect.${NC}"
    echo -e "${YELLOW}After logging back in, continue with HashiCorp Vault Initialization in the README.${NC}"
fi

print_info "Setup log saved to: $LOG_FILE"
log_message "Script completed successfully"
echo ""