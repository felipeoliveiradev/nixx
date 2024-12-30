# src/utils/system.sh
#!/bin/bash

# Verificar requerimentos
check_requirements() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker não está instalado"
        return 1
    fi

    if [ "$EUID" -ne 0 ]; then 
        print_error "Por favor, execute como root (sudo)"
        return 1
    fi

    return 0
}

# Detectar arquitetura
get_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l)
            echo "arm"
            ;;
        *)
            echo $arch
            ;;
    esac
}

# Verificar sistema
check_system() {
    # Verificar CPU
    local cpu_cores=$(nproc)
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
    print_info "CPU: $cpu_cores cores, Uso: $cpu_usage%"

    # Verificar memória
    local total_mem=$(free -h | awk '/^Mem:/ {print $2}')
    local used_mem=$(free -h | awk '/^Mem:/ {print $3}')
    print_info "Memória: $used_mem / $total_mem"

    # Verificar disco
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}')
    local disk_free=$(df -h / | awk 'NR==2 {print $4}')
    print_info "Disco: Uso: $disk_usage, Livre: $disk_free"

    # Verificar Docker
    local docker_version=$(docker version --format '{{.Server.Version}}')
    print_info "Docker versão: $docker_version"

    # Verificar Swarm
    local swarm_status=$(docker info --format '{{.Swarm.LocalNodeState}}')
    print_info "Swarm status: $swarm_status"
}

# Monitorar recursos
monitor_resources() {
    while true; do
        clear
        print_info "=== Monitor de Recursos ==="
        check_system
        
        print_info "\nContainers em execução:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        
        print_info "\nUso de recursos por container:"
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"
        
        sleep 5
    done
}

# Verificar porta em uso
check_port() {
    local port=$1
    if netstat -tuln | grep ":$port " > /dev/null; then
        return 0
    else
        return 1
    fi
}

# Verificar serviço
check_service() {
    local service=$1
    if docker service ls --format "{{.Name}}" | grep -q "^$service$"; then
        return 0
    else
        return 1
    fi
}

# Verificar container
check_container() {
    local container=$1
    if docker ps -q -f name=$container > /dev/null; then
        return 0
    else
        return 1
    fi
}