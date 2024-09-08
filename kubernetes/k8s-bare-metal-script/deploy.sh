#!/bin/bash

# Usage function to print help
usage() {
    echo "Usage: $0 -master <IP> [-worker <IP1> <IP2> ...] [-lb <IP1> <IP2> ...] [-cn <CLUSTER_NAME>]"
    echo
    echo "  -master <IP>         Specify the master IP."
    echo "  -worker <IP1> <IP2>  Specify worker IPs to run the script on specific workers."
    echo "  -lb <IP1> <IP2>      Specify load balancer IPs."
    echo "  -cn <CLUSTER_NAME>   Specify the cluster name."
    echo "  -help                Display this help message."
    exit 1
}

# Check if no arguments were provided
if [ $# -eq 0 ]; then
    if [ -f "servers.txt" ]; then
        SERVERS_FILE="servers.txt"
    else
        echo "Error: No parameters provided and servers.txt file not found."
        usage
    fi
fi

# Parse command line arguments
MASTER_IP=""
WORKER_IPS=()
LB_IPS=()
CLUSTER_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -master)
            MASTER_IP="$2"
            shift 2
            ;;
        -worker)
            shift
            while [[ $# -gt 0 && "$1" != -* ]]; do
                WORKER_IPS+=("$1")
                shift
            done
            ;;
        -lb)
            shift
            while [[ $# -gt 0 && "$1" != -* ]]; do
                LB_IPS+=("$1")
                shift
            done
            ;;
        -cn)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log "Master IP: $MASTER_IP"
log "Worker IPs: ${WORKER_IPS[@]}"
log "Load Balancer IPs: ${LB_IPS[@]}"
log "Cluster Name: $CLUSTER_NAME"

# Define the SSH key and the servers file
SSH_KEY="ssh-key.........."
SERVERS_FILE="servers.txt"
USER="ubuntu"

remove_known_hosts_entries() {
    local ip=$1
    while IFS=' ' read -r ip hostname; do
        if ! ssh-keygen -R "$ip" > /dev/null 2>&1; then
            log "Failed to remove known_hosts entry for $ip ($hostname)"
        fi
    done < "$SERVERS_FILE"
}

log "Starting script with USER: $USER and SERVERS_FILE: $SERVERS_FILE"

# Function to update authorized keys and basic configuration
update_authorized_keys() {
    local ip=$1
    log "Updating authorized keys for IP: $ip"
    
    # Run ssh-keygen silently, only log if it fails
    if ! ssh-keygen -R "$ip" > /dev/null 2>&1; then
        log "Failed to remove known_hosts entry for $ip"
        exit 1
    fi
    # Run SSH command silently, only log if it fails
    if ! ssh -T -o StrictHostKeyChecking=no -o LogLevel=ERROR "$USER@$ip" bash > /dev/null 2>&1 <<EOF
        echo '$SSH_KEY' | sudo tee /root/.ssh/authorized_keys > /dev/null
        sudo timedatectl set-timezone UTC
        if [ -f /etc/selinux/config ]; then
            sudo sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
        fi
        sudo sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
        sudo systemctl restart sshd
        sudo swapoff -a
        sudo sed -i '/ swap / s/^/#/' /etc/fstab
EOF
    then
        log "Failed to update authorized keys on server: $ip"
        exit 1
    fi
}

# Function to configure netplan on the server
configure_netplan() {
    local server_ip=$1
    log "Configuring netplan for IP: $server_ip"
    
    local IP_ROW=$(grep -n "$server_ip" "$SERVERS_FILE" | cut -f1 -d:)

    ssh -T -o StrictHostKeyChecking=no $server_ip "IP_ROW=$IP_ROW bash" << 'EOF'
        sudo ufw disable && sudo apt-get remove -y ufw && sudo apt-get purge -y ufw
        PRIMARY_IFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
        IPV4_ADDRESS=$(ip -4 addr show $PRIMARY_IFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | grep -v '^127\.')
        GATEWAY=$(ip r | grep default | grep $PRIMARY_IFACE | awk '{print $3}' | head -n 1)
        MAC_ADDRESS=$(ip link show $PRIMARY_IFACE | awk '/ether/ {print $2}')
        
        VRACK_INTERFACE=$(ip a | sed -n '/^3:/,$p' | grep -oP '^\d+: \K\S+(?=:)' | head -n 1)
        VRACK_MAC_ADDRESS=$(ip link show $VRACK_INTERFACE | awk '/ether/ {print $2}')

        cat > /etc/netplan/50-cloud-init.yaml << NETPLAN
network:
    version: 2
    ethernets:
        eth0:
            dhcp4: true
            addresses:
            - $IPV4_ADDRESS
            nameservers:
                addresses:
                - 8.8.8.8
                - 1.1.1.1
            routes:
            - on-link: true
              to: default
              via: $GATEWAY
            match:
                macaddress: $MAC_ADDRESS
            set-name: eth0
        vrack:
            dhcp4: true
            addresses:
            - 192.168.1.$IP_ROW/24
            match:
                macaddress: $VRACK_MAC_ADDRESS
            set-name: vrack
NETPLAN

        netplan apply > /dev/null 2>&1
EOF
    if [ $? -ne 0 ]; then
        log "Failed to configure netplan on server: $server_ip"
        exit 1
    fi
}

# Function to disable IPv6 on the server
disable_ipv6() {
    local server_ip=$1
    log "Disabling IPv6 for IP: $server_ip"
    ssh -T -o StrictHostKeyChecking=no $server_ip bash << 'EOF'
if [ ! -f /etc/sysctl.d/99-disable-ipv6.conf ]; then
    tee /etc/sysctl.d/99-disable-ipv6.conf << EOL
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOL
    sysctl --system > /dev/null 2>&1
fi

if ! grep -q "ipv6.disable=1" /etc/default/grub; then
    sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 ipv6.disable=1"/' /etc/default/grub
    update-grub
fi
EOF
    if [ $? -ne 0 ]; then
        log "Failed to disable IPv6 on server: $server_ip"
        exit 1
    else
        log "Successfully disabled IPv6 on server: $server_ip"
    fi
}

# Function to update /etc/hosts on a remote server
update_hosts() {
    local ip="$1"
    log "Updating /etc/hosts for IP: $ip"
    # Read the servers file
    SERVERS_CONTENT=$(<"$SERVERS_FILE")

    CUSTOM_SERVERS_CONTENT=$(echo "$SERVERS_CONTENT" | awk '{print "192.168.1."NR, $2}')

    # Extract the hostname corresponding to the given IP
    hostname=$(echo "$SERVERS_CONTENT" | grep "$ip" | awk '{print $2}')
    
    ssh -T -o StrictHostKeyChecking=no "$ip" bash <<EOF
    if ! grep -q "^$ip " /etc/hosts; then
        sudo bash -c "echo '$CUSTOM_SERVERS_CONTENT' >> /etc/hosts"
    fi
    sudo hostnamectl set-hostname $hostname
EOF
    if [ $? -ne 0 ]; then
        log "Failed to update /etc/hosts on server: $ip"
        exit 1
    fi
}

configure_nfs() {
    local server_ip=$1
    echo "Configuring iptables for IP: $server_ip"
    ssh -T -o StrictHostKeyChecking=no $server_ip bash << NFS
      export DEBIAN_FRONTEND=noninteractive
      apt_install() {
          while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
              echo "Waiting for other apt-get instances to exit"
              sleep 1
          done
          sudo apt-get install -y -qq "$@"
      }
      apt_install nfs-common
NFS
}

# Function to install iptables-persistent and configure iptables
configure_iptables() {
    local server_ip=$1
    SERVERS_CONTENT=$(<"$SERVERS_FILE")
    log "Configuring iptables for IP: $server_ip"

    # Prepare the iptables rules for the servers
    SERVER_RULES=$(while read -r ip hostname; do echo "-A INPUT -s $ip/32 -m comment --comment $hostname -j ACCEPT"; done <<< "$SERVERS_CONTENT")

    ssh -T -o StrictHostKeyChecking=no $server_ip bash << EOF
        export DEBIAN_FRONTEND=noninteractive
        apt_install() {
            while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
                echo "Waiting for other apt-get instances to exit"
                sleep 1
            done
            sudo apt-get install -y -qq "$@"
        }

        apt_install debconf-utils
        sudo debconf-set-selections <<BOOL
iptables-persistent iptables-persistent/autosave_v4 boolean true
iptables-persistent iptables-persistent/autosave_v6 boolean true
BOOL
        apt_install iptables-persistent
        sleep 1
        systemctl enable --now iptables; systemctl enable --now netfilter-persistent
        
        sleep 3
        tee /etc/iptables/rules.v4 > /dev/null << 'RULES'
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A INPUT -s 127.0.0.1/32 -p tcp -m tcp --dport 53 -m comment --comment dns -j ACCEPT
-A INPUT -s 127.0.0.1/32 -p udp -m udp --dport 53 -m comment --comment dns -j ACCEPT
-A INPUT -s 54.39.107.34/32 -m comment --comment master -j ACCEPT
-A INPUT -s 54.39.107.59/32 -m comment --comment master -j ACCEPT
-A INPUT -s 10.0.0.0/8 -m comment --comment local-cluster -j ACCEPT
-A INPUT -s 131.0.72.0/22 -m comment --comment cloud-flare -j ACCEPT
-A INPUT -s 172.64.0.0/13 -m comment --comment cloud-flare -j ACCEPT
-A INPUT -s 104.24.0.0/14 -m comment --comment cloud-flare -j ACCEPT
-A INPUT -s 104.16.0.0/13 -m comment --comment cloud-flare -j ACCEPT
-A INPUT -s 162.158.0.0/15 -m comment --comment cloud-flare -j ACCEPT
-A INPUT -s 198.41.128.0/17 -m comment --comment cloud-flare -j ACCEPT
-A INPUT -s 197.234.240.0/22 -m comment --comment cloud-flare -j ACCEPT
-A INPUT -s 188.114.96.0/20 -m comment --comment cloud-flare -j ACCEPT
-A INPUT -s 190.93.240.0/20 -m comment --comment cloud-flare -j ACCEPT
-A INPUT -s 108.162.192.0/18 -m comment --comment cloud-flare -j ACCEPT
-A INPUT -s 141.101.64.0/18 -m comment --comment cloud-flare -j ACCEPT
-A INPUT -s 103.31.4.0/22 -m comment --comment cloud-flare -j ACCEPT
-A INPUT -s 103.22.200.0/22 -m comment --comment cloud-flare -j ACCEPT
-A INPUT -s 103.21.244.0/22 -m comment --comment cloud-flare -j ACCEPT
-A INPUT -s 173.245.48.0/20 -m comment --comment cloud-flare -j ACCEPT
-A INPUT -s 192.168.1.0/24 -m comment --comment vrack -j ACCEPT
$SERVER_RULES
-A INPUT -s 1.1.1.1/32 -p tcp -m tcp --dport 53 -m comment --comment dns -j ACCEPT
-A INPUT -s 8.8.8.8/32 -p tcp -m tcp --dport 53 -m comment --comment dns -j ACCEPT
-A INPUT -s 1.1.1.1/32 -p udp -m udp --dport 53 -m comment --comment dns -j ACCEPT
-A INPUT -s 8.8.8.8/32 -p udp -m udp --dport 53 -m comment --comment dns -j ACCEPT
-A INPUT -p tcp -j DROP
COMMIT
RULES
        systemctl restart iptables
EOF
    if [ $? -ne 0 ]; then
        log "Failed to configure iptables on server: $server_ip"
        return 1
    fi
    log "Successfully configured iptables on server: $server_ip"
}

configure_k8s() {
    local server_ip=$1
    echo "Configuring Kubernetes for IP: $server_ip"
    ssh -T -o StrictHostKeyChecking=no $server_ip bash << 'EOF'
apt_get_install() {
    local package=$1
    local retries=5
    local wait_time=10

    for ((i=1; i<=retries; i++)); do
        while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1 || sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || sudo fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
           echo "Waiting for other apt operations to finish..."
           sleep 5
        done

        sudo apt-get update -qq || true

        if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends --allow-change-held-packages $package; then
            echo "Successfully installed $package"
            return 0
        else
            echo "Attempt $i of $retries to install $package failed."
            sudo dpkg --configure -a
            sudo apt-get -f install -y
            sudo apt-get clean
            sudo apt-get autoremove -y
            echo "Retrying installation of $package in $wait_time seconds..."
            sleep $wait_time
        fi
    done

    echo "Failed to install package $package after $retries attempts."
    return 1
}

# Configure kernel modules
echo -e "overlay\nbr_netfilter" | sudo tee /etc/modules-load.d/k8s.conf > /dev/null
sudo modprobe overlay
sudo modprobe br_netfilter

# Set up required sysctl params
echo -e "net.bridge.bridge-nf-call-iptables = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\nnet.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/k8s.conf > /dev/null
sudo sysctl --system > /dev/null 2>&1

# Add Kubernetes repository
sudo mkdir -p /etc/apt/keyrings
sudo rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

# Update package lists
sudo apt-get update -qq

# Install prerequisite packages
apt_get_install apt-transport-https
apt_get_install ca-certificates
apt_get_install curl
apt_get_install gpg

# Update package lists again after adding the new repository
sudo apt-get update -qq

# Install Kubernetes components
apt_get_install kubelet
apt_get_install kubeadm
apt_get_install kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Install Docker
apt_get_install docker.io

# Configure containerd
sudo mkdir -p /etc/containerd
sudo sh -c "containerd config default > /etc/containerd/config.toml"
sudo sed -i 's/ SystemdCgroup = false/ SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd.service

# Enable and start services
sudo systemctl enable --now kubelet containerd

# Configuring private ip kubelet
VRACK_IP=$(ip -4 addr show dev vrack | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
echo "KUBELET_EXTRA_ARGS=\"--node-ip=${VRACK_IP}\"" | sudo tee /etc/default/kubelet
sudo systemctl daemon-reload && sudo systemctl restart kubelet
EOF

    if [ $? -ne 0 ]; then
        echo "Failed to configure Kubernetes on server: $server_ip"
        return 1
    fi
    echo "Successfully configured Kubernetes on server: $server_ip"
}

# Function to process a server
process_server() {
    local ip=$1
    log "Removing known_hosts entries for all servers"
    remove_known_hosts_entries
    wait
    log "Processing server with IP: $ip"
    update_authorized_keys $ip &
    wait
    configure_netplan $ip &
    disable_ipv6 $ip &
    update_hosts $ip &
    configure_iptables $ip &
    wait
    configure_k8s $ip &
    wait
    configure_nfs $ip &
    wait
}


# Check if command line arguments are provided
if [ ! -z "$MASTER_IP" ] || [ ${#WORKER_IPS[@]} -ne 0 ] || [ ${#LB_IPS[@]} -ne 0 ]; then
    # Ensure a master IP is specified to generate the join command
    if [ -z "$MASTER_IP" ]; then
        log "Error: Master IP is required when adding nodes."
        usage
    fi

    # Generate or retrieve the join command directly from the master node
    JOIN_COMMAND=$(ssh -T -o StrictHostKeyChecking=no $MASTER_IP bash << 'EOF'
sudo kubeadm token create --print-join-command
EOF
    )

    # Propagate the join command to new worker or load balancer nodes
    for ip in "${WORKER_IPS[@]}" "${LB_IPS[@]}"; do
        log "Propagating join command to node at IP: $ip"
        ssh -T -o StrictHostKeyChecking=no $ip bash << EOF
$JOIN_COMMAND
EOF
        if [ $? -ne 0 ]; then
            log "Failed to propagate join command to node at IP: $ip"
            exit 1
        fi

        # Check if this is a load balancer node and apply label and taint
        if [[ " ${LB_IPS[@]} " =~ " $ip " ]]; then
            # Assume hostname follows a specific pattern replacing "master" with "lb"
            node_hostname=$(ssh -T -o StrictHostKeyChecking=no $ip hostname | sed 's/master/lb/')
            log "Labeling and tainting load balancer node: $node_hostname"
            kubectl label nodes $node_hostname ingress=true --overwrite
            kubectl taint nodes $node_hostname dedicated=ingress:NoSchedule --overwrite
        fi
    done
    log "Nodes added to the existing cluster successfully."
else
    # If no command line arguments are provided, follow another procedure
    if [ -z "$MASTER_IP" ] && [ ${#WORKER_IPS[@]} -eq 0 ] && [ -n "$CLUSTER_NAME" ]; then
        # Using -cn flag, read from servers.txt
        while IFS=' ' read -r ip hostname; do
            process_server $ip &
        done < "$SERVERS_FILE"
    else
        # Parameters provided, check if MASTER_IP is set
        if [ -z "$MASTER_IP" ]; then
            log "Error: Master IP is required."
            usage
        fi

        # If WORKER_IPS is provided, process only those workers
        if [ ${#WORKER_IPS[@]} -ne 0 ]; then
            for worker_ip in "${WORKER_IPS[@]}"; do
                process_server $worker_ip &
            done
        else
            # Read the IPs from the servers file and process all servers
            while IFS=' ' read -r ip hostname; do
                process_server $ip &
            done < "$SERVERS_FILE"
        fi
    fi
fi

wait
log "All tasks completed."


Read the master01 node IP and hostname
MASTER01=$(awk '/master01/ {print $1}' $SERVERS_FILE)
log "Master01 node IP: $MASTER01"

# Initialize the Kubernetes cluster on master01
ssh -T -o StrictHostKeyChecking=no $MASTER01 bash << EOF
HOSTNAME=\$(hostname)
sudo kubeadm init --config=/dev/stdin << KUBEADM_EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
clusterName: $CLUSTER_NAME
kubernetesVersion: stable-1.29
controlPlaneEndpoint: "\$HOSTNAME"
networking:
  podSubnet: "10.244.0.0/16"
KUBEADM_EOF

if [ $? -ne 0 ]; then
    echo "kubeadm init failed"
    exit 1
fi

sleep 1
mkdir -p \$HOME/.kube && sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config && sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config

curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
EOF

if [ $? -ne 0 ]; then
    log "Failed to initialize Kubernetes cluster on master01"
    exit 1
fi

# Upload certificates and get the certificate key
CERT_KEY=$(ssh -T -o StrictHostKeyChecking=no $MASTER01 bash << 'EOF'
sudo kubeadm init phase upload-certs --upload-certs | grep -A 1 "Using certificate key" | tail -n 1
EOF
)

if [ $? -ne 0 ] || [ -z "$CERT_KEY" ]; then
    log "Failed to upload certificates and get certificate key from master01"
    exit 1
fi
log "Certificate key obtained: $CERT_KEY"

# Create the join command with the certificate key
JOIN_COMMAND=$(ssh -T -o StrictHostKeyChecking=no $MASTER01 bash << EOF
sudo kubeadm token create --print-join-command --certificate-key $CERT_KEY
EOF
)

if [ $? -ne 0 ] || [ -z "$JOIN_COMMAND" ]; then
    log "Failed to create join command on master01"
    exit 1
fi
log "Join command created: $JOIN_COMMAND"

# Propagate the join command to the other master nodes
while read -r ip hostname; do
    if [[ "$hostname" == *"master"* && "$hostname" != *"master01"* ]]; then
        log "Propagating join command to master node at IP: $ip"
        ssh -T -o StrictHostKeyChecking=no $ip bash << EOF
$JOIN_COMMAND
EOF
        if [ $? -ne 0 ]; then
            log "Failed to propagate join command to master node at IP: $ip"
            exit 1
        fi
    fi
done < $SERVERS_FILE

# Generate join command for worker nodes
WORKER_JOIN_COMMAND=$(ssh -T -o StrictHostKeyChecking=no $MASTER01 bash << 'EOF'
sudo kubeadm token create --print-join-command
EOF
)

if [ $? -ne 0 ]; then
    log "Failed to generate join command for worker nodes on master01"
    exit 1
fi
log "Worker join command generated."

# Propagate the join command to worker nodes
while read -r ip hostname; do
    if [[ "$hostname" != *"master"* ]]; then
        log "Propagating join command to worker node at IP: $ip"
        ssh -T -o StrictHostKeyChecking=no $ip bash << EOF
$WORKER_JOIN_COMMAND
EOF
        if [ $? -ne 0 ]; then
            log "Failed to propagate join command to worker node at IP: $ip"
            exit 1
        fi
    fi
done < $SERVERS_FILE

log "Done initializing cluster nodes"
sleep 10

MASTER_IP_ONE=$(grep "master01" $SERVERS_FILE | awk '{print $1}')
if [ -z "$MASTER_IP_ONE" ]; then
    log "Error: Unable to extract master01 IP from $SERVERS_FILE"
    exit 1
fi
log "Master IP for final operations: $MASTER_IP_ONE"

# Extract external IPs from '-lb' nodes
EXTERNAL_IPS=$(grep "\-lb" $SERVERS_FILE | awk '{print $1}')
if [ -z "$EXTERNAL_IPS" ]; then
    log "Error: Unable to extract load balancer IPs from $SERVERS_FILE"
    exit 1
fi
log "External IPs for load balancers: $EXTERNAL_IPS"

# Extract and taint the nodes with '-lb' in their hostname
LB_NODES=$(grep "\-lb" $SERVERS_FILE | awk '{print $2}')
log "Load balancer nodes to taint: $LB_NODES"

# Initialize variables
externalIPs=""
index=0

# Convert the external IPs into Helm values format and assign to variables
for ip in $EXTERNAL_IPS; do
    if [ $index -eq 0 ]; then
        EXTERNAL_IP1=$ip
    elif [ $index -eq 1 ]; then
        EXTERNAL_IP2=$ip
    fi
    externalIPs+=" --set controller.service.externalIPs[$index]=$ip"
    index=$((index+1))
done

replicaCount=$index
log "Replica count for ingress controller: $replicaCount"
log "EXTERNAL_IP1: $EXTERNAL_IP1"
log "EXTERNAL_IP2: $EXTERNAL_IP2"

# SSH into the master node and execute the commands
log "Connecting to master node: $MASTER_IP_ONE"
ssh -T -o StrictHostKeyChecking=no root@$MASTER_IP_ONE << EOF
set -e
export CLUSTER_NAME=$CLUSTER_NAME
export EXTERNAL_IP1=$EXTERNAL_IP1
export EXTERNAL_IP2=$EXTERNAL_IP2
replicaCount=$replicaCount

sed -i "s/kubernetes/$CLUSTER_NAME/g" /root/.kube/config
kubectl apply -f - <<EOC
apiVersion: v1
data:
  Corefile: |
    .:53 {
        errors
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        prometheus :9153
        forward . 8.8.8.8 1.1.1.1
        cache 30
        loop
        reload
        loadbalance
    }
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
EOC
kubectl rollout restart deployment coredns -n kube-system

helm repo add kubescape https://kubescape.github.io/helm-charts/ || true
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx || true
helm repo add gitlab https://charts.gitlab.io || true
helm repo add cilium https://helm.cilium.io/ || true
helm repo add argo https://argoproj.github.io/argo-helm || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/ || true
helm repo update

# Taint the nodes with '-lb' in their hostname
while read -r node; do
    kubectl taint nodes \$node dedicated=ingress:NoSchedule --overwrite
    kubectl label nodes \$node ingress=true --overwrite
done <<< "$LB_NODES"

# Check if Cilium CLI is installed, uninstall if found, and then reinstall
command -v cilium &> /dev/null && sudo rm /usr/local/bin/cilium

# Download and install Cilium CLI
CILIUM_CLI_VERSION=\$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "\$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/\${CILIUM_CLI_VERSION}/cilium-linux-\${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-\${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-\${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-\${CLI_ARCH}.tar.gz{,.sha256sum}

# Install Cilium with the specified configurations
cilium install \
  --set kubeProxyReplacement=true \
  --set-string extraConfig.enable-envoy-config=true \
  --set loadBalancer.l7.backend=envoy \
  --helm-set bpf.lbExternalClusterIP=true \
  --helm-set bpf.tproxy=true \
  --helm-set ipv6.enabled=false \
  --set bpf.masquerade=true \
  --set egressGateway.enabled=true \
  --helm-set sctp.enabled=true \
  --set l2podAnnouncements.enabled=true \
  --set l2podAnnouncements.interface=vrack \
  --set l2announcements.enabled=true \
  --set externalIPs.enabled=true \
  --helm-set socketLB.enabled=true \
  --set k8sServiceHost=$MASTER_IP_ONE \
  --set k8sServicePort=6443 \
  --set policyEnforcement=always \
  --set hubble.enabled=true

cilium hubble enable

# Install Hubble client
HUBBLE_VERSION=\$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
HUBBLE_ARCH=amd64
if [ "\$(uname -m)" = "aarch64" ]; then HUBBLE_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/hubble/releases/download/\$HUBBLE_VERSION/hubble-linux-\${HUBBLE_ARCH}.tar.gz{,.sha256sum}
sha256sum --check hubble-linux-\${HUBBLE_ARCH}.tar.gz.sha256sum
sudo tar xzvfC hubble-linux-\${HUBBLE_ARCH}.tar.gz /usr/local/bin
rm hubble-linux-\${HUBBLE_ARCH}.tar.gz{,.sha256sum}

echo "Cilium installation completed"

# Apply NGINX Ingress CRDs
kubectl apply -f https://raw.githubusercontent.com/nginxinc/kubernetes-ingress/v3.6.1/deploy/crds.yaml

sleep 2

# Create a values file for NGINX Ingress
cat << EOT > nginx-ingress-values.yaml
controller:
  enableSnippets: true
  disableIPV6: true
  nodeSelector:
    ingress: "true"
  replicaCount: ${replicaCount}
  resources:
    requests:
      cpu: 2
      memory: 6Gi
  metrics:
    enabled: true
    serviceMonitor:
      enabled: false
  config:
    ssl-protocols: "TLSv1.2 TLSv1.3"
    ssl-ciphers: "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384"
  tolerations:
    - key: "dedicated"
      operator: "Equal"
      value: "ingress"
      effect: "NoSchedule"
  ingressClassResource:
    name: nginx
    enabled: true
    default: true
  service:
    externalTrafficPolicy: Local
    externalIPs:
      - ${EXTERNAL_IP1}
      - ${EXTERNAL_IP2}
EOT

# Install NGINX Ingress controller using the values file
helm install ${CLUSTER_NAME}-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  -f nginx-ingress-values.yaml

echo "Helm installation completed. Proceeding with verification..."

# Verify the service configuration
# echo "Verifying service configuration:"
# kubectl get service -n ingress-nginx ${CLUSTER_NAME}-ingress-ingress-nginx-controller -o yaml

# Check if external IPs are set correctly
EXTERNAL_IPS=$(kubectl get service -n ingress-nginx ${CLUSTER_NAME}-ingress-ingress-nginx-controller -o jsonpath='{.spec.externalIPs}')
if [[ -z "$EXTERNAL_IPS" ]]; then
    echo "Warning: External IPs are not set in the service."
else
    echo "External IPs set in the service: $EXTERNAL_IPS"
fi

# Install the Kubernetes Metrics Server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch the Metrics Server deployment to use insecure connections
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}, {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-preferred-address-types=InternalIP,Hostname,ExternalIP"}]'

# Wait for the Metrics Server to be ready
kubectl rollout status deployment metrics-server -n kube-system

echo "Metrics Server installation and patching completed"

kubectl apply -f - <<HPA
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ingress-nginx-hpa
  namespace: ingress-nginx
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ${CLUSTER_NAME}-ingress-ingress-nginx-controller
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 80
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
HPA
echo "Cluster setup completed"
echo "NOTE: ServiceMonitor for NGINX Ingress metrics is disabled. To enable it, install Prometheus Operator and its CRDs, then update the Helm release with serviceMonitor.enabled=true"
EOF

if [ $? -ne 0 ]; then
    log "Failed during the setup operations on master node"
    exit 1
fi
log "Successfully completed setup operations on master node"
sleep 10

ssh -T -o StrictHostKeyChecking=no $MASTER_IP_ONE bash <<EOF
kubectl apply -f - <<EOF
apiVersion: cilium.io/v2
kind: CiliumEgressGatewayPolicy
metadata:
  name: egress-all-pods
spec:
  selectors:
  - podSelector: {}
  destinationCIDRs:
  - "0.0.0.0/0"
  egressGateway:
    nodeSelector:
      matchLabels:
        ingress: "true"
---
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: allow-all-icmp
spec:
  egress:
  - toEntities:
    - all
  - icmps:
    - fields:
      - family: IPv4
        type: 0
      - family: IPv4
        type: 3
      - family: IPv4
        type: 4
      - family: IPv4
        type: 5
      - family: IPv4
        type: 8
      - family: IPv4
        type: 11
      - family: IPv4
        type: 12
      - family: IPv4
        type: 13
      - family: IPv4
        type: 14
      - family: IPv4
        type: 15
      - family: IPv4
        type: 16
      - family: IPv4
        type: 17
      - family: IPv4
        type: 18
      - family: IPv6
        type: 1
      - family: IPv6
        type: 2
      - family: IPv6
        type: 3
      - family: IPv6
        type: 4
      - family: IPv6
        type: 128
      - family: IPv6
        type: 129
      - family: IPv6
        type: 133
      - family: IPv6
        type: 134
      - family: IPv6
        type: 135
      - family: IPv6
        type: 136
      - family: IPv6
        type: 137
  endpointSelector: {}
---
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: allow-all-to-coredns
spec:
  egress:
  - toPorts:
    - ports:
      - port: "53"
        protocol: UDP
      - port: "53"
        protocol: TCP
  endpointSelector:
    matchLabels:
      io.kubernetes.pod.namespace: kube-system
      k8s-app: coredns
  ingress:
  - fromEntities:
    - cluster
    - host
    - remote-node
    - kube-apiserver
    - health
    - ingress
    - init
    - unmanaged
    toPorts:
    - ports:
      - port: "53"
        protocol: UDP
      - port: "53"
        protocol: TCP
---
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: dai
spec:
  egress:
  - toEntities:
    - world
    - host
    - remote-node
    - kube-apiserver
    - health
    - cluster
  endpointSelector: {}
  ingress:
  - fromEntities:
    - cluster
    - host
    - remote-node
    - kube-apiserver
    - health
    - ingress
    - init
    - unmanaged
    toPorts:
    - ports:
      - port: "0"
        protocol: TCP
      - port: "0"
        protocol: UDP
  - fromCIDR:
$(awk '{print "    - "$1"/32"}' $SERVERS_FILE)
  - fromCIDRSet:
    - cidr: 10.0.0.0/8
    - cidr: 192.168.1.0/24
    - cidr: 103.21.244.0/22
    - cidr: 103.22.200.0/22
    - cidr: 103.31.4.0/22
    - cidr: 104.16.0.0/13
    - cidr: 104.24.0.0/14
    - cidr: 108.162.192.0/18
    - cidr: 131.0.72.0/22
    - cidr: 141.101.64.0/18
    - cidr: 162.158.0.0/15
    - cidr: 172.64.0.0/13
    - cidr: 173.245.48.0/20
    - cidr: 188.114.96.0/20
    - cidr: 190.93.240.0/20
    - cidr: 197.234.240.0/22
    - cidr: 198.41.128.0/17
    toPorts:
    - ports:
      - port: "0"
        protocol: TCP
      - port: "0"
        protocol: UDP
EOF
if [ $? -ne 0 ]; then
    log "Failed to apply Cilium policy on master node: $MASTER_IP_ONE"
    exit 1
fi
log "Cilium policy applied on master node: $MASTER_IP_ONE"

ssh -T -o StrictHostKeyChecking=no $MASTER_IP_ONE bash <<FINAL
    echo "source <(kubectl completion bash)" >> ~/.bashrc
    echo "source <(helm completion bash)" >> ~/.bashrc
    echo "alias k=kubectl" >> ~/.bashrc
    echo "complete -o default -F __start_kubectl k" >> ~/.bashrc
    source ~/.bashrc
    kubectl -n kube-system delete ds kube-proxy --force --grace-period=0
FINAL