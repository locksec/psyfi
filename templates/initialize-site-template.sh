#!/bin/bash
# Create directory and set ownership
sudo mkdir -p /var/www/{{SITE_NAME}}
sudo chown -R $USER:$USER /var/www/{{SITE_NAME}}

export VAULT_ADDR='http://127.0.0.1:8200'
GITHUB_TOKEN=$(vault kv get -field=github_token sites/{{SITE_NAME}})

if [ -z "$GITHUB_TOKEN" ]; then
    echo "ERROR: Failed to retrieve GitHub token from Vault"
    exit 1
fi

echo "Cloning repository..."
git clone https://${GITHUB_TOKEN}@github.com/{{GITHUB_REPO}} /var/www/{{SITE_NAME}}

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to clone repository. Please check the GitHub token and repository name."
    exit 1
fi

echo "Repository cloned successfully to /var/www/{{SITE_NAME}}"

# Initial Jekyll Build
echo "Performing initial Jekyll build..."
cd ~/docker-sites/{{SITE_NAME}}

# Build the container
if docker-compose build; then
    echo "Docker build successful!"
else
    BUILD_EXIT_CODE=$?
    echo "ERROR: Docker build failed with exit code ${BUILD_EXIT_CODE}"
    exit 1
fi

# Attempt to run the build
if docker-compose run --rm build; then
    echo "Jekyll build successful!"
else
    BUILD_EXIT_CODE=$?
    echo "ERROR: Jekyll build failed with exit code ${BUILD_EXIT_CODE}"
    echo "Build logs:"
    docker-compose logs build
    echo ""
    echo "Please fix the build issues before continuing."
    exit 1
fi

echo "Starting containers..."
docker-compose up -d

echo "Site initialization complete!"
echo "Site is now available and should be accessible via the configured domains"