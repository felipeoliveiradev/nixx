# src/commands/service.sh
#!/bin/bash

fix_gitlab_deployment() {
    local timeout=${1:-300}  # 5 minutos de timeout padrão
    
    print_info "Preparando ambiente para GitLab..."

    # 1. Limpar recursos antigos
    print_info "Limpando recursos antigos..."
    docker service rm gitlab || true
    docker volume rm gitlab_config gitlab_logs gitlab_data || true
    sleep 5

    # 2. Verificar e corrigir Redis
    print_info "Verificando Redis..."
    docker run --rm --network monitoring redis:latest redis-cli -h redis ping || {
        print_warning "Problema com Redis detectado, recriando..."
        docker service rm redis || true
        docker service create \
            --name redis \
            --network monitoring \
            --mount type=volume,source=redis_data,target=/data \
            redis:latest --appendonly yes
    }

    # 3. Verificar e aumentar limites do sistema
    print_info "Configurando limites do sistema..."
    sysctl -w vm.max_map_count=262144 || true
    sysctl -w fs.file-max=524288 || true

    # 4. Criar volumes com verificação
    print_info "Criando volumes..."
    for volume in gitlab_config gitlab_logs gitlab_data; do
        docker volume create $volume
        if [ $? -ne 0 ]; then
            print_error "Falha ao criar volume $volume"
            return 1
        fi
    done

    # 5. Criar serviço GitLab com configurações otimizadas
    print_info "Criando serviço GitLab..."
    docker service create \
        --name gitlab \
        --publish 80:80 \
        --publish 443:443 \
        --publish 22:22 \
        --mount source=gitlab_config,target=/etc/gitlab \
        --mount source=gitlab_logs,target=/var/log/gitlab \
        --mount source=gitlab_data,target=/var/opt/gitlab \
        --network monitoring \
        --env GITLAB_ROOT_PASSWORD=password123 \
        --env GITLAB_HOST=http://192.168.200.211 \
        --env GITLAB_PORT=80 \
        --env GITLAB_SHARED_RUNNERS_REGISTRATION_TOKEN=token \
        --env 'GITLAB_OMNIBUS_CONFIG=postgresql["shared_buffers"] = "256MB"; postgresql["max_worker_processes"] = 8; redis["tcp_timeout"] = "60"; redis["io_threads"] = "4"; unicorn["worker_timeout"] = 60; unicorn["worker_processes"] = 4;' \
        --limit-cpu 2 \
        --limit-memory 4GB \
        --update-parallelism 1 \
        --update-delay 10s \
        --update-failure-action rollback \
        --restart-condition any \
        --restart-delay 5s \
        --restart-max-attempts 3 \
        $image

    # 6. Aguardar e verificar status
    print_info "Aguardando GitLab iniciar (pode levar alguns minutos)..."
    local count=0
    while [ $count -lt $timeout ]; do
        if curl -s http://localhost:8090/-/health > /dev/null; then
            print_success "GitLab iniciado com sucesso!"
            return 0
        fi
        sleep 10
        count=$((count + 10))
        print_info "Ainda aguardando... (${count}s/${timeout}s)"
    done

    print_error "Timeout ao aguardar GitLab iniciar"
    return 1
}
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
            fix_gitlab_deployment
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
        "datadog")
            print_info "Criando Datadog Agent..."
            
            # Verificar se a API key está configurada
            if [ -z "$DATADOG_API_KEY" ]; then
                print_error "API Key do Datadog não configurada"
                print_info "Use: nixx config set DATADOG_API_KEY sua_api_key"
                return 1
            fi
            
            # Remover serviço antigo se existir
            docker service rm datadog-agent 2>/dev/null || true
            sleep 5
            
            # Criar serviço Datadog
            docker service create \
                --name datadog-agent \
                --mode global \
                --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
                --mount type=bind,source=/proc/,target=/host/proc/,readonly \
                --mount type=bind,source=/sys/fs/cgroup/,target=/host/sys/fs/cgroup,readonly \
                --mount type=bind,source=/var/lib/docker/containers,target=/var/lib/docker/containers,readonly \
                --network monitoring \
                -e DD_API_KEY=${DATADOG_API_KEY} \
                -e DD_SITE="datadoghq.com" \
                -e DD_DOCKER_LABELS_AS_TAGS=true \
                -e DD_LOGS_ENABLED=true \
                -e DD_LOGS_CONFIG_CONTAINER_COLLECT_ALL=true \
                -e DD_CONTAINER_EXCLUDE="name:datadog-agent" \
                -e DD_PROCESS_AGENT_ENABLED=true \
                datadog/agent:latest
            
            print_success "Datadog Agent criado com sucesso"
            
            # Instruções adicionais
            print_info "Para visualizar os logs:"
            print_info "nixx logs datadog-agent"
            print_info "Para verificar o status:"
            print_info "nixx status datadog-agent"
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