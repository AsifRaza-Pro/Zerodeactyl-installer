#!/bin/bash

# Basic Configuration Variables
DOMAIN=""
MYSQL_ROOT_PASSWORD=""
MYSQL_PTERO_PASSWORD=""
PANEL_DB_NAME="pterodactyl"
PANEL_DB_USER="pterodactyluser"
SSL_OPTION=""
EMAIL=""
INSTALL_TYPE=""
OS_TYPE=$(lsb_release -si | tr '[:upper:]' '[:lower:]')

# Function to Check for Ubuntu and Nginx
check_requirements() {
    if [ "$OS_TYPE" != "ubuntu" ]; then
        echo "This script is only supported on Ubuntu. Exiting..."
        exit 1
    fi

    if ! command -v nginx &> /dev/null; then
        echo "Nginx is not installed. Please install Nginx before running this script. Exiting..."
        exit 1
    fi

    echo "All requirements met."
}

# Function to Install Dependencies
install_dependencies() {
    echo "Updating system and installing dependencies..."
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg mysql-server redis-server certbot python3-certbot-nginx \
        php8.1-cli php8.1-fpm php8.1-mbstring php8.1-xml php8.1-mysql php8.1-curl php8.1-zip unzip tar fail2ban
}

# Function to Set Up Firewall
setup_firewall() {
    echo "Configuring firewall to allow required ports..."
    if command -v ufw >/dev/null 2>&1; then
        echo "UFW is installed, configuring it..."
        sudo ufw allow 'Nginx Full'
        sudo ufw allow 8080   # Allow Wings port
        sudo ufw allow 22     # Allow SSH
        sudo ufw allow 25565   # Allow default game server port
        sudo ufw allow 25575   # Allow additional game server port
        sudo ufw allow 8081   # Allow additional port for Wings
        sudo ufw allow 2022   # Allow additional custom port
        sudo ufw enable
        echo "UFW configured and enabled."
    else
        echo "No supported firewall (ufw) found. Please install UFW for security."
    fi

    # Show ports to open on the router
    echo "Please ensure the following ports are open on your router for Pterodactyl functionality:"
    echo "HTTP Port: 80"
    echo "HTTPS Port: 443"
    echo "Wings Port: 8080"
    echo "Additional Port for Wings: 8081"
    echo "SSH Port: 22"
    echo "Game Server Port: 25565"
    echo "Additional Game Server Port: 25575"
    echo "Custom Port: 2020"
    echo "Additional Custom Port: 2022"
}

# Function to Configure Fail2ban
configure_fail2ban() {
    echo "Configuring Fail2ban for DDoS protection..."
    sudo tee /etc/fail2ban/jail.d/nginx.conf > /dev/null <<EOF
[nginx-http-auth]
enabled = true
port    = http,https
filter = nginx-http-auth
logpath = /var/log/nginx/error.log
maxretry = 5
bantime  = 3600

[nginx-badbots]
enabled = true
port = http,https
filter = nginx-badbots
logpath = /var/log/nginx/access.log
maxretry = 2
bantime  = 86400

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600
EOF

    # Restart Fail2ban to apply changes
    sudo systemctl restart fail2ban
    echo "Fail2ban configured and started."
}

# Function to Install Pterodactyl Panel
install_panel() {
    echo "Installing Pterodactyl Panel..."
    cd /var/www
    sudo mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz --strip-components=1
    sudo chmod -R 755 storage/* bootstrap/cache/

    # Install Composer Dependencies
    echo "Installing Composer dependencies..."
    curl -sS https://getcomposer.org/installer | php
    php composer.phar install --no-dev --optimize-autoloader

    # Generate application key
    cp .env.example .env
    php artisan key:generate --force

    # Configure environment variables for MySQL
    sed -i "s/DB_DATABASE=pterodactyl/DB_DATABASE=$PANEL_DB_NAME/g" .env
    sed -i "s/DB_USERNAME=pterodactyl/DB_USERNAME=$PANEL_DB_USER/g" .env
    sed -i "s/DB_PASSWORD=/DB_PASSWORD=$MYSQL_PTERO_PASSWORD/g" .env

    # Nginx configuration for Pterodactyl
    configure_nginx
}

# Function to Configure Nginx
configure_nginx() {
    echo "Configuring Nginx..."
    if [ "$SSL_OPTION" == "y" ]; then
        echo "Configuring Nginx for SSL..."
        sudo tee /etc/nginx/sites-available/$DOMAIN.conf > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    # Redirect HTTP to HTTPS
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    # SSL Certificates
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    root /var/www/pterodactyl/public;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

        # Enable Nginx config and obtain SSL
        sudo ln -s /etc/nginx/sites-available/$DOMAIN.conf /etc/nginx/sites-enabled/
        sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email $EMAIL
        sudo systemctl restart nginx
    else
        echo "Configuring Nginx without SSL..."
        sudo tee /etc/nginx/sites-available/$DOMAIN.conf > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    root /var/www/pterodactyl/public;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

        # Enable Nginx config
        sudo ln -s /etc/nginx/sites-available/$DOMAIN.conf /etc/nginx/sites-enabled/
        sudo systemctl restart nginx
    fi

    # Create systemd service for the Panel
    create_panel_service
}

# Function to Create Systemd Service for the Panel
create_panel_service() {
    echo "Creating systemd service for Pterodactyl Panel..."
    sudo tee /etc/systemd/system/pterodactyl-panel.service > /dev/null <<EOF
[Unit]
Description=Pterodactyl Panel
After=nginx.service

[Service]
User=www-data
Group=www-data
WorkingDirectory=/var/www/pterodactyl
ExecStart=/usr/bin/php artisan serve --host=0.0.0.0 --port=80
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl enable pterodactyl-panel
    echo "Pterodactyl Panel service created and enabled."
}

# Function to Install Wings
install_wings() {
    echo "Installing Pterodactyl Wings..."
    mkdir -p /etc/pterodactyl
    cd /etc/pterodactyl
    curl -Lo wings.tar.gz https://github.com/pterodactyl/wings/releases/latest/download/wings.tar.gz
    tar -xzvf wings.tar.gz --strip-components=1
    chmod +x wings

    # Create systemd service for Wings
    create_wings_service
}

# Function to Create Systemd Service for Wings
create_wings_service() {
    echo "Creating systemd service for Wings..."
    sudo tee /etc/systemd/system/pterodactyl-wings.service > /dev/null <<EOF
[Unit]
Description=Pterodactyl Wings
After=network.target

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
ExecStart=/etc/pterodactyl/wings
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl enable pterodactyl-wings
    echo "Pterodactyl Wings service created and enabled."
}

# Main Function to Run the Installer
main() {
    check_requirements
    install_dependencies

    echo "Please enter your domain name (e.g., panel.example.com): "
    read -r DOMAIN

    echo "Enter your MySQL root password: "
    read -rs MYSQL_ROOT_PASSWORD

    echo "Enter a password for the Pterodactyl MySQL user: "
    read -rs MYSQL_PTERO_PASSWORD

    echo "Do you want to enable SSL? (y/n): "
    read -r SSL_OPTION

    if [ "$SSL_OPTION" == "y" ]; then
        echo "Enter your email address for Let's Encrypt: "
        read -r EMAIL
    fi

    setup_firewall
    install_panel
    install_wings
    configure_fail2ban

    # Start services
    sudo systemctl start pterodactyl-panel
    sudo systemctl start pterodactyl-wings

    echo "Pterodactyl installation completed successfully!"
}

# Run the main function
main
