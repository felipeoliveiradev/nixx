# src/utils/core.sh
#!/bin/bash

# Verificar se é root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        print_error "Por favor, execute como root (sudo)"
        exit 1
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
    print_info "Verificando atualizações..."
    # Implementar lógica de verificação de atualizações
}

# Setup inicial
setup_directories() {
    mkdir -p "$CONFIG_DIR" "$DOCKER_COMPOSE_DIR" "$BACKUP_DIR" "$LOG_DIR" "$TEMPLATES_DIR"
    touch "$LOG_FILE"
    
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
        print_info "Arquivo de configuração criado em $CONFIG_FILE"
    fi
}

# Menu de ajuda
show_help() {
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                        Nixx CLI - Sistema DevOps                           ║"
    echo "║                              Versão: $VERSION                              ║"
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
    echo "    workflow [TEMPLATE]     → Configurar GitHub Actions (node|docker)"
    echo "    runner setup            → Configurar GitHub Runner"
    echo "    runner remove           → Remover GitHub Runner"
    echo "    runner list             → Listar GitHub Runners"
    echo ""
    echo "  nixx pipeline:"
    echo "    create NAME STAGES      → Criar pipeline personalizada"
    echo "    template list           → Listar templates disponíveis"
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
    echo "    clean                   → Limpeza completa do sistema"
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

# Tratamento de erros
handle_error() {
    local exit_code=$1
    local line_no=$2
    local last_command=$3
    local function_trace=$4

    print_error "Erro no comando: $last_command"
    print_error "Código de saída: $exit_code"
    print_error "Linha: $line_no"
    print_error "Stack trace: $function_trace"
    
    log "ERROR" "Comando: $last_command | Código: $exit_code | Linha: $line_no | Stack: $function_trace"
}

# Verificar status do comando
check_command_status() {
    local status=$1
    local command=$2

    if [ $status -ne 0 ]; then
        print_error "Falha ao executar: $command"
        return 1
    fi
    return 0
}

# Carregar configuração
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        print_error "Arquivo de configuração não encontrado"
        return 1
    fi
}