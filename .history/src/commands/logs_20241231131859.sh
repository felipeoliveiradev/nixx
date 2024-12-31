# src/commands/logs.sh
#!/bin/bash

# Mostrar logs de um serviço
show_logs() {
    local service=$1
    local lines=${2:-100}  # número de linhas (padrão: 100)
    local follow=${3:-false}  # seguir logs em tempo real

    print_info "Obtendo logs do serviço: $service"

    # Verificar se o serviço existe
    if ! docker service ps $service >/dev/null 2>&1; then
        print_error "Serviço não encontrado: $service"
        return 1
    }

    if [ "$follow" = "true" ]; then
        docker service logs --follow $service
    else
        docker service logs --tail $lines $service
    fi
}

# Exportar logs para arquivo
export_logs() {
    local service=$1
    local output_file="$LOG_DIR/${service}_$(date +%Y%m%d_%H%M%S).log"

    print_info "Exportando logs do serviço $service para $output_file"

    # Verificar se o serviço existe
    if ! docker service ps $service >/dev/null 2>&1; then
        print_error "Serviço não encontrado: $service"
        return 1
    }

    docker service logs $service > "$output_file"
    print_success "Logs exportados para: $output_file"
}

# Limpar logs de um serviço
clean_logs() {
    local service=$1

    print_info "Limpando logs do serviço: $service"

    # Verificar se o serviço existe
    if ! docker service ps $service >/dev/null 2>&1; then
        print_error "Serviço não encontrado: $service"
        return 1
    }

    docker service update --force $service
    print_success "Logs do serviço $service foram limpos"
}

# Handler principal de logs
handle_logs() {
    local action=$1
    shift

    case $action in
        "show")
            if [ -z "$1" ]; then
                print_error "Serviço não especificado"
                return 1
            fi
            show_logs "$1" "${2:-100}" false
            ;;
        "follow")
            if [ -z "$1" ]; then
                print_error "Serviço não especificado"
                return 1
            fi
            show_logs "$1" "all" true
            ;;
        "export")
            if [ -z "$1" ]; then
                print_error "Serviço não especificado"
                return 1
            fi
            export_logs "$1"
            ;;
        "clean")
            if [ -z "$1" ]; then
                print_error "Serviço não especificado"
                return 1
            fi
            clean_logs "$1"
            ;;
        *)
            print_error "Ação desconhecida: $action"
            echo "Ações disponíveis:"
            echo "  show SERVICE [LINES]  - Mostrar logs (padrão: últimas 100 linhas)"
            echo "  follow SERVICE        - Seguir logs em tempo real"
            echo "  export SERVICE        - Exportar logs para arquivo"
            echo "  clean SERVICE         - Limpar logs do serviço"
            return 1
            ;;
    esac
}