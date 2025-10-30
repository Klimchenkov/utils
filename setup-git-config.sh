#!/bin/bash

echo "================================================"
echo "Git Configuration Setup"
echo "================================================"

# Get user input
read -p "Enter your full name (for Git commits): " user_name
read -p "Enter your email address (for Git commits): " user_email

# Set global Git configuration
echo ""
echo "Setting up Git global configuration..."
git config --global user.name "$user_name"
git config --global user.email "$user_email"

# Set some useful Git defaults
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global core.editor "nano"

# Display the configuration
echo ""
echo "Git configuration has been set:"
echo "----------------------------------------"
git config --global --list | grep -E "(user.name|user.email|init.defaultBranch)"
echo "----------------------------------------"

# Test the GitHub SSH connection
echo ""
echo "Testing GitHub SSH connection..."
ssh -T git@github.com

echo ""
echo "================================================"
echo "Git configuration completed successfully!"
echo "You can now commit and push to GitHub."
echo "================================================"
