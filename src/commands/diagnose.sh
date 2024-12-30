# src/commands/diagnose.sh
#!/bin/bash

# Verificar sistema
diagnose_system() {
    print_info "Verificando sistema..."

    # Verificar CPU
    echo "=== CPU ==="
    echo "Modelo: $(cat /proc/cpuinfo | grep 'model name' | head -n1 | cut -d':' -f2)"
    echo "Cores: $(nproc)"
    echo "Carga: $(uptime | awk -F'average:' '{print $2}')"
    echo ""

    # Verificar memória
    echo "=== Memória ==="
    free -h
    echo ""

    # Verificar disco
    echo "=== Disco ==="
    df -h
    echo ""

    # Verificar sistema operacional
    echo "=== Sistema Operacional ==="
    cat /etc/os-release
    echo ""

    # Verificar kernel
    echo "=== Kernel ==="
    uname -a
    echo ""
}

# Verificar Docker
diagnose_docker() {
    print_info "Verificando Docker..."

    # Versão do Docker
    echo "=== Versão do Docker ==="
    docker version
    echo ""

    # Info do Docker
    echo "=== Informações do Docker ==="
    docker info
    echo ""

    # Status do Swarm
    echo "=== Status do Swarm ==="
    docker node ls 2>/dev/null || echo "Swarm não inicializado"
    echo ""

    # Containers em execução
    echo "=== Containers em Execução ==="
    docker ps
    echo ""

    # Uso de recursos
    echo "=== Uso de Recursos por Container ==="
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
    echo ""
}

# Verificar rede
diagnose_network() {
    print_info "Verificando rede..."

    # Interfaces de rede
    echo "=== Interfaces de Rede ==="
    ip addr
    echo ""

    # Redes Docker
    echo "=== Redes Docker ==="
    docker network ls
    echo ""

    # Portas em uso
    echo "=== Portas em Uso ==="
    netstat -tuln
    echo ""

    # Conectividade
    echo "=== Teste de Conectividade ==="
    ping -c 4 8.8.8.8
    echo ""
}

# Verificar serviços
diagnose_services() {
    print_info "Verificando serviços..."

    # Serviços Docker
    echo "=== Serviços Docker ==="
    docker service ls
    echo ""

    # Status dos serviços
    for service in $(docker service ls --format "{{.Name}}"); do
        echo "=== Status do Serviço: $service ==="
        docker service ps $service
        echo ""
    done

    # Volumes
    echo "=== Volumes Docker ==="
    docker volume ls
    echo ""
}

# Exportar diagnóstico
export_diagnose() {
    local output_file="$BACKUP_DIR/diagnose_$(date +%Y%m%d_%H%M%S).txt"

    {
        echo "=== Diagnóstico do Sistema ==="
        echo "Data: $(date)"
        echo ""
        
        diagnose_system
        diagnose_docker
        diagnose_network
        diagnose_services
        
    } > "$output_file"

    print_success "Diagnóstico exportado para: $output_file"
}

# Handler principal de diagnóstico
handle_diagnose() {
    local type=$1

    case $type in
        "system")
            diagnose_system
            ;;
        "docker")
            diagnose_docker
            ;;
        "network")
            diagnose_network
            ;;
        "services")
            diagnose_services
            ;;
        "export")
            export_diagnose
            ;;
        "all")
            diagnose_system
            diagnose_docker
            diagnose_network
            diagnose_services
            ;;
        *)
            print_error "Tipo de diagnóstico inválido: $type"
            echo "Tipos disponíveis: system, docker, network, services, all, export"
            return 1
            ;;
    esac
}