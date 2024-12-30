# src/commands/list.sh
#!/bin/bash

# Listar portas em uso
list_ports() {
    print_info "Portas em uso por serviços Docker:"
    echo -e "\nCONTAINER ID        NAME                PORT                 TARGET"
    docker ps --format "{{.ID}}\t{{.Names}}\t{{.Ports}}" | grep -v "^$" | while read -r line; do
        container_id=$(echo "$line" | cut -f1)
        name=$(echo "$line" | cut -f2)
        ports=$(echo "$line" | cut -f3)
        if [ ! -z "$ports" ]; then
            echo "$container_id        $name        $ports"
        fi
    done

    print_info "\nPortas em uso no sistema:"
    netstat -tuln | grep "LISTEN"
}

# Listar recursos
list_resources() {
    print_info "=== Recursos do Sistema ==="
    
    # CPU
    print_info "\nCPU:"
    top -bn1 | grep "Cpu(s)" | awk '{print "Uso: " $2 "%"}'
    echo "Cores: $(nproc)"
    
    # Memória
    print_info "\nMemória:"
    free -h
    
    # Disco
    print_info "\nDisco:"
    df -h /
    
    # Docker
    print_info "\nRecursos Docker:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
}

# Listar serviços
list_services() {
    print_info "=== Serviços Docker ==="
    
    # Serviços Swarm
    print_info "\nServiços Swarm:"
    docker service ls 2>/dev/null || echo "Swarm não está ativo"

    # Containers
    print_info "\nContainers em execução:"
    docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}"

    # Volumes
    print_info "\nVolumes:"
    docker volume ls

    # Networks
    print_info "\nRedes:"
    docker network ls
}

# Listar runners
list_runners() {
    print_info "=== Runners ==="
    
    # GitLab Runners
    if command -v gitlab-runner &> /dev/null; then
        print_info "\nGitLab Runners:"
        gitlab-runner list 2>/dev/null || echo "Nenhum GitLab Runner encontrado"
    fi

    # GitHub Actions Runners
    if [ -d "/opt/actions-runner" ]; then
        print_info "\nGitHub Actions Runners:"
        ls -l /opt/actions-runner/runs 2>/dev/null || echo "Nenhum GitHub Runner encontrado"
    fi
}

# Listar todos os recursos
list_all() {
    list_services
    echo -e "\n"
    list_ports
    echo -e "\n"
    list_resources
    echo -e "\n"
    list_runners
}

# Handler principal de listagem
handle_list() {
    local type=${1:-"all"}
    
    case $type in
        "ports")
            list_ports
            ;;
        "resources")
            list_resources
            ;;
        "services")
            list_services
            ;;
        "runners")
            list_runners
            ;;
        "all")
            list_all
            ;;
        *)
            print_error "Tipo de listagem inválido: $type"
            echo "Tipos disponíveis: ports, resources, services, runners, all"
            return 1
            ;;
    esac
}