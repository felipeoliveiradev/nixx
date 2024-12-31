#!/bin/bash

# Encontrar o diretório real do script, mesmo quando executado através de um link simbólico
SCRIPT_PATH="$(readlink -f "$0")"
BASE_DIR="$(dirname "$SCRIPT_PATH")"

# Configurações globais
CONFIG_DIR="$HOME/.nixx-cli"
CONFIG_FILE="$CONFIG_DIR/config.sh"
DOCKER_COMPOSE_DIR="$CONFIG_DIR/compose"
BACKUP_DIR="$CONFIG_DIR/backups"
LOG_DIR="$CONFIG_DIR/logs"
LOG_FILE="$LOG_DIR/nixx-cli.log"
TEMPLATES_DIR="$BASE_DIR/src/templates"

# Importar utilitários primeiro (pois outros módulos dependem deles)
source "$BASE_DIR/src/utils/logger.sh"
source "$BASE_DIR/src/utils/system.sh"

# Importar comandos após os utilitários
source "$BASE_DIR/src/commands/install.sh"
source "$BASE_DIR/src/commands/service.sh"
source "$BASE_DIR/src/commands/ci.sh"
source "$BASE_DIR/src/commands/manage.sh"
source "$BASE_DIR/src/commands/list.sh"
source "$BASE_DIR/src/commands/runners.sh"
source "$BASE_DIR/src/commands/network.sh"
source "$BASE_DIR/src/commands/backup.sh"
source "$BASE_DIR/src/commands/monitor.sh"
source "$BASE_DIR/src/commands/config.sh"
source "$BASE_DIR/src/commands/diagnose.sh"

# Versão do CLI
VERSION="1.0.0"

# Configurações globais
CONFIG_DIR="$HOME/.nixx-cli"
CONFIG_FILE="$CONFIG_DIR/config.sh"
DOCKER_COMPOSE_DIR="$CONFIG_DIR/compose"
BACKUP_DIR="$CONFIG_DIR/backups"
LOG_DIR="$CONFIG_DIR/logs"
LOG_FILE="$LOG_DIR/nixx-cli.log"
TEMPLATES_DIR="$BASE_DIR/src/templates"

# Inicialização
setup_directories() {
    mkdir -p "$CONFIG_DIR" "$DOCKER_COMPOSE_DIR" "$BACKUP_DIR" "$LOG_DIR" "$TEMPLATES_DIR"
    touch "$LOG_FILE"

    # Criar arquivo de configuração se não existir
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << EOF
# Nixx CLI Configuration
VERSION="$VERSION"
DOCKER_REGISTRY=""
GITLAB_URL=""
GITHUB_TOKEN=""
DATADOG_API_KEY=""
PORTAINER_URL=""
BACKUP_RETENTION_DAYS=7
MONITORING_INTERVAL=5
EOF
        print_info "Arquivo de configuração criado em $CONFIG_FILE. Edite conforme necessário."
    fi
}

# Verificar se é root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        print_error "Por favor, execute como root (sudo)"
        exit 1
    fi
}

# Inicialização
setup_directories() {
    mkdir -p "$CONFIG_DIR" "$DOCKER_COMPOSE_DIR" "$BACKUP_DIR" "$LOG_DIR" "$TEMPLATES_DIR"
    touch "$LOG_FILE"
    
    # Criar arquivo de configuração se não existir
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << EOF
# Nixx CLI Configuration
VERSION="$VERSION"
DOCKER_REGISTRY=""
GITLAB_URL=""
GITHUB_TOKEN=""
DATADOG_API_KEY=""
PORTAINER_URL=""
BACKUP_RETENTION_DAYS=7
MONITORING_INTERVAL=5
EOF
    fi
}

# Verificar dependências
check_dependencies() {
    local deps=("docker" "curl" "netstat" "jq")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v $dep &> /dev/null; then
            missing+=($dep)
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        print_error "Dependências faltando: ${missing[*]}"
        print_info "Instalando dependências..."
        apt-get update
        apt-get install -y ${missing[@]}
    fi
}

# Verificar atualizações
check_updates() {
    local current_version=$VERSION
    # Aqui você pode implementar a lógica de verificação de atualizações
    # Por exemplo, fazendo uma requisição a um repositório git
    print_info "Verificando atualizações..."
}

# Tratamento de erros
trap 'error_handler $? $LINENO $BASH_LINENO "$BASH_COMMAND" $(printf "::%s" ${FUNCNAME[@]:-})' ERR

error_handler() {
    local exit_code=$1
    local line_no=$2
    local bash_lineno=$3
    local last_command=$4
    local func_trace=$5

    print_error "Erro no comando: $last_command"
    print_error "Código de saída: $exit_code"
    print_error "Linha: $line_no"
    print_error "Stack trace: $func_trace"
    
    log "ERROR" "Comando: $last_command | Código: $exit_code | Linha: $line_no | Stack: $func_trace"
}

show_help() {
    echo "Nixx CLI - Sistema de Gerenciamento Nixx"
    echo "Versão: 1.0.0"
    echo ""
    echo "Uso: nixx COMANDO [argumentos]"
    echo ""
    echo "Comandos de Sistema:"
    echo "  install main              Instalar node principal"
    echo "  install client           Instalar node cliente"
    echo "  system check             Verificar sistema"
    echo "  system update            Atualizar sistema"
    echo "  monitor                  Monitorar recursos"
    echo "  list [TYPE]              Listar recursos (ports|resources|services|runners|all)"
    echo ""
    echo "Gerenciamento de Serviços:"
    echo "  create SERVICE                       Criar serviço"
    echo "                  - gitlab             GitLab CE Server"
    echo "                  - portainer          Portainer CE"
    echo "                  - prometheus         Prometheus Monitoring"
    echo "                  - grafana            Grafana Dashboard"
    echo "                  - datadog            Datadog Agent"
    echo "                  - custom             Serviço personalizado"
    echo "  remove SERVICE          Remover serviço"
    echo "  status SERVICE          Verificar status do serviço"
    echo "  logs SERVICE [lines]    Ver logs do serviço"
    echo "  restart SERVICE         Reiniciar serviço"
    echo ""
    echo "CI/CD e Runners:"
    echo "  gitlab:"
    echo "    - ci TEMPLATE         Criar pipeline GitLab (node|docker|python)"
    echo "    - runner setup TOKEN URL [TAGS] [EXECUTOR]  Configurar GitLab Runner"
    echo "    - runner remove       Remover GitLab Runner"
    echo "    - runner list         Listar GitLab Runners"
    echo ""
    echo "  github:"
    echo "    - workflow TEMPLATE                       Criar GitHub Actions (node|docker)"
    echo "    - runner setup TOKEN URL [NAME] [LABELS]  Configurar GitHub Runner"
    echo "    - runner remove                           Remover GitHub Runner"
    echo "    - runner list                             Listar GitHub Runners"
    echo ""
    echo "  pipeline:"
    echo "    - create NAME STAGES                      Criar pipeline personalizada"
    echo "    - template list                           Listar templates disponíveis"
    echo ""
    echo "Redes:"
    echo "  network create NAME [driver]                Criar rede (default: overlay)"
    echo "  network remove NAME                         Remover rede"
    echo "  network list                                Listar redes"
    echo "  network inspect NAME                        Inspecionar rede"
    echo ""
    echo "Backup e Restore:"
    echo "  backup:"
    echo "    - create SERVICE          Criar backup"
    echo "    - restore SERVICE FILE    Restaurar backup"
    echo "    - list                    Listar backups"
    echo "    - clean                   Limpar backups antigos"
    echo ""
    echo "Monitoramento:"
    echo "  monitor resources          Monitorar recursos do sistema"
    echo "  monitor containers         Monitorar containers"
    echo "  monitor network            Monitorar tráfego de rede"
    echo "  ports list                 Listar portas em uso"
    echo "  ports check PORT           Verificar disponibilidade de porta"
    echo ""
    echo "Configurações:"
    echo "  config:"
    echo "    - set KEY VALUE         Definir configuração"
    echo "    - get KEY               Obter configuração"
    echo "    - list                  Listar configurações"
    echo "    - import FILE           Importar configurações"
    echo "    - export FILE           Exportar configurações"
    echo ""
    echo "Diagnóstico:"
    echo "  diagnose:"
    echo "    - system                Verificar sistema"
    echo "    - docker                Verificar Docker"
    echo "    - network               Verificar rede"
    echo "    - services              Verificar serviços"
    echo "    - all                   Verificar tudo"
    echo ""
    echo "Logs:"
    echo "  logs:"
    echo "    - show SERVICE [lines] Mostrar logs de serviço"
    echo "    - follow SERVICE       Seguir logs em tempo real"
    echo "    - export SERVICE FILE  Exportar logs para arquivo"
    echo "    - clean SERVICE        Limpar logs"
    echo ""
    echo "Manage:"
    echo "  manage:"
    echo "      kill-port PORT        - Finalizar processo em uma porta específica"
    echo "      kill-service SERVICE  - Finalizar todas as portas de um serviço"
    echo "      kill-containers       - Finalizar todos os containers"
    echo "      kill-services         - Finalizar todos os serviços"
    echo "      clean                 - Limpar tudo (containers, serviços, redes, volumes)"
    echo "Exemplos:"
    echo "  nixx install main                      # Instalar node principal"
    echo "  nixx create gitlab                     # Criar serviço GitLab"
    echo "  nixx gitlab runner setup TOKEN URL     # Configurar GitLab Runner"
    echo "  nixx monitor resources                 # Monitorar recursos"
    echo "  nixx backup create gitlab              # Criar backup do GitLab"
    echo ""
    echo "Para mais informações, visite: https://github.com/seu-usuario/nixx-cli"
}
# Função principal
main() {
    # Verificar root exceto para comandos de ajuda e versão
    case $1 in
        "help"|"--help"|"-h"|"version"|"-v"|"--version"|"")
            ;;
        *)
            check_root
            ;;
    esac

    setup_directories
    check_dependencies
    check_updates
    
    case $1 in
        "install")
            handle_install "${@:2}"
            ;;
        "create"|"remove"|"status"|"restart")
            if [ -z "$2" ]; then
                print_error "Serviço não especificado"
                show_help
            else
                handle_service "$@"
            fi
            ;;
        "gitlab"|"github")
            case $2 in
                "ci"|"workflow") 
                    handle_ci "$@" 
                    ;;
                "runner") 
                    handle_runners "${@:2}" 
                    ;;
                *) 
                    print_error "Comando inválido para $1"
                    show_help
                    ;;
            esac
            ;;
        "monitor")
            case $2 in
                "resources"|"containers"|"network") 
                    handle_monitor "${@:2}" 
                    ;;
                *) 
                    monitor_resources 
                    ;;
            esac
            ;;
        "list")
            handle_list "${@:2}"
            ;;
        "network")
            handle_network "${@:2}"
            ;;
        "backup")
            handle_backup "${@:2}"
            ;;
        "config")
            handle_config "${@:2}"
            ;;
        "diagnose")
            handle_diagnose "${@:2}"
            ;;
        "manage")
            handle_manage "${@:2}"
            ;;
        "logs")
            handle_logs "${@:2}"
            ;;
        "ports")
            handle_ports "${@:2}"
            ;;
        "pipeline")
            handle_pipeline "${@:2}"
            ;;
        "version"|"-v"|"--version")
            echo "Nixx CLI versão $VERSION"
            ;;
        "help"|"--help"|"-h"|"")
            show_help
            ;;
        *)
            print_error "Comando desconhecido: $1"
            show_help
            exit 1
            ;;
    esac
}

# Executar
main "$@"