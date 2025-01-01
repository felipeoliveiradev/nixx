# install.sh
#!/bin/bash

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Versão do CLI
VERSION="1.0.0"

# Diretórios
INSTALL_DIR="/opt/nixx"
BIN_DIR="/usr/local/bin"
CONFIG_DIR="$HOME/.nixx"

# Função para logs
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Verificar requisitos
check_requirements() {
    log "Verificando requisitos do sistema..."

    # Verificar se é root
    if [ "$EUID" -ne 0 ]; then 
        error "Por favor, execute como root (sudo)"
    fi

    # Verificar sistema operacional
    if ! grep -q 'Ubuntu\|Debian' /etc/os-release; then
        error "Este instalador suporta apenas Ubuntu e Debian"
    fi

    # Verificar dependências
    local deps=("curl" "git" "docker" "jq" "iftop")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v $dep &> /dev/null; then
            missing+=($dep)
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        warning "Dependências faltando: ${missing[*]}"
        log "Instalando dependências..."
        apt-get update
        apt-get install -y ${missing[@]}
    fi
    
    success "Requisitos verificados com sucesso"
}

# Preparar diretórios
setup_directories() {
    log "Criando diretórios..."

    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"/{logs,backups,compose,templates}

    success "Diretórios criados com sucesso"
}

# Download dos arquivos
download_files() {
    log "Baixando arquivos..."

    # Clone do repositório
    git clone https://github.com/felipeoliveiradev/nixx.git /tmp/nixx

    # Mover arquivos
    cp -r /tmp/nixx/* "$INSTALL_DIR/"
    
    # Limpar temporários
    rm -rf /tmp/nixx

    success "Arquivos baixados com sucesso"
}

# Configurar CLI
setup_cli() {
    log "Configurando Nixx CLI..."

    # Tornar executável
    chmod +x "$INSTALL_DIR/nixx.sh"

    # Criar link simbólico
    ln -sf "$INSTALL_DIR/nixx.sh" "$BIN_DIR/nixx"

    # Criar arquivo de configuração inicial
    cat > "$CONFIG_DIR/config.sh" << EOF
# Nixx CLI Configuration
VERSION="$VERSION"
INSTALL_DIR="$INSTALL_DIR"
CONFIG_DIR="$CONFIG_DIR"
DOCKER_REGISTRY=""
GITLAB_URL=""
GITHUB_TOKEN=""
EOF

    success "CLI configurado com sucesso"
}

verify_installation() {
    log "Verificando instalação..."

    if ! command -v nixx &> /dev/null; then
        error "Instalação falhou: comando 'nixx' não encontrado"
    fi

    local version=$(nixx --version)
    if [ "$version" != "$VERSION" ]; then
        error "Versão incorreta instalada"
    fi

    success "Instalação verificada com sucesso"
}

setup_docker() {
    if ! command -v docker &> /dev/null; then
        warning "Docker não encontrado. Deseja instalar? (s/n)"
        read -r install_docker

        if [ "$install_docker" = "s" ]; then
            log "Instalando Docker..."
            curl -fsSL https://get.docker.com -o get-docker.sh
            sh get-docker.sh
            systemctl enable docker
            systemctl start docker
            success "Docker instalado com sucesso"
        fi
    fi
}

show_completion() {
    echo -e "\n${GREEN}=== Nixx CLI instalado com sucesso! ===${NC}\n"
    echo "Para começar, execute:"
    echo "  nixx --help    # Ver comandos disponíveis"
    echo "  nixx install main    # Configurar node principal"
    echo -e "\nDocumentação: https://github.com/felipeoliveiradev/nixx\n"
}

main() {
    echo -e "${BLUE}=== Instalador Nixx CLI v${VERSION} ===${NC}\n"

    check_requirements
    setup_directories
    download_files
    setup_cli
    setup_docker
    verify_installation
    show_completion
}

main