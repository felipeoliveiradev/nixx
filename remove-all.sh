#!/bin/bash

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Função para imprimir mensagens
print_message() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar se é root
if [ "$EUID" -ne 0 ]; then 
    print_error "Por favor, execute como root (sudo)"
    exit 1
fi

# Remover todos os stacks
remove_stacks() {
    print_message "Removendo stacks Docker..."
    
    docker stack rm portainer || true
    print_message "Portainer removido"
    
    docker stack rm monitoring || true
    print_message "Prometheus e Grafana removidos"
    
    docker stack rm gitlab-server || true
    print_message "GitLab removido"
    
    docker stack rm gitlab || true
    print_message "GitLab Runner removido"
    
    # Aguardar remoção dos serviços
    print_message "Aguardando remoção dos serviços..."
    sleep 30
}

# Remover volumes
remove_volumes() {
    print_message "Removendo volumes..."
    
    docker volume rm portainer_data || true
    docker volume rm prometheus_data || true
    docker volume rm grafana_data || true
    docker volume rm gitlab-server_gitlab_config || true
    docker volume rm gitlab-server_gitlab_logs || true
    docker volume rm gitlab-server_gitlab_data || true
}

# Remover networks
remove_networks() {
    print_message "Removendo networks..."
    docker network rm monitoring || true
}

# Limpar diretórios
clean_directories() {
    print_message "Removendo diretórios..."
    rm -rf devops/{app,configs,gitlab,gitlab-runner,prometheus,portainer}
}

# Função principal
main() {
    print_message "Iniciando remoção completa da infraestrutura..."
    
    read -p "Isso irá remover TODOS os serviços, volumes e configurações. Continuar? (s/n) " confirm
    if [ "$confirm" != "s" ]; then
        print_error "Operação cancelada"
        exit 1
    fi
    
    remove_stacks
    remove_volumes
    remove_networks
    clean_directories
    
    print_success "Remoção completa finalizada!"
    print_message "Para remover o Docker e outras dependências, execute:"
    print_message "apt-get remove docker-ce docker-ce-cli containerd.io docker-compose-plugin"
}

# Executar
main