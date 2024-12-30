# src/commands/monitor.sh
#!/bin/bash

# Monitorar recursos do sistema
monitor_resources() {
    print_info "Monitorando recursos do sistema..."
    
    while true; do
        clear
        echo "=== Monitoramento de Sistema ==="
        echo "Data: $(date)"
        echo ""
        
        # CPU
        echo "=== CPU ==="
        top -bn1 | head -n 3
        echo ""
        
        # Memória
        echo "=== Memória ==="
        free -h
        echo ""
        
        # Disco
        echo "=== Disco ==="
        df -h /
        echo ""
        
        sleep ${MONITORING_INTERVAL:-5}
    done
}

# Monitorar containers
monitor_containers() {
    print_info "Monitorando containers..."
    
    while true; do
        clear
        echo "=== Containers Docker ==="
        echo "Data: $(date)"
        echo ""
        
        # Status dos containers
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo ""
        
        # Uso de recursos
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"
        echo ""
        
        sleep ${MONITORING_INTERVAL:-5}
    done
}

# Monitorar rede
monitor_network() {
    if ! command -v iftop &> /dev/null; then
        apt-get update && apt-get install -y iftop
    fi

    print_info "Monitorando tráfego de rede..."
    iftop -P
}

# Handler principal de monitoramento
handle_monitor() {
    local type=$1

    case $type in
        "resources")
            monitor_resources
            ;;
        "containers")
            monitor_containers
            ;;
        "network")
            monitor_network
            ;;
        *)
            print_error "Tipo de monitoramento inválido: $type"
            echo "Tipos disponíveis: resources, containers, network"
            return 1
            ;;
    esac
}