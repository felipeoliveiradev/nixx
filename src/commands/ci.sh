#!/bin/bash

# Configurações de templates
TEMPLATES_DIR="$BASE_DIR/src/templates"  # Corrigido o caminho

# Criar pipeline GitLab
create_gitlab_ci() {
    local template=$1
    local template_file="$TEMPLATES_DIR/gitlab/$template.yml"
    local output_file=".gitlab-ci.yml"

    if [ ! -f "$template_file" ]; then
        print_error "Template não encontrado: $template"
        return 1
    fi  # Adicionado 'fi' que estava faltando

    cp "$template_file" "$output_file"
    print_success "Arquivo .gitlab-ci.yml criado com template $template"
}

# Configurar GitLab Runner
setup_gitlab_runner() {
    local token=$1
    local url=$2

    print_info "Instalando GitLab Runner..."

    # Verificar se é root
    if [ "$EUID" -ne 0 ]; then 
        print_error "Por favor, execute como root (sudo)"
        return 1
    fi

    # Adicionar repositório do GitLab Runner
    print_info "Adicionando repositório do GitLab Runner..."
    curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | sudo bash

    # Instalar GitLab Runner
    print_info "Instalando GitLab Runner..."
    sudo apt-get update
    sudo apt-get install -y gitlab-runner

    # Registrar Runner
    print_info "Registrando Runner..."
    sudo gitlab-runner register \
        --non-interactive \
        --url "$url" \
        --registration-token "$token" \
        --executor "docker" \
        --docker-image alpine:latest \
        --description "docker-runner" \
        --tag-list "docker" \
        --run-untagged="true" \
        --locked="false"

    # Iniciar o serviço
    print_info "Iniciando serviço..."
    sudo systemctl enable gitlab-runner
    sudo systemctl start gitlab-runner

    print_success "GitLab Runner configurado com sucesso"
}

# Criar workflow GitHub Actions
create_github_workflow() {
    local template=$1
    local template_file="$TEMPLATES_DIR/github/$template.yml"
    
    mkdir -p .github/workflows
    local output_file=".github/workflows/main.yml"

    if [ ! -f "$template_file" ]; then
        print_error "Template não encontrado: $template"
        return 1
    fi  # Adicionado 'fi' que estava faltando

    cp "$template_file" "$output_file"
    print_success "GitHub Actions workflow criado com template $template"
}

# Criar pipeline personalizada
create_custom_pipeline() {
    local name=$1
    local stages=$2
    local output_file=".gitlab-ci.yml"

    print_info "Criando pipeline personalizada..."

    # Verificar parâmetros
    if [ -z "$name" ] || [ -z "$stages" ]; then
        print_error "Nome e estágios são necessários"
        return 1
    fi

    # Cabeçalho
    cat > "$output_file" << EOF
# Pipeline: $name
# Gerada por Nixx CLI

stages:
EOF

    # Adicionar estágios
    IFS=',' read -ra STAGE_ARRAY <<< "$stages"
    for stage in "${STAGE_ARRAY[@]}"; do
        echo "  - $stage" >> "$output_file"
    done

    echo "" >> "$output_file"

    # Criar jobs para cada estágio
    for stage in "${STAGE_ARRAY[@]}"; do
        cat >> "$output_file" << EOF
${stage}:
  stage: ${stage}
  script:
    - echo "Executando estágio ${stage}"
  rules:
    - when: on_success

EOF
    done

    print_success "Pipeline personalizada criada em $output_file"
}

# Handler principal de CI/CD
handle_ci() {
    local platform=$1
    local action=$2
    local template=$3

    if [ -z "$platform" ] || [ -z "$action" ]; then
        print_error "Plataforma e ação são necessárias"
        return 1
    fi

    case $platform in
        "gitlab")
            case $action in
                "ci")
                    if [ -z "$template" ]; then
                        print_error "Template é necessário"
                        return 1
                    fi
                    create_gitlab_ci "$template"
                    ;;
                "runner")
                    if [ -z "$template" ] || [ -z "$4" ]; then
                        print_error "Token e URL são necessários"
                        return 1
                    fi
                    setup_gitlab_runner "$template" "$4"
                    ;;
                *)
                    print_error "Ação GitLab desconhecida: $action"
                    return 1
                    ;;
            esac
            ;;
        "github")
            case $action in
                "workflow")
                    if [ -z "$template" ]; then
                        print_error "Template é necessário"
                        return 1
                    fi
                    create_github_workflow "$template"
                    ;;
                *)
                    print_error "Ação GitHub desconhecida: $action"
                    return 1
                    ;;
            esac
            ;;
        "pipeline")
            create_custom_pipeline "$action" "$template"
            ;;
        *)
            print_error "Plataforma desconhecida: $platform"
            return 1
            ;;
    esac
}