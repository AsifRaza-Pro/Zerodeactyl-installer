# Zerodeactyl Installer

Zerodeactyl is a Bash script designed for automating the installation of the Pterodactyl game server management panel on Ubuntu systems. The script facilitates the setup of both the panel and Wings service, providing options for SSL configuration, MySQL database setup, and firewall configuration.

## Features

- **Automated Installation**: Installs Pterodactyl Panel and Wings service with a single command.
- **User-Friendly Menu**: Interactive prompts for user inputs, including domain name, MySQL passwords, and SSL options.
- **Database Setup**: Automatically creates a MySQL database and user for the Pterodactyl panel.
- **Nginx Configuration**: Configures Nginx for serving the Pterodactyl panel, with options for SSL through Let's Encrypt.
- **Firewall Configuration**: Sets up UFW to allow necessary ports for Pterodactyl functionality.
- **DDoS Protection**: Configures Fail2ban to enhance security against unauthorized access.

## Requirements

- **Operating System**: Ubuntu (18.04 and above recommended)
- **Web Server**: Nginx (must be installed before running the script)
- **Permissions**: Script should be executed with sudo privileges.

## Installation

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/AsifRaza-Pro/Zerodeactyl-installer.git
   
cd Zerodeactyl-installer.         
# Make the Script Executable:
```chmod +x zerdactyl.sh```

# Run the Installer:
```sudo ./zerdactyl.sh```
# To check:
```sudo systemctl status pterodactyl-panel
```sudo systemctl status pterodactyl-wing```

