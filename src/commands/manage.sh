# src/commands/manage.sh
#!/bin/bash

# Finalizar processo em uma porta específica
kill_port() {
    local port=$1
    print_info "Procurando processo na porta $port..."
    
    # Encontrar PID do processo usando a porta
    local pid=$(sudo lsof -t -i:$port)
    
    if [ -z "$pid" ]; then
        print_warning "Nenhum processo encontrado na porta $port"
        return 0
    fi
    
    print_info "Encontrado processo (PID: $pid) na porta $port"
    sudo kill -9 $pid
    print_success "Processo finalizado na porta $port"
}

# Finalizar todas as portas de um serviço
kill_service_ports() {
    local service=$1
    print_info "Finalizando todas as portas do serviço $service..."
    
    # Obter todas as portas do serviço
    local ports=$(docker port $service 2>/dev/null | cut -d ':' -f2)
    
    if [ -z "$ports" ]; then
        print_warning "Nenhuma porta encontrada para o serviço $service"
        return 0
    fi
    
    for port in $ports; do
        kill_port $port
    done
    
    print_success "Todas as portas do serviço $service foram finalizadas"
}

# Finalizar todos os containers
kill_all_containers() {
    print_info "Finalizando todos os containers..."
    
    # Parar todos os containers
    docker stop $(docker ps -q) 2>/dev/null || true
    
    # Remover todos os containers parados
    docker rm $(docker ps -a -q) 2>/dev/null || true
    
    print_success "Todos os containers foram finalizados"
}

# Finalizar todos os serviços do swarm
kill_all_services() {
    print_info "Finalizando todos os serviços do swarm..."
    
    # Remover todos os serviços
    docker service rm $(docker service ls -q) 2>/dev/null || true
    
    print_success "Todos os serviços foram finalizados"
}

# Limpar tudo (containers, serviços, redes e volumes não utilizados)
clean_all() {
    print_info "Iniciando limpeza completa..."
    
    # Parar e remover todos os containers
    kill_all_containers
    
    # Remover todos os serviços
    kill_all_services
    
    # Remover todas as redes não utilizadas
    print_info "Removendo redes não utilizadas..."
    docker network prune -f
    
    # Remover todos os volumes não utilizados
    print_info "Removendo volumes não utilizados..."
    docker volume prune -f
    
    # Remover imagens não utilizadas
    print_info "Removendo imagens não utilizadas..."
    docker image prune -a -f
    
    print_success "Limpeza completa finalizada"
}

# Handler principal
handle_manage() {
    local action=$1
    shift
    
    case $action in
        "kill-port")
            if [ -z "$1" ]; then
                print_error "Porta não especificada"
                return 1
            fi
            kill_port "$1"
            ;;
        "kill-service")
            if [ -z "$1" ]; then
                print_error "Serviço não especificado"
                return 1
            fi
            kill_service_ports "$1"
            ;;
        "kill-containers")
            kill_all_containers
            ;;
        "kill-services")
            kill_all_services
            ;;
        "clean")
            clean_all
            ;;
        *)
            print_error "Ação desconhecida: $action"
            echo "Ações disponíveis:"
            echo "  kill-port PORT        - Finalizar processo em uma porta específica"
            echo "  kill-service SERVICE  - Finalizar todas as portas de um serviço"
            echo "  kill-containers       - Finalizar todos os containers"
            echo "  kill-services         - Finalizar todos os serviços"
            echo "  clean                 - Limpar tudo (containers, serviços, redes, volumes)"
            return 1
            ;;
    esac
}