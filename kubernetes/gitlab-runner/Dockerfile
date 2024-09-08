# Use Ubuntu as the base image
FROM ubuntu:22.04

# Environment variables
ENV NODE_VERSION=20.0.0
ENV NVM_DIR=/usr/local/nvm
ENV DEBIAN_FRONTEND=noninteractive

# Install base utilities, Docker, kubectl, and Azure CLI in one layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates gnupg gnupg2 lsb-release git git-lfs \
    openssh-client vim apt-transport-https software-properties-common sed \
    && curl -fsSL https://get.docker.com -o get-docker.sh \
    && sh get-docker.sh \
    && rm get-docker.sh \
    && curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x ./kubectl \
    && mv ./kubectl /usr/local/bin/kubectl \
    && curl -sL https://aka.ms/InstallAzureCLIDeb | bash \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install NVM, Node.js, npm, Yarn, and pnpm
RUN mkdir -p $NVM_DIR \
    && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash \
    && . $NVM_DIR/nvm.sh \
    && nvm install $NODE_VERSION \
    && nvm alias default $NODE_VERSION \
    && nvm use default \
    && npm install -g yarn pnpm \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Create .kube directory and empty config file
RUN mkdir -p /root/.kube && touch /root/.kube/config
ENV KUBECONFIG=/root/.kube/config

# Set PATH after Node.js installation
ENV PATH=$NVM_DIR/versions/node/v${NODE_VERSION}/bin:$PATH

WORKDIR /root

CMD ["bash"]