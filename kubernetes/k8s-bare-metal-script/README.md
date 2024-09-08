# Kubernetes Cluster Setup Script

This Bash script automates the process of setting up a Kubernetes cluster across multiple nodes. It's designed to configure master nodes, worker nodes, and load balancer nodes in a flexible and customizable manner.

## Features

- Automated setup of Kubernetes cluster components
- Flexible configuration for master, worker, and load balancer nodes
- Network configuration including IPv6 disabling and iptables setup
- Kubernetes components installation (kubelet, kubeadm, kubectl)
- Docker installation and containerd configuration
- Cilium CNI installation with custom configurations
- NGINX Ingress controller setup with external IP configuration
- Metrics Server installation and configuration
- Horizontal Pod Autoscaler (HPA) setup for the Ingress controller
- Cilium network policies application

## Prerequisites

- Ubuntu-based servers for all nodes
- SSH access to all nodes
- `servers.txt` file with IP addresses and hostnames of all nodes (if not using command-line arguments)

## Usage

The script can be used in two primary ways:

1. Using command-line arguments:

   ```bash
   ./script.sh -master <MASTER_IP> [-worker <WORKER_IP1> <WORKER_IP2> ...] [-lb <LB_IP1> <LB_IP2> ...] [-cn <CLUSTER_NAME>]
   ```

2. Using a `servers.txt` file:

   ```bash
   ./script.sh -cn <CLUSTER_NAME>
   ```

### Command-line Arguments

- `-master <IP>`: Specify the master node IP
- `-worker <IP1> <IP2> ...`: Specify worker node IPs
- `-lb <IP1> <IP2> ...`: Specify load balancer node IPs
- `-cn <CLUSTER_NAME>`: Specify the cluster name

### servers.txt Format

```
<IP> <HOSTNAME>
<IP> <HOSTNAME>
...
```

## Script Workflow

1. Process each server:
   - Update authorized keys
   - Configure netplan
   - Disable IPv6
   - Update /etc/hosts
   - Configure iptables
   - Install and configure Kubernetes components

2. Initialize the Kubernetes cluster on the first master node

3. Join other master nodes to the cluster

4. Join worker nodes to the cluster

5. Install and configure Cilium CNI

6. Install NGINX Ingress controller

7. Install Kubernetes Metrics Server

8. Set up Horizontal Pod Autoscaler for the Ingress controller

9. Apply Cilium network policies

## Customization

The script includes several customizable parameters, such as:

- Kubernetes version
- Cilium configuration options
- NGINX Ingress controller settings
- Network CIDR ranges

Modify these parameters in the script to suit your specific requirements.

## Notes

- Ensure all servers have the necessary ports open for Kubernetes communication.
- The script assumes Ubuntu-based systems. Modifications may be needed for other distributions.
- Review and adjust the Cilium and NGINX Ingress configurations based on your network requirements.

## Troubleshooting

- Check the script logs for any error messages.
- Ensure all nodes can communicate with each other.
- Verify that the `servers.txt` file is correctly formatted if using that method.

## Contributing

Contributions to improve the script are welcome. Please submit pull requests or open issues for any bugs or feature requests.

## License

[Specify your license here]