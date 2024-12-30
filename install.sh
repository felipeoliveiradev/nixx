#!/bin/bash

# Nome do CLI
CLI_NAME="nixx"
INSTALL_DIR="/usr/local/bin"
REPO_URL="https://github.com/felipeoliveiradev/nixx"

# Funções de ajuda
print_info() {
    echo -e "\e[32m[INFO]\e[0m $1"
}

print_error() {
    echo -e "\e[31m[ERROR]\e[0m $1"
}

print_success() {
    echo -e "\e[32m[SUCCESS]\e[0m $1"
}

print_message() {
    local type=$1
    local message=$2
    case $type in
        "INFO")
            echo -e "\033[1;32m[INFO]\033[0m $message"
            ;;
        "WARN")
            echo -e "\033[1;33m[WARN]\033[0m $message"
            ;;
        "ERROR")
            echo -e "\033[1;31m[ERROR]\033[0m $message"
            ;;
        *)
            echo "$message"
            ;;
    esac
}
# Verificar permissões
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Este instalador deve ser executado como root (sudo)."
        exit 1
    fi
}

# Instalar dependências
install_dependencies() {
    print_info "Verificando dependências..."
    local deps=("bash" "curl" "docker")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v $dep &> /dev/null; then
            missing+=($dep)
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        print_info "Instalando dependências: ${missing[*]}..."
        apt-get update -y && apt-get install -y "${missing[@]}"
    else
        print_success "Todas as dependências estão instaladas."
    fi
}

# Copiar arquivos
install_cli() {
    print_message "INFO" "Baixando o CLI $CLI_NAME..."

    curl -fsSL "$REPO_URL/$CLI_NAME.sh" -o "$INSTALL_DIR/$CLI_NAME"
    if [ $? -ne 0 ]; then
        print_message "ERROR" "Falha ao baixar o CLI. Verifique o URL: $REPO_URL"
        exit 1
    fi

    print_message "INFO" "Configurando permissões para o CLI..."
    chmod +x "$INSTALL_DIR/$CLI_NAME"

    print_message "INFO" "$CLI_NAME foi instalado com sucesso em $INSTALL_DIR/$CLI_NAME"
}

# Mensagem de conclusão
show_completion_message() {
    echo ""
    print_success "Instalação concluída!"
    echo "Use o comando '$CLI_NAME help' para começar."
    echo "Se precisar desinstalar, remova os arquivos em $INSTALL_DIR e o link simbólico em /usr/bin/$CLI_NAME."
}

# Função principal
main() {
    check_root
    install_dependencies
    install_cli
    show_completion_message
}

main "$@"