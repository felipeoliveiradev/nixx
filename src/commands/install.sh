# src/commands/install.sh
#!/bin/bash

# Instalar Docker
install_docker() {
    print_info "Instalando Docker..."
    
    # Remover versões antigas
    apt-get remove -y docker docker-engine docker.io containerd runc || true
    
    # Instalar dependências
    apt-get update
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # Adicionar chave GPG oficial do Docker
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # Adicionar repositório
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Instalar Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # Iniciar e habilitar serviço
    systemctl enable docker
    systemctl start docker

    print_success "Docker instalado com sucesso"
}

# Configurar acesso remoto
configure_remote_access() {
    print_info "Configurando acesso remoto do Docker..."
    
    mkdir -p /etc/docker
    mkdir -p /etc/systemd/system/docker.service.d

    # Configurar daemon.json
    cat > /etc/docker/daemon.json << EOF
{
    "tls": false,
    "hosts": ["tcp://0.0.0.0:2375", "unix:///var/run/docker.sock"]
}
EOF

    # Configurar override
    cat > /etc/systemd/system/docker.service.d/override.conf << EOF
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd
EOF

    # Recarregar configurações
    systemctl daemon-reload
    systemctl restart docker
    sleep 5

    print_success "Acesso remoto configurado"
}

# Inicializar Swarm
init_swarm() {
    print_info "Inicializando Swarm..."
    local ip=$(hostname -I | awk '{print $1}')
    
    # Verificar se já está no swarm
    if docker info --format '{{.Swarm.LocalNodeState}}' | grep "active" > /dev/null; then
        print_warning "Node já está no Swarm. Recriando..."
        docker swarm leave --force
        sleep 2
    fi

    # Inicializar swarm
    docker swarm init --advertise-addr "$ip"
    
    # Criar rede overlay
    docker network create --driver overlay monitoring

    print_success "Swarm inicializado"
    return 0
}

# Handler principal de instalação
handle_install() {
    local type=$1
    
    if ! check_requirements; then
        return 1
    fi

    case $type in
        "main")
            install_docker
            configure_remote_access
            init_swarm
            create_service portainer
            ;;
        "client")
            install_docker
            configure_remote_access
            
            # Solicitar informações do swarm
            read -p "Token do Swarm: " token
            read -p "IP do node principal: " manager_ip
            
            docker swarm join --token "$token" "${manager_ip}:2377"
            ;;
        *)
            print_error "Tipo de instalação inválido: $type"
            return 1
            ;;
    esac
}