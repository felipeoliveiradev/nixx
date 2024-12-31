# src/commands/service.sh
#!/bin/bash

# Criar serviço
create_service() {
    local name=$1
    local arch=$(get_arch)
    
    case $name in
        "gitlab")
            if [ "$arch" = "arm64" ]; then
                image="yrzr/gitlab-ce-arm64v8:latest"
            else
                image="gitlab/gitlab-ce:latest"
            fi
            
            print_info "Criando GitLab..."
            docker service create \
                --name gitlab \
                --publish 8090:80 \
                --publish 443:443 \
                --publish 22:22 \
                --mount source=gitlab_config,target=/etc/gitlab \
                --mount source=gitlab_logs,target=/var/log/gitlab \
                --mount source=gitlab_data,target=/var/opt/gitlab \
                --network monitoring \
                --env GITLAB_ROOT_PASSWORD=password123 \
                --env GITLAB_HOST=http://localhost \
                --env GITLAB_PORT=8090 \
                $image
            ;;
            
        "portainer")
            print_info "Criando Portainer..."
            docker volume create portainer_data
            docker run -d \
                -p 9000:9000 \
                --name portainer \
                --restart always \
                -v /var/run/docker.sock:/var/run/docker.sock \
                -v portainer_data:/data \
                portainer/portainer-ce:latest
            ;;
        "prometheus")
            print_info "Criando Prometheus..."
            
            # Criar diretório de configuração
            mkdir -p "$CONFIG_DIR/prometheus"
            
            # Copiar arquivo de configuração
            cp "$BASE_DIR/src/services/prometheus.yml" "$CONFIG_DIR/prometheus/prometheus.yml"
            
            # Criar volume se não existir
            docker volume create prometheus_data || true
            
            # Remover serviço antigo se existir
            docker service rm prometheus 2>/dev/null || true
            sleep 5
            
            # Criar serviço com configurações corretas
            docker service create \
                --name prometheus \
                --publish 9090:9090 \
                --mount type=bind,source=$CONFIG_DIR/prometheus/prometheus.yml,target=/etc/prometheus/prometheus.yml \
                --mount type=volume,source=prometheus_data,target=/prometheus \
                --network monitoring \
                --replicas 1 \
                --constraint 'node.role==manager' \
                prom/prometheus:latest \
                --config.file=/etc/prometheus/prometheus.yml \
                --storage.tsdb.path=/prometheus \
                --web.console.libraries=/usr/share/prometheus/console_libraries \
                --web.console.templates=/usr/share/prometheus/consoles
            
            print_success "Prometheus criado com sucesso"
            ;;
            
        "grafana")
            print_info "Criando Grafana..."
            docker service create \
                --name grafana \
                --publish 3000:3000 \
                --mount source=grafana_data,target=/var/lib/grafana \
                --network monitoring \
                --env GF_SECURITY_ADMIN_PASSWORD=admin \
                grafana/grafana:latest
            ;;
            
        "custom")
            create_custom_service
            ;;
            
        *)
            print_error "Serviço desconhecido: $name"
            return 1
            ;;
    esac
}

# Criar serviço customizado
create_custom_service() {
    read -p "Nome do serviço: " name
    read -p "Imagem Docker: " image
    read -p "Portas (ex: 8080:80,443:443): " ports
    read -p "Volumes (ex: data:/data,/host:/container): " volumes
    read -p "Variáveis de ambiente (ex: KEY=value,DEBUG=1): " env_vars
    
    local cmd="docker service create --name $name --network monitoring"
    
    # Adicionar portas
    if [ ! -z "$ports" ]; then
        IFS=',' read -ra PORT_ARRAY <<< "$ports"
        for port in "${PORT_ARRAY[@]}"; do
            cmd="$cmd --publish $port"
        done
    fi
    
    # Adicionar volumes
    if [ ! -z "$volumes" ]; then
        IFS=',' read -ra VOL_ARRAY <<< "$volumes"
        for vol in "${VOL_ARRAY[@]}"; do
            cmd="$cmd --mount source=${vol%%:*},target=${vol#*:}"
        done
    fi
    
    # Adicionar variáveis de ambiente
    if [ ! -z "$env_vars" ]; then
        IFS=',' read -ra ENV_ARRAY <<< "$env_vars"
        for env in "${ENV_ARRAY[@]}"; do
            cmd="$cmd --env $env"
        done
    fi
    
    cmd="$cmd $image"
    print_info "Criando serviço customizado..."
    eval $cmd
}

# Remover serviço
remove_service() {
    local name=$1
    
    if [ "$name" = "all" ]; then
        print_info "Removendo todos os serviços..."
        docker service rm $(docker service ls -q)
        return
    fi
    
    if ! check_service "$name"; then
        print_error "Serviço não encontrado: $name"
        return 1
    fi
    
    print_info "Removendo serviço: $name"
    docker service rm "$name"
    
    # Remover volumes associados
    case $name in
        "gitlab")
            docker volume rm gitlab_config gitlab_logs gitlab_data
            ;;
        "portainer")
            docker volume rm portainer_data
            ;;
        "prometheus")
            docker volume rm prometheus_data
            ;;
        "grafana")
            docker volume rm grafana_data
            ;;
    esac
}

# Verificar logs
check_logs() {
    local service=$1
    local lines=${2:-100}
    
    if ! check_service "$service"; then
        print_error "Serviço não encontrado: $service"
        return 1
    fi
    
    print_info "Últimas $lines linhas de log do serviço $service:"
    docker service logs --tail "$lines" "$service"
}

# Handler principal de serviços
handle_service() {
    local action=$1
    local service=$2
    
    case $action in
        "create")
            create_service "$service"
            ;;
        "remove")
            remove_service "$service"
            ;;
        "logs")
            check_logs "$service" "${3:-100}"
            ;;
        *)
            print_error "Ação desconhecida: $action"
            return 1
            ;;
    esac
}