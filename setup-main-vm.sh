#!/bin/bash

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

if [ "$EUID" -ne 0 ]; then 
    print_error "Por favor, execute como root (sudo)"
    exit 1
}

# Instalar Docker
install_docker() {
    print_message "Instalando Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    systemctl enable docker
    systemctl start docker
}

# Inicializar Swarm
init_swarm() {
    print_message "Inicializando Docker Swarm..."
    SWARM_TOKEN=$(docker swarm init --advertise-addr $(hostname -I | awk '{print $1}') 2>&1 | grep "docker swarm join --token" || true)
    echo "$SWARM_TOKEN" > /root/swarm_token.txt
    
    # Criar rede overlay
    docker network create -d overlay monitoring || true
}

# Instalar Portainer
install_portainer() {
    print_message "Instalando Portainer Principal..."
    docker volume create portainer_data
    
    # Remover container anterior se existir
    docker rm -f portainer || true
    
    docker run -d \
        -p 9000:9000 \
        --name portainer \
        --restart always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce
}

# Script principal
main() {
    print_message "Iniciando setup da VM Principal..."
    
    install_docker
    init_swarm
    install_portainer
    
    print_message "Setup concluído!"
    print_message "Portainer disponível em: http://$(hostname -I | awk '{print $1}'):9000"
    print_message "Token do Swarm salvo em: /root/swarm_token.txt"
}

main