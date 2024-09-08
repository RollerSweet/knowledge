#!/bin/bash

# Install Zabbix agent on a remote server
install_zabbix_agent() {
  REMOTE_SERVER_IP=$1

  ssh -o PasswordAuthentication=yes -o StrictHostKeyChecking=no ${REMOTE_SERVER_IP} bash << 'EOF'
  # Check if Zabbix agent is already installed
  if systemctl is-active --quiet zabbix-agent2; then
    echo "Zabbix agent is already installed and running."
    exit 0
  fi

  # Determine the operating system
  if grep -iq 'ubuntu' /etc/os-release; then
    # Update package list and install required packages quietly
    sudo apt-get update -qq > /dev/null
    sudo apt-get install -qq wget vim dmidecode mc iptraf pciutils psmisc net-tools traceroute ipmitool dnsutils nmap curl > /dev/null

    # Set DNS servers if they don't exist
    grep -q 'nameserver 8.8.8.8' /etc/resolv.conf || echo 'nameserver 8.8.8.8' | sudo tee -a /etc/resolv.conf > /dev/null
    grep -q 'nameserver 1.1.1.1' /etc/resolv.conf || echo 'nameserver 1.1.1.1' | sudo tee -a /etc/resolv.conf > /dev/null

    # Download and install Zabbix agent quietly
    wget -q https://repo.zabbix.com/zabbix/6.4/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.4-1+ubuntu22.04_all.deb > /dev/null
    sudo dpkg -i zabbix-release_6.4-1+ubuntu22.04_all.deb > /dev/null
    sudo apt-get update -qq > /dev/null
    sudo apt-get install -qq zabbix-agent2 zabbix-agent2-plugin-* > /dev/null

    # Configure Zabbix agent
    sudo sed -i -r 's/Server=.*/Server=zabbix.domain.name/' /etc/zabbix/zabbix_agent2.conf
    sudo sed -i -r 's/ServerActive=.*/ServerActive=zabbix.domain.name/' /etc/zabbix/zabbix_agent2.conf
    sudo sed -i -e "s&^Hostname=.*&Hostname=$(hostname)&" /etc/zabbix/zabbix_agent2.conf

    # Restart and enable Zabbix agent service
    sudo systemctl restart zabbix-agent2 > /dev/null
    sudo systemctl enable zabbix-agent2 > /dev/null || { echo "Error: Failed to enable Zabbix agent"; exit 2; }

    echo "Zabbix agent installed and configured to connect to zabbix.domain.name"

  elif grep -iq 'rocky' /etc/os-release; then
    # Disable Zabbix packages from EPEL if it exists
    sudo sed -i '/\[epel\]/a exclude=zabbix*' /etc/yum.repos.d/epel.repo 2>/dev/null

    # Install Zabbix repository
    sudo rpm -Uvh https://repo.zabbix.com/zabbix/6.4/rhel/9/x86_64/zabbix-release-6.4-2.el9.noarch.rpm > /dev/null
    sudo dnf clean all > /dev/null

    # Update package list and install required packages quietly
    sudo dnf install -y -q wget vim dmidecode mc iptraf pciutils psmisc net-tools traceroute ipmitool bind-utils nmap curl > /dev/null

    # Set DNS servers if they don't exist
    grep -q 'nameserver 8.8.8.8' /etc/resolv.conf || echo 'nameserver 8.8.8.8' | sudo tee -a /etc/resolv.conf > /dev/null
    grep -q 'nameserver 1.1.1.1' /etc/resolv.conf || echo 'nameserver 1.1.1.1' | sudo tee -a /etc/resolv.conf > /dev/null

    # Install Zabbix agent2
    sudo dnf install -y -q zabbix-agent2 zabbix-agent2-plugin-* > /dev/null

    # Configure Zabbix agent
    sudo sed -i -r 's/Server=.*/Server=zabbix.domain.name/' /etc/zabbix/zabbix_agent2.conf
    sudo sed -i -r 's/ServerActive=.*/ServerActive=zabbix.domain.name/' /etc/zabbix/zabbix_agent2.conf
    sudo sed -i -e "s&^Hostname=.*&Hostname=$(hostname)&" /etc/zabbix/zabbix_agent2.conf

    # Restart and enable Zabbix agent service
    sudo systemctl restart zabbix-agent2 > /dev/null
    sudo systemctl enable zabbix-agent2 > /dev/null || { echo "Error: Failed to enable Zabbix agent"; exit 2; }

    echo "Zabbix agent installed and configured to connect to zabbix.domain.name"
  else
    echo "OS is not Ubuntu or Rocky Linux. This script currently supports only Ubuntu and Rocky Linux."
    exit 1
  fi
EOF
}

# Show usage if no parameters are provided
if [ $# -eq 0 ]; then
  echo "Usage: $0 <REMOTE_SERVER_IP> [<REMOTE_SERVER_IP>...]"
  exit 1
fi

# Loop through the provided IP addresses and run the function in the background
for REMOTE_SERVER_IP in "$@"; do
  install_zabbix_agent "$REMOTE_SERVER_IP" &
done

# Wait for all background jobs to complete
wait

echo "All tasks completed."