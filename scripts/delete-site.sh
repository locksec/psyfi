#!/bin/bash
# /usr/local/bin/delete-site.sh

# Initialize variables
SITE_NAME=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --site-name)
      SITE_NAME="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 --site-name <site_name>"
      exit 1
      ;;
  esac
done

# Validate required inputs
if [[ -z "$SITE_NAME" ]]; then
  echo "Error: --site-name is required"
  echo "Usage: $0 --site-name <site_name>"
  exit 1
fi

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

echo "Preparing to delete site: $SITE_NAME"

# Confirmation prompt
read -p "Are you sure you want to delete the site '$SITE_NAME'? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Operation cancelled."
  exit 0
fi

# Check if the site directories and files exist
if [ ! -d ~/docker-sites/$SITE_NAME ]; then
  echo "Warning: Site directory ~/docker-sites/$SITE_NAME does not exist"
fi

if [ ! -f /etc/webhooks/$SITE_NAME-webhook.json ]; then
  echo "Warning: Webhook configuration /etc/webhooks/$SITE_NAME-webhook.json does not exist"
fi

if [ ! -f /usr/local/bin/build-$SITE_NAME.sh ]; then
  echo "Warning: Build script /usr/local/bin/build-$SITE_NAME.sh does not exist"
fi

if [ ! -f /usr/local/bin/initialize-$SITE_NAME.sh ]; then
  echo "Warning: Initialize script /usr/local/bin/initialize-$SITE_NAME.sh does not exist"
fi

echo "Stopping and removing docker containers..."
if [ -d ~/docker-sites/$SITE_NAME ]; then
  # Stop any running containers for this site
  cd ~/docker-sites/$SITE_NAME && docker-compose down 2>/dev/null
  echo "Docker containers for $SITE_NAME stopped (if any were running)"
fi

# Stop and remove any running site containers
echo "Removing the site hook from webhook service..."
if [ -f /etc/systemd/system/webhook.service ]; then
  # Remove the hook line from the webhook service
  sudo sed -i "/\/etc\/webhooks\/$SITE_NAME-webhook.json/d" /etc/systemd/system/webhook.service
  echo "Reloading systemd and restarting webhook service..."
  sudo systemctl daemon-reload
  sudo systemctl restart webhook
fi

# Delete the webhook configuration
echo "Deleting webhook configuration..."
if [ -f /etc/webhooks/$SITE_NAME-webhook.json ]; then
  sudo rm /etc/webhooks/$SITE_NAME-webhook.json
fi

# Delete the build and initialize scripts
echo "Deleting build and initialize scripts..."
if [ -f /usr/local/bin/build-$SITE_NAME.sh ]; then
  sudo rm /usr/local/bin/build-$SITE_NAME.sh
fi

if [ -f /usr/local/bin/initialize-$SITE_NAME.sh ]; then
  sudo rm /usr/local/bin/initialize-$SITE_NAME.sh
fi

# Remove log file
echo "Deleting log file..."
if [ -f /var/log/webhook_$SITE_NAME.log ]; then
  sudo rm /var/log/webhook_$SITE_NAME.log
fi

# Delete the site directory
echo "Deleting site directory..."
if [ -d ~/docker-sites/$SITE_NAME ]; then
  rm -rf ~/docker-sites/$SITE_NAME
fi

# Ask about removing website content
read -p "Do you want to delete the website content at /var/www/$SITE_NAME? (y/n): " DELETE_CONTENT
if [[ "$DELETE_CONTENT" =~ ^[Yy]$ ]]; then
  echo "Deleting website content..."
  sudo rm -rf /var/www/$SITE_NAME
  echo "Website content deleted."
fi

# Optionally remove Vault entry
read -p "Do you want to delete the site's GitHub token from Vault? (y/n): " DELETE_VAULT
if [[ "$DELETE_VAULT" =~ ^[Yy]$ ]]; then
  echo "Deleting Vault entry..."
  export VAULT_ADDR='http://127.0.0.1:8200'
  vault kv delete sites/$SITE_NAME
  echo "Vault entry deleted."
fi

echo "Site $SITE_NAME has been deleted successfully."