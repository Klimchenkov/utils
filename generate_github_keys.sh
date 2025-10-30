#!/bin/bash

set -e  # Exit on any error

echo "================================================"
echo "GitHub SSH Key Generator"
echo "================================================"

# Default values
KEY_TYPE="ed25519"
KEY_COMMENT="github-$(date +%Y-%m-%d)"
KEY_PATH="$HOME/.ssh/id_ed25519_github"

# Check for existing GitHub key
if [ -f "$KEY_PATH" ]; then
    echo "Warning: GitHub key already exists at $KEY_PATH"
    read -p "Do you want to overwrite? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        exit 1
    fi
fi

# Get user input
echo ""
echo "Key generation settings:"
read -p "Enter your GitHub email address: " github_email
read -p "Enter key filename [default: $KEY_PATH]: " custom_key_path
read -p "Enter key type (ed25519/rsa) [default: $KEY_TYPE]: " key_type_input

# Use custom values if provided
if [ ! -z "$custom_key_path" ]; then
    KEY_PATH="$custom_key_path"
fi

if [ ! -z "$key_type_input" ]; then
    KEY_TYPE="$key_type_input"
fi

# Ensure .ssh directory exists
echo ""
echo "Creating .ssh directory if it doesn't exist..."
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Generate the SSH key
echo ""
echo "Generating SSH key..."
if [ "$KEY_TYPE" = "ed25519" ]; then
    ssh-keygen -t ed25519 -C "$github_email" -f "$KEY_PATH" -N ""
elif [ "$KEY_TYPE" = "rsa" ]; then
    ssh-keygen -t rsa -b 4096 -C "$github_email" -f "$KEY_PATH" -N ""
else
    echo "Error: Unsupported key type. Use 'ed25519' or 'rsa'."
    exit 1
fi

# Start SSH agent and add the key
echo ""
echo "Adding key to SSH agent..."
eval "$(ssh-agent -s)"
ssh-add "$KEY_PATH"

# Create/update SSH config
echo ""
echo "Updating SSH configuration..."
if [ ! -f ~/.ssh/config ]; then
    touch ~/.ssh/config
    chmod 600 ~/.ssh/config
fi

# Check if GitHub configuration already exists
if ! grep -q "github.com" ~/.ssh/config; then
    cat >> ~/.ssh/config <<EOF

# GitHub
Host github.com
    HostName github.com
    User git
    IdentityFile $KEY_PATH
    IdentitiesOnly yes
EOF
    echo "Added GitHub configuration to ~/.ssh/config"
else
    echo "GitHub configuration already exists in ~/.ssh/config"
fi

# Set proper permissions
chmod 600 ~/.ssh/config

# Display the public key
echo ""
echo "================================================"
echo "SSH Key generated successfully!"
echo "================================================"
echo ""
echo "Your public key is:"
echo "----------------------------------------"
cat "${KEY_PATH}.pub"
echo "----------------------------------------"
echo ""
echo "Next steps:"
echo "1. Copy the public key above"
echo "2. Go to https://github.com/settings/keys"
echo "3. Click 'New SSH key'"
echo "4. Paste your key and give it a title"
echo "5. Test the connection with: ssh -T git@github.com"
echo ""
echo "Key files:"
echo "  Private: $KEY_PATH"
echo "  Public:  ${KEY_PATH}.pub"
echo ""
echo "================================================"
