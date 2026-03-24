#!/bin/bash

# Microsoft Intune Installer Helper for Linux
# Supports: Ubuntu 22.04/24.04 and RHEL 8/9

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

printf "${BLUE}==>${NC} Starting Microsoft Intune installation helper...\n"

# Function to check if a command exists
exists() {
  command -v "$1" >/dev/null 2>&1
}

# Identify Distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    printf "${RED}error:${NC} Cannot detect OS distribution.\n"
    exit 1
fi

install_ubuntu() {
    printf "${BLUE}==>${NC} Configuring Microsoft repository for Ubuntu ${VER}...\n"
    
    sudo apt update && sudo apt install -y curl gpg
    
    # Download and install the Microsoft signing key
    curl -sSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/microsoft.gpg > /dev/null
    
    # Add the repository
    # Note: $(lsb_release -rs) is used to ensure the correct path
    REPO_URL="https://packages.microsoft.com/ubuntu/$(lsb_release -rs)/prod"
    REPO_FILE="/etc/apt/sources.list.d/microsoft-ubuntu-$(lsb_release -cs)-prod.list"
    
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] ${REPO_URL} $(lsb_release -cs) main" | sudo tee $REPO_FILE > /dev/null

    printf "${BLUE}==>${NC} Updating package lists...\n"
    sudo apt update
    
    printf "${BLUE}==>${NC} Installing Intune Portal...\n"
    sudo apt install -y intune-portal
}

install_rhel() {
    printf "${BLUE}==>${NC} Configuring Microsoft repository for RHEL ${VER}...\n"
    
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    
    # RHEL repository setup (adjusting for major version)
    MAJOR_VER=$(echo $VER | cut -d. -f1)
    sudo dnf config-manager --add-repo https://packages.microsoft.com/yumrepos/microsoft-rhel${MAJOR_VER}.0-prod
    
    printf "${BLUE}==>${NC} Installing Intune Portal...\n"
    sudo dnf install -y intune-portal
}

# Main Logic
case "$OS" in
    ubuntu)
        install_ubuntu
        ;;
    rhel|centos|fedora)
        install_rhel
        ;;
    *)
        printf "${RED}error:${NC} Your OS ($OS) is not officially supported by this script.\n"
        exit 1
        ;;
esac

printf "\n${GREEN}Success!${NC} Microsoft Intune has been installed.\n"

# Apply polkit rule for Intune agent
# This allows users in the "users" group to perform necessary actions for device configuration without needing root access.
# If you don't have a group requirement, just remove the whole "&& subject.isInGroup("users"))" part

printf "${BLUE}==>${NC} Applying Intune polkit rule...\n"
sudo mkdir -p /etc/polkit-1/rules.d
cat <<'EOF' | sudo tee /etc/polkit-1/rules.d/intune-agent.rules > /dev/null
/* Applying configuration from Microsoft Intune Portal */
polkit.addRule(function(action, subject) {
    if (action.id == "com.microsoft.intune.actions.ConfigureDevice" &&   subject.isInGroup("users")) {
        return polkit.Result.YES;
    }
});
EOF

printf "${GREEN}Success!${NC} intune-agent.rules has been created in /etc/polkit-1/rules.d/.\n"
printf "${BLUE}==>${NC} PLEASE REBOOT your machine to complete the registration setup.\n"