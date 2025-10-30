#!/bin/bash

set -e  # Exit on any error

echo "Starting Docker and Docker Compose installation..."

# Update package index and install prerequisites
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

# Add Docker's official GPG key
echo "Adding Docker's official GPG key..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add the Docker repository
echo "Adding Docker repository..."
echo \
  "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package index again with Docker repository
sudo apt-get update

# Install Docker
echo "Installing Docker..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# Try to start and enable Docker service, but continue if it fails
echo "Attempting to start Docker service..."
if sudo systemctl enable docker 2>/dev/null; then
    echo "Docker service enabled"
else
    echo "Warning: Could not enable Docker via systemctl (may be running in container)"
fi

if sudo systemctl start docker 2>/dev/null; then
    echo "Docker service started"
else
    echo "Warning: Could not start Docker via systemctl (may be running in container)"
    echo "Trying alternative method..."
    
    # Alternative: Start dockerd manually in background for current session
    if command -v dockerd >/dev/null 2>&1; then
        echo "Starting dockerd manually..."
        sudo nohup dockerd > /var/log/dockerd.log 2>&1 &
        sleep 5
    fi
fi

# Add current user to docker group
sudo usermod -aG docker $USER

# Install Docker Compose Plugin
echo "Installing Docker Compose plugin..."
sudo apt-get install -y docker-compose-plugin

# Verify Docker is accessible
echo "Verifying Docker accessibility..."
if docker info >/dev/null 2>&1; then
    echo "Docker is accessible"
else
    echo "Warning: Docker daemon may not be running. Trying to start..."
    # One more attempt to start Docker
    sudo systemctl start docker 2>/dev/null || sudo dockerd > /dev/null 2>&1 &
    sleep 3
fi

# Verify installations
echo "Verifying installations..."
docker --version

echo "Verifying Docker Compose installation..."
docker compose version

# Check if Docker daemon is actually running
if ! docker info >/dev/null 2>&1; then
    echo ""
    echo "================================================"
    echo "WARNING: Docker daemon may not be running!"
    echo "Docker Compose is installed, but Docker daemon needs to be started."
    echo ""
    echo "You can try:"
    echo "  sudo systemctl start docker"
    echo "  OR"
    echo "  sudo dockerd &"
    echo ""
else
    echo ""
    echo "================================================"
    echo "Installation completed successfully!"
fi

echo ""
echo "Docker Compose is installed as: docker compose"
echo "Version: $(docker compose version)"
echo ""
echo "Examples:"
echo "  docker compose version"
echo "  docker compose up"
echo "  docker compose down"
echo ""
echo "Note: You need to log out and log back in"
echo "      to use Docker commands without sudo."
echo "================================================"
