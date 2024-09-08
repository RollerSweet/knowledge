#!/bin/bash

# Check if an IP address was passed as an argument
if [ $# -eq 0 ]; then
    echo "Usage: $0 <IP>"
    exit 1
fi

# Extract the IP address from the first argument
ip="$1"

# Function to check and update the hostname on the given IP
process_ip() {
    local ip="$1"
    local zabbix_config="/etc/zabbix/zabbix_agent2.conf"
    local current_hostname
    local zabbix_hostname

    echo "Processing IP: $ip"

    # Retrieve the hostname of the target machine
    current_hostname=$(ssh "$ip" 'hostname')

    # Retrieve the hostname from the Zabbix agent configuration
    zabbix_hostname=$(ssh "$ip" "grep -m1 '^Hostname=' $zabbix_config" | cut -d'=' -f2)

    # Compare the two hostnames
    if [[ "$current_hostname" != "$zabbix_hostname" ]]; then
        echo "Updating hostname for $ip from '$zabbix_hostname' to '$current_hostname'"
        ssh "$ip" "sudo sed -i 's/^Hostname=.*/Hostname=$current_hostname/' $zabbix_config"
        ssh "$ip" "sudo systemctl restart zabbix-agent2"
        echo "Hostname updated and Zabbix agent restarted for $ip."
    else
        echo "No changes needed for $ip (hostname: '$current_hostname')."
    fi
}

# Call the process_ip function with the given IP
process_ip "$ip"

