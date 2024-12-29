#!/bin/bash

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Função para imprimir mensagens
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar se é root
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

# Configurar Docker para acesso remoto
configure_remote_access() {
    print_message "Configurando acesso remoto do Docker..."
    
    mkdir -p /etc/docker
    cat << INNEREOF > /etc/docker/daemon.json
{
    "tls": false,
    "hosts": ["tcp://0.0.0.0:2375", "unix:///var/run/docker.sock"]
}
INNEREOF

    mkdir -p /etc/systemd/system/docker.service.d
    cat << INNEREOF > /etc/systemd/system/docker.service.d/override.conf
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd
INNEREOF

    systemctl daemon-reload
    systemctl restart docker
}

# Inicializar Docker Swarm
init_swarm() {
    print_message "Inicializando Docker Swarm..."
    docker swarm init --advertise-addr $(hostname -I | awk '{print $1}') || true
    
    # Criar rede overlay
    docker network create -d overlay monitoring || true
}

# Instalar Portainer
install_portainer() {
    print_message "Instalando Portainer..."
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
    print_message "Iniciando setup da VM Docker..."
    
    install_docker
    configure_remote_access
    init_swarm
    install_portainer
    
    print_message "Setup concluído!"
    print_message "Portainer disponível em: http://$(hostname -I | awk '{print $1}'):9000"
    print_message "Docker disponível em: tcp://$(hostname -I | awk '{print $1}'):2375"
}

# Executar script
main