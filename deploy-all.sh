#!/bin/bash

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configurações padrão
HOST_IP=$(hostname -I | awk '{print $1}')
PORTAINER_PORT=9000
GRAFANA_PORT=3000
PROMETHEUS_PORT=9090
GITLAB_PORT=80
GITLAB_SSH_PORT=22
GITLAB_HTTPS_PORT=443

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

# Solicitar configurações do usuário
get_config() {
    read -p "Host IP [$HOST_IP]: " input
    HOST_IP=${input:-$HOST_IP}

    read -p "Portainer Port [$PORTAINER_PORT]: " input
    PORTAINER_PORT=${input:-$PORTAINER_PORT}

    read -p "Grafana Port [$GRAFANA_PORT]: " input
    GRAFANA_PORT=${input:-$GRAFANA_PORT}

    read -p "Prometheus Port [$PROMETHEUS_PORT]: " input
    PROMETHEUS_PORT=${input:-$PROMETHEUS_PORT}

    read -p "GitLab HTTP Port [$GITLAB_PORT]: " input
    GITLAB_PORT=${input:-$GITLAB_PORT}

    print_message "Configurações definidas:"
    echo "Host IP: $HOST_IP"
    echo "Portainer: $HOST_IP:$PORTAINER_PORT"
    echo "Grafana: $HOST_IP:$GRAFANA_PORT"
    echo "Prometheus: $HOST_IP:$PROMETHEUS_PORT"
    echo "GitLab: $HOST_IP:$GITLAB_PORT"

    read -p "Confirmar configurações? (s/n) " confirm
    if [ "$confirm" != "s" ]; then
        print_error "Configuração cancelada"
        exit 1
    fi
}

setup_directories() {
    print_message "Criando estrutura de diretórios..."
    
    # Criar estrutura base
    mkdir -p devops/{app,configs/{nginx,php},gitlab,gitlab-runner,prometheus,portainer}
    chmod -R devops

    # Criar arquivos de configuração padrão do Nginx
    cat << 'EOF' > devops/configs/nginx/default.conf
server {
    listen 80;
    root /var/www/html/public;
    index index.php;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass app:9000;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF

    # Criar arquivo prometheus.yml
    cat << 'EOF' > devops/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    dns_sd_configs:
      - names: ['tasks.node-exporter']
        type: 'A'
        port: 9100

  - job_name: 'cadvisor'
    dns_sd_configs:
      - names: ['tasks.cadvisor']
        type: 'A'
        port: 8080
EOF

    print_message "Estrutura de diretórios e arquivos de configuração criados"
}

# Deploy Portainer
deploy_portainer() {
    print_message "Deployando Portainer..."
    cd devops/portainer
    envsubst < docker-compose.portainer.yml | docker stack deploy -c - portainer
}

# Deploy Prometheus e Grafana
deploy_monitoring() {
    print_message "Deployando Prometheus e Grafana..."
    pwd
    cd ../../
    cd devops/prometheus
    envsubst < docker-compose.monitoring.yml | docker stack deploy -c - monitoring
}

# Deploy GitLab
deploy_gitlab() {
    print_message "Deployando GitLab..."
    cd ../../
    cd devops/gitlab
    envsubst < docker-compose.gitlab-server.yml | docker stack deploy -c - gitlab-server
}

# Deploy GitLab Runner
deploy_runner() {
    print_message "Deployando GitLab Runner..."
    cd ../../
    cd devops/gitlab-runner
    envsubst < docker-compose.gitlab.yml | docker stack deploy -c - gitlab
}

# Criar arquivos de configuração
create_configs() {
    print_message "Criando arquivos de configuração..."

    # Portainer
    cat << EOF > devops/portainer/docker-compose.portainer.yml
version: '3.8'
services:
  portainer:
    image: portainer/portainer-ce:latest
    ports:
      - "${PORTAINER_PORT}:9000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    deploy:
      placement:
        constraints: [node.role == manager]
volumes:
  portainer_data:
networks:
  default:
    external: true
    name: monitoring
EOF

    # Prometheus
    cat << EOF > devops/prometheus/docker-compose.monitoring.yml
version: '3.8'
services:
  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    ports:
      - "${PROMETHEUS_PORT}:9090"
    deploy:
      placement:
        constraints: [node.role == manager]

  grafana:
    image: grafana/grafana:latest
    volumes:
      - grafana_data:/var/lib/grafana
    ports:
      - "${GRAFANA_PORT}:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_SERVER_ROOT_URL=http://${HOST_IP}:${GRAFANA_PORT}
    deploy:
      placement:
        constraints: [node.role == manager]

volumes:
  prometheus_data:
  grafana_data:

networks:
  default:
    external: true
    name: monitoring
EOF

    # GitLab
    cat << EOF > devops/gitlab/docker-compose.gitlab-server.yml
version: '3.8'
services:
  gitlab:
    image: yrzr/gitlab-ce-arm64v8:latest
    ports:
      - "${GITLAB_PORT}:80"
      - "${GITLAB_HTTPS_PORT}:443"
      - "${GITLAB_SSH_PORT}:22"
    volumes:
      - gitlab_config:/etc/gitlab
      - gitlab_logs:/var/log/gitlab
      - gitlab_data:/var/opt/gitlab
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'http://${HOST_IP}'
    deploy:
      placement:
        constraints: [node.role == manager]

volumes:
  gitlab_config:
  gitlab_logs:
  gitlab_data:

networks:
  default:
    external: true
    name: monitoring
EOF

}

# Função principal
main() {
    print_message "Iniciando deploy completo..."

    # Obter configurações
    get_config

    # Criar estrutura
    setup_directories
    create_configs

    # Criar rede se não existir
    docker network create -d overlay monitoring || true

    # Deploy dos serviços
    deploy_portainer
    sleep 10
    deploy_monitoring
    sleep 20
    deploy_gitlab
    sleep 10
    deploy_runner

    print_success "Deploy completo!"
    print_message "Portainer: http://${HOST_IP}:${PORTAINER_PORT}"
    print_message "Grafana: http://${HOST_IP}:${GRAFANA_PORT}"
    print_message "GitLab: http://${HOST_IP}:${GITLAB_PORT}"
    print_message "Prometheus: http://${HOST_IP}:${PROMETHEUS_PORT}"
}

# Executar
main