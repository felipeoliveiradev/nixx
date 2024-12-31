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
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                        Nixx CLI - Sistema DevOps                           ║"
    echo "║                              Versão: 1.0.0                                 ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "🔧 INSTALAÇÃO E SISTEMA"
    echo "  nixx install:"
    echo "    main                    → Instalar node principal (Docker + Swarm)"
    echo "    client                  → Instalar node cliente e conectar ao Swarm"
    echo ""
    echo "  nixx system:"
    echo "    check                   → Verificar recursos e requisitos do sistema"
    echo "    update                  → Atualizar componentes do sistema"
    echo ""
    echo "🐳 SERVIÇOS"
    echo "  nixx create [SERVIÇO]     → Criar e iniciar serviços"
    echo "    Serviços disponíveis:"
    echo "    - gitlab                → GitLab CE Server (Git + CI/CD)"
    echo "    - portainer             → UI de gerenciamento Docker"
    echo "    - prometheus            → Monitoramento de métricas"
    echo "    - grafana               → Visualização de dados"
    echo "    - datadog               → Monitoramento avançado"
    echo "    - custom                → Serviço personalizado"
    echo ""
    echo "  nixx service:"
    echo "    remove [SERVIÇO]        → Remover serviço específico"
    echo "    status [SERVIÇO]        → Verificar status do serviço"
    echo "    restart [SERVIÇO]       → Reiniciar serviço"
    echo ""
    echo "📊 MONITORAMENTO"
    echo "  nixx monitor:"
    echo "    resources               → CPU, memória e disco"
    echo "    containers              → Status dos containers"
    echo "    network                 → Tráfego de rede"
    echo ""
    echo "  nixx logs:"
    echo "    show [SERVIÇO] [LINHAS] → Mostrar logs do serviço"
    echo "    follow [SERVIÇO]        → Acompanhar logs em tempo real"
    echo "    export [SERVIÇO]        → Salvar logs em arquivo"
    echo "    clean [SERVIÇO]         → Limpar logs do serviço"
    echo ""
    echo "🔑 CREDENCIAIS"
    echo "  nixx credentials:"
    echo "    show [SERVIÇO]          → Mostrar credenciais do serviço"
    echo "    reset [SERVIÇO] [SENHA] → Redefinir senha do serviço"
    echo "    reset all same          → Mesma senha para todos os serviços"
    echo ""
    echo "🔄 CI/CD"
    echo "  nixx gitlab:"
    echo "    ci [TEMPLATE]           → Criar pipeline GitLab (node|docker|python)"
    echo "    runner setup            → Configurar GitLab Runner"
    echo "    runner remove           → Remover Runner"
    echo "    runner list             → Listar Runners"
    echo ""
    echo "  nixx github:"
    echo "    workflow [TEMPLATE]     → Configurar GitHub Actions"
    echo "    runner setup            → Configurar GitHub Runner"
    echo ""
    echo "🌐 REDE"
    echo "  nixx network:"
    echo "    create [NOME] [DRIVER]  → Criar rede (default: overlay)"
    echo "    remove [NOME]           → Remover rede"
    echo "    list                    → Listar redes"
    echo "    inspect [NOME]          → Detalhes da rede"
    echo ""
    echo "  nixx ports:"
    echo "    list                    → Listar portas em uso"
    echo "    check [PORTA]           → Verificar disponibilidade"
    echo ""
    echo "💾 BACKUP"
    echo "  nixx backup:"
    echo "    create [SERVIÇO]        → Criar backup"
    echo "    restore [SERVIÇO] [ARQ] → Restaurar backup"
    echo "    list                    → Listar backups"
    echo "    clean                   → Remover backups antigos"
    echo ""
    echo "⚙️  CONFIGURAÇÃO"
    echo "  nixx config:"
    echo "    set [CHAVE] [VALOR]     → Definir configuração"
    echo "    get [CHAVE]             → Obter valor"
    echo "    list                    → Listar configurações"
    echo "    import [ARQUIVO]        → Importar configurações"
    echo "    export [ARQUIVO]        → Exportar configurações"
    echo ""
    echo "🔍 DIAGNÓSTICO"
    echo "  nixx diagnose:"
    echo "    system                  → Verificar sistema"
    echo "    docker                  → Verificar Docker"
    echo "    network                 → Verificar rede"
    echo "    services                → Verificar serviços"
    echo "    all                     → Verificação completa"
    echo ""
    echo "⚡ GERENCIAMENTO"
    echo "  nixx manage:"
    echo "    kill-port [PORTA]       → Finalizar processo em porta"
    echo "    kill-service [SERVIÇO]  → Finalizar portas do serviço"
    echo "    kill-containers         → Finalizar todos containers"
    echo "    kill-services           → Finalizar todos serviços"
    echo "    clean                   → Limpeza completa"
    echo ""
    echo "📝 EXEMPLOS COMUNS"
    echo "  nixx install main                     → Configurar servidor principal"
    echo "  nixx create gitlab                    → Instalar GitLab"
    echo "  nixx monitor resources                → Monitorar sistema"
    echo "  nixx credentials reset gitlab         → Nova senha GitLab"
    echo "  nixx logs follow gitlab               → Acompanhar logs"
    echo "  nixx backup create gitlab             → Backup do GitLab"
    echo ""
    echo "📚 DOCUMENTAÇÃO"
    echo "  Para mais informações e exemplos: https://github.com/seu-usuario/nixx-cli"
    echo "  Reportar problemas: https://github.com/seu-usuario/nixx-cli/issues"
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
        "logs")
            handle_logs "${@:2}"
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
        "credentials")
            handle_credentials "$2"
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