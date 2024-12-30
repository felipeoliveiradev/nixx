#!/bin/bash

# Nome do CLI e diretórios
CLI_NAME="nixx-cli"
INSTALL_DIR="/usr/local/bin"
SRC_DIR="$(pwd)" # Diretório atual (onde está o projeto)

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
    print_info "Instalando $CLI_NAME em $INSTALL_DIR..."

    # Criar diretório, se não existir
    mkdir -p "$INSTALL_DIR"

    # Copiar script principal
    cp "$SRC_DIR/nixx-cli.sh" "$INSTALL_DIR/$CLI_NAME"

    # Garantir permissões de execução
    chmod +x "$INSTALL_DIR/$CLI_NAME"

    print_success "$CLI_NAME instalado com sucesso!"
}

# Criar link simbólico (opcional)
create_symlink() {
    if [ -f "/usr/bin/$CLI_NAME" ]; then
        print_info "Link simbólico já existe em /usr/bin/$CLI_NAME."
    else
        ln -s "$INSTALL_DIR/$CLI_NAME" "/usr/bin/$CLI_NAME"
        print_success "Link simbólico criado em /usr/bin/$CLI_NAME."
    fi
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
    create_symlink
    show_completion_message
}

main "$@"