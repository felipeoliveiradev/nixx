#!/bin/bash

# Encontrar o diretório real do script
SCRIPT_PATH="$(readlink -f "$0")"
BASE_DIR="$(dirname "$SCRIPT_PATH")"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Versão do CLI
VERSION="1.0.0"

# Configurações globais
CONFIG_DIR="$HOME/.nixx-cli"
FIRST_RUN_FILE="$CONFIG_DIR/.first_run"
CONFIG_FILE="$CONFIG_DIR/config.sh"
DOCKER_COMPOSE_DIR="$CONFIG_DIR/compose"
BACKUP_DIR="$CONFIG_DIR/backups"
LOG_DIR="$CONFIG_DIR/logs"
LOG_FILE="$LOG_DIR/nixx-cli.log"
TEMPLATES_DIR="$BASE_DIR/src/templates"

# Função para carregar módulos
load_modules() {
    local module_type=$1
    local module_dir="$BASE_DIR/src/$module_type"
    
    echo "[DEBUG] BASE_DIR = $BASE_DIR"
    echo "[DEBUG] Tentando carregar módulos de: $module_dir"
    
    if [ ! -d "$module_dir" ]; then
        echo "[DEBUG] ERRO: Diretório não encontrado: $module_dir"
        return 1
    fi
    
    # Listar todos os arquivos no diretório
    echo "[DEBUG] Arquivos no diretório $module_dir:"
    ls -la "$module_dir"
    
    for file in "$module_dir"/*.sh; do
        if [ -f "$file" ]; then
            echo "[DEBUG] Carregando: $file"
            # Verificar se o arquivo tem permissão de execução
            if [ ! -x "$file" ]; then
                echo "[DEBUG] AVISO: Arquivo sem permissão de execução: $file"
                chmod +x "$file"
            fi
            source "$file"
            if [ $? -ne 0 ]; then
                echo "[DEBUG] ERRO ao carregar $file"
            else
                echo "[DEBUG] $file carregado com sucesso"
            fi
        fi
    done
    
    # Listar todas as funções carregadas que começam com "handle_"
    echo "[DEBUG] Funções handle_ disponíveis:"
    declare -F | grep "handle_"
}

# Handler principal de comandos
handle_command() {
    local command=$1
    shift

    if declare -F "handle_$command" > /dev/null; then
        "handle_$command" "$@"
    else
        echo -e "${RED}[ERROR]${NC} Comando desconhecido: $command"
        return 1
    fi
}

# Inicialização do CLI
init_cli() {
    # Verificar primeira execução
    echo $FIRST_RUN_FILE
    if [ ! -f "$FIRST_RUN_FILE" ]; then
        echo -e "${BLUE}[INFO]${NC} Inicializando Nixx CLI v$VERSION..."
        
        # Criar diretórios necessários
        mkdir -p "$CONFIG_DIR" "$DOCKER_COMPOSE_DIR" "$BACKUP_DIR" "$LOG_DIR"
        touch "$LOG_FILE"
        
        # Carregar módulos com mensagens
        load_modules "utils"
        load_modules "commands"
        
        # Criar arquivo de controle
        touch "$FIRST_RUN_FILE"
    else
        # Carregar módulos silenciosamente
        load_modules "utils" >/dev/null 2>&1
        load_modules "commands" >/dev/null 2>&1
    fi
}

# Função principal
main() {
    # Inicializar CLI
    init_cli
    # Verificar root para comandos que necessitam
    case $1 in
        "help"|"--help"|"-h"|"version"|"-v"|"--version"|"")
            ;;
        *)
            if [ "$EUID" -ne 0 ]; then 
                echo -e "${RED}[ERROR]${NC} Por favor, execute como root (sudo)"
                exit 1
            fi
            ;;
    esac

    # Processar comando
    case $1 in
        "version"|"-v"|"--version")
            echo "Nixx CLI versão $VERSION"
            ;;
        "help"|"--help"|"-h"|"")
            show_help
            ;;
        *)
            handle_command "$@"
            ;;
    esac
}

# Tratamento de erros
trap 'echo -e "${RED}[ERROR]${NC} Erro na linha $LINENO: $BASH_COMMAND"' ERR

# Executar
main "$@"