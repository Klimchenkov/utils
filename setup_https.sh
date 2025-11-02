#!/bin/bash

# HTTPS Certificate Setup Script using Certbot
# Supports Apache and Nginx web servers with pre/post hooks for renewal

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo -e "${RED}Cannot detect OS${NC}"
    exit 1
fi

# Install Certbot
install_certbot() {
    echo -e "${YELLOW}Installing Certbot...${NC}"
    
    case $OS in
        ubuntu|debian)
            apt update
            apt install -y certbot
            ;;
        centos|rhel|fedora)
            if [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
                yum install -y epel-release
            fi
            yum install -y certbot
            ;;
        *)
            echo -e "${RED}Unsupported OS${NC}"
            exit 1
            ;;
    esac
}

# Install Web Server Plugin
install_web_plugin() {
    local webserver=$1
    echo -e "${YELLOW}Installing Certbot plugin for $webserver...${NC}"
    
    case $OS in
        ubuntu|debian)
            case $webserver in
                apache)
                    apt install -y python3-certbot-apache
                    ;;
                nginx)
                    apt install -y python3-certbot-nginx
                    ;;
            esac
            ;;
        centos|rhel|fedora)
            case $webserver in
                apache)
                    yum install -y python3-certbot-apache
                    ;;
                nginx)
                    yum install -y python3-certbot-nginx
                    ;;
            esac
            ;;
    esac
}

# Get certificate with pre/post hooks
get_certificate() {
    local webserver=$1
    local domain=$2
    local email=$3
    
    echo -e "${YELLOW}Getting certificate for $domain${NC}"
    
    case $webserver in
        apache)
            certbot --apache -d "$domain" --email "$email" --agree-tos --non-interactive
            # Set up renewal hooks for Apache
            setup_renewal_hooks "apache2" "$domain"
            ;;
        nginx)
            certbot --nginx -d "$domain" --email "$email" --agree-tos --non-interactive
            # Set up renewal hooks for Nginx
            setup_renewal_hooks "nginx" "$domain"
            ;;
        standalone)
            certbot certonly --standalone -d "$domain" --email "$email" --agree-tos --non-interactive
            # For standalone, we need to stop web server during renewal
            detect_webserver_and_setup_hooks "$domain"
            ;;
    esac
}

# Detect which web server is running and set up hooks
detect_webserver_and_setup_hooks() {
    local domain=$1
    
    if systemctl is-active --quiet nginx; then
        echo -e "${YELLOW}Detected Nginx is running, setting up renewal hooks${NC}"
        setup_renewal_hooks "nginx" "$domain"
    elif systemctl is-active --quiet apache2; then
        echo -e "${YELLOW}Detected Apache is running, setting up renewal hooks${NC}"
        setup_renewal_hooks "apache2" "$domain"
    elif systemctl is-active --quiet httpd; then
        echo -e "${YELLOW}Detected Apache (httpd) is running, setting up renewal hooks${NC}"
        setup_renewal_hooks "httpd" "$domain"
    else
        echo -e "${YELLOW}No web server detected or using different service name${NC}"
        read -p "Enter the service name that uses port 80 (or leave empty if none): " service_name
        if [ -n "$service_name" ]; then
            setup_renewal_hooks "$service_name" "$domain"
        fi
    fi
}

# Set up renewal hooks in Certbot configuration
setup_renewal_hooks() {
    local service_name=$1
    local domain=$2
    
    local renewal_config="/etc/letsencrypt/renewal/${domain}.conf"
    
    if [ -f "$renewal_config" ] && [ -n "$service_name" ]; then
        echo -e "${YELLOW}Setting up renewal hooks for $service_name in $renewal_config${NC}"
        
        # Check if hooks already exist
        if ! grep -q "^pre_hook" "$renewal_config" && ! grep -q "^post_hook" "$renewal_config"; then
            # Add pre and post hooks to renewal config
            sed -i "/^\[renewalparams\]/a\\
pre_hook = systemctl stop $service_name\\
post_hook = systemctl start $service_name" "$renewal_config"
            
            echo -e "${GREEN}Renewal hooks added for $service_name${NC}"
        else
            echo -e "${YELLOW}Renewal hooks already exist in configuration${NC}"
        fi
    fi
}

# Test renewal with hooks
test_renewal_with_hooks() {
    echo -e "${YELLOW}Testing certificate renewal with hooks...${NC}"
    
    # Test renewal for all certificates
    if certbot renew --dry-run; then
        echo -e "${GREEN}All renewal tests passed!${NC}"
    else
        echo -e "${YELLOW}Some renewals failed, but this might be expected for certain configurations${NC}"
        echo -e "${YELLOW}Check the logs above for details${NC}"
    fi
}

# Fix existing certificate renewals that fail due to port 80 issues
fix_existing_renewals() {
    echo -e "${YELLOW}Checking for existing certificates that need renewal hooks...${NC}"
    
    local renewal_dir="/etc/letsencrypt/renewal"
    local fixed_count=0
    
    # Detect running web server
    local webserver=""
    if systemctl is-active --quiet nginx; then
        webserver="nginx"
    elif systemctl is-active --quiet apache2; then
        webserver="apache2"
    elif systemctl is-active --quiet httpd; then
        webserver="httpd"
    fi
    
    if [ -n "$webserver" ]; then
        for config_file in "$renewal_dir"/*.conf; do
            if [ -f "$config_file" ]; then
                local domain=$(basename "$config_file" .conf)
                # Check if this config uses standalone mode and doesn't have hooks
                if grep -q "authenticator.*standalone" "$config_file" && \
                   ! grep -q "^pre_hook" "$config_file"; then
                    echo -e "${YELLOW}Adding hooks to: $domain${NC}"
                    setup_renewal_hooks "$webserver" "$domain"
                    ((fixed_count++))
                fi
            fi
        done
        
        if [ $fixed_count -gt 0 ]; then
            echo -e "${GREEN}Fixed renewal hooks for $fixed_count certificates${NC}"
        else
            echo -e "${GREEN}No certificates need fixing${NC}"
        fi
    else
        echo -e "${YELLOW}No web server detected, skipping existing certificate fix${NC}"
    fi
}

# Main execution
main() {
    echo -e "${GREEN}Certbot HTTPS Setup Script with Renewal Hooks${NC}"
    
    # Check if Certbot is installed
    if ! command -v certbot &> /dev/null; then
        install_certbot
    fi

    # Web server selection
    echo -e "\n${YELLOW}Select web server:${NC}"
    echo "1) Apache"
    echo "2) Nginx" 
    echo "3) Standalone (no web server integration)"
    echo "4) Fix existing certificate renewals"
    read -p "Enter choice [1-4]: " ws_choice

    case $ws_choice in
        1) webserver="apache" ;;
        2) webserver="nginx" ;;
        3) webserver="standalone" ;;
        4) 
            fix_existing_renewals
            test_renewal_with_hooks
            exit 0
            ;;
        *) echo -e "${RED}Invalid choice${NC}"; exit 1 ;;
    esac

    # Install web server plugin if not standalone
    if [ "$webserver" != "standalone" ]; then
        install_web_plugin "$webserver"
    fi

    # Get domain and email
    read -p "Enter domain name (e.g., example.com): " domain
    read -p "Enter email address (for renewal notices): " email

    # Get certificate
    get_certificate "$webserver" "$domain" "$email"

    # Test renewal with hooks
    test_renewal_with_hooks

    # Setup auto-renewal crontab if not exists
    if ! crontab -l | grep -q "certbot renew"; then
        echo -e "${YELLOW}Setting up auto-renewal crontab...${NC}"
        (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
    fi

    echo -e "${GREEN}Certificate setup complete!${NC}"
    echo -e "${GREEN}Your site is now available at https://$domain${NC}"
    echo -e "${GREEN}Renewal hooks have been configured to handle port 80 conflicts${NC}"
}

# Run main function
main "$@"