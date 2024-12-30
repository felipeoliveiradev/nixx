# src/commands/network.sh
#!/bin/bash

# Criar rede
create_network() {
    local name=$1
    local driver=${2:-overlay}
    
    print_info "Criando rede $name com driver $driver..."
    
    if docker network ls | grep -q "$name"; then
        print_warning "Rede $name já existe"
        return 0
    fi
    
    docker network create --driver "$driver" "$name"
    print_success "Rede $name criada com sucesso"
}

# Remover rede
remove_network() {
    local name=$1
    
    print_info "Removendo rede $name..."
    
    if ! docker network ls | grep -q "$name"; then
        print_error "Rede $name não encontrada"
        return 1
    fi
    
    docker network rm "$name"
    print_success "Rede $name removida com sucesso"
}

# Listar redes
list_networks() {
    print_info "Redes disponíveis:"
    docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}"
}

# Inspecionar rede
inspect_network() {
    local name=$1
    
    if ! docker network ls | grep -q "$name"; then
        print_error "Rede $name não encontrada"
        return 1
    fi
    
    print_info "Detalhes da rede $name:"
    docker network inspect "$name"
}

# Handler principal de rede
handle_network() {
    local action=$1
    local name=$2
    
    case $action in
        "create")
            create_network "$name"
            ;;
        "remove")
            remove_network "$name"
            ;;
        "list")
            list_networks
            ;;
        "inspect")
            inspect_network "$name"
            ;;
        *)
            print_error "Ação de rede inválida: $action"
            return 1
            ;;
    esac
}