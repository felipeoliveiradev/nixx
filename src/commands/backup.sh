# src/commands/backup.sh
#!/bin/bash


setup_github_backup() {
    local github_token=$1
    local github_repo=$2
    local backup_interval=${3:-"0 */6 * * *"}

    print_info "Configurando backup automático dos repositórios para GitHub..."

    # Verificar parâmetros
    if [ -z "$github_token" ] || [ -z "$github_repo" ]; then
        print_error "Token do GitHub e repositório são necessários"
        print_info "Uso: nixx backup github-setup TOKEN REPO [CRON_SCHEDULE]"
        print_info "Exemplo: nixx backup github-setup ghp_xxx123 usuario/repo '0 */6 * * *'"
        return 1
    fi

    # Criar script de backup
    local backup_script="$CONFIG_DIR/backup-gitlab-repos.sh"
    cat > "$backup_script" << 'EOF'
#!/bin/bash

# Configurações
DATE=$(date +%Y%m%d_%H%M%S)
TEMP_DIR="/tmp/gitlab-repos-backup-$DATE"
GITLAB_URL="http://localhost"  # Ajuste para sua URL do GitLab
GITHUB_TOKEN="$github_token"
GITHUB_REPO="$github_repo"

# Função para log
log_info() {
    echo "[INFO] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

# Criar diretório temporário
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR" || exit 1

# Inicializar repositório Git para o backup
git init
git config user.email "gitlab-backup@local"
git config user.name "GitLab Backup"
git checkout -b main

# Criar diretório para os repos
mkdir -p repos

# Obter token do GitLab do container
GITLAB_TOKEN=$(docker exec $(docker ps -q -f name=gitlab) gitlab-rails runner "puts User.where(admin: true).first.personal_access_tokens.first.token" 2>/dev/null)

if [ -z "$GITLAB_TOKEN" ]; then
    log_error "Não foi possível obter o token do GitLab"
    exit 1
fi

# Função para clonar um repositório e suas branches
clone_repository() {
    local project_id=$1
    local project_path=$2
    
    log_info "Clonando repositório: $project_path"
    
    # Criar diretório para o projeto
    mkdir -p "repos/$project_path"
    cd "repos/$project_path" || return 1
    
    # Clonar o repositório
    git clone --mirror "http://oauth2:${GITLAB_TOKEN}@localhost/${project_path}.git" .
    
    # Atualizar todas as refs
    git remote update
    
    cd "$TEMP_DIR" || return 1
}

# Listar e clonar todos os repositórios
log_info "Obtendo lista de projetos..."
docker exec $(docker ps -q -f name=gitlab) gitlab-rails runner '
  Project.all.each do |project|
    puts "#{project.id}|#{project.path_with_namespace}"
  end
' | while IFS='|' read -r project_id project_path; do
    clone_repository "$project_id" "$project_path"
done

# Verificar se há repositórios para backup
if [ -z "$(ls -A repos)" ]; then
    log_error "Nenhum repositório encontrado para backup"
    cd /
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Adicionar todos os repositórios ao Git
cd "$TEMP_DIR" || exit 1
git add .
git commit -m "Backup dos repositórios GitLab - $DATE"

# Enviar para GitHub
git remote add origin "https://${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git"
if ! git push -u origin main --force; then
    log_error "Falha ao enviar para o GitHub"
    cd /
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Limpar
cd /
rm -rf "$TEMP_DIR"

log_info "Backup dos repositórios concluído e enviado para GitHub com sucesso"
EOF

    # Tornar script executável
    chmod +x "$backup_script"

    # Configurar cron
    print_info "Configurando cron job..."
    (crontab -l 2>/dev/null | grep -v "$backup_script"; echo "$backup_interval $backup_script") | crontab -

    # Testar execução
    print_info "Testando backup..."
    bash "$backup_script"

    print_success "Backup configurado com sucesso!"
    print_info "Schedule: $backup_interval"
    print_info "Repositório: https://github.com/$github_repo"
}
# Listar backups
list_github_backups() {
    local github_token=$1
    local github_repo=$2

    if [ -z "$github_token" ] || [ -z "$github_repo" ]; then
        print_error "Token do GitHub e repositório são necessários"
        print_info "Uso: nixx backup github-list TOKEN REPO"
        print_info "Exemplo: nixx backup github-list ghp_xxx123 usuario/repo"
        return 1
    fi

    print_info "Listando backups no GitHub..."
    local response
    response=$(curl -s -H "Authorization: token $github_token" \
        "https://api.github.com/repos/$github_repo/commits")
    
    if echo "$response" | jq -e 'type == "array"' > /dev/null; then
        echo "$response" | jq -r '.[] | "[\(.commit.committer.date)] \(.commit.message)"'
    else
        error_message=$(echo "$response" | jq -r '.message // "Erro desconhecido"')
        print_error "Falha ao listar commits: $error_message"
        return 1
    fi
}
execute_backup_now() {
    local github_token=$1
    local github_repo=$2
    local gitlab_token=$3

    if [ -z "$github_token" ] || [ -z "$github_repo" ]; then
        print_error "Token do GitHub e repositório são necessários"
        print_info "Uso: nixx backup github-now GITHUB_TOKEN GITHUB_REPO [GITLAB_TOKEN]"
        print_info "Exemplo: nixx backup github-now ghp_xxx123 usuario/repo glpat_xxxxx"
        return 1
    fi

    print_info "Iniciando backup imediato dos repositórios..."

    # Verificar token do GitHub
    print_info "Verificando credenciais do GitHub..."
    if ! curl -s -H "Authorization: token $github_token" \
        "https://api.github.com/user" | jq -e '.login' > /dev/null; then
        print_error "Token do GitHub inválido"
        return 1
    fi

    # Se o token do GitLab não foi fornecido, tentar obtê-lo
    if [ -z "$gitlab_token" ]; then
        print_info "Token do GitLab não fornecido, tentando obter automaticamente..."
        gitlab_token=$(docker exec $(docker ps -q -f name=gitlab) gitlab-rails runner "puts User.where(admin: true).first&.personal_access_tokens&.first&.token" 2>/dev/null)
    fi

    if [ -z "$gitlab_token" ]; then
        print_error "Token do GitLab não encontrado."
        print_info "Por favor, forneça o token do GitLab como terceiro parâmetro:"
        print_info "nixx backup github-now GITHUB_TOKEN GITHUB_REPO GITLAB_TOKEN"
        print_info "Você pode gerar um token no GitLab em: User Settings > Access Tokens"
        return 1
    fi

    local TEMP_DIR="/tmp/gitlab-repos-backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR" || exit 1

    # Verificar token do GitLab
    print_info "Verificando credenciais do GitLab..."
    if ! curl -s --header "PRIVATE-TOKEN: $gitlab_token" \
        "http://localhost/api/v4/projects" | jq -e 'length > 0' > /dev/null; then
        print_error "Token do GitLab inválido ou sem acesso aos projetos"
        cd /
        rm -rf "$TEMP_DIR"
        return 1
    fi

    # Inicializar repositório Git para o backup
    git init
    git config user.email "gitlab-backup@local"
    git config user.name "GitLab Backup"
    git checkout -b main

    # Criar diretório para os repos
    mkdir -p repos

    # Função para clonar um repositório e suas branches
    clone_repository() {
        local project_path=$1
        
        print_info "Clonando repositório: $project_path"
        
        # Criar diretório para o projeto
        mkdir -p "repos/$project_path"
        cd "repos/$project_path" || return 1
        
        # Clonar o repositório
        if ! git clone --mirror "http://oauth2:${gitlab_token}@localhost/${project_path}.git" .; then
            print_error "Falha ao clonar $project_path"
            return 1
        fi
        
        # Atualizar todas as refs
        git remote update
        
        cd "$TEMP_DIR" || return 1
    }

    # Listar e clonar todos os repositórios
    print_info "Obtendo lista de projetos..."
    curl -s --header "PRIVATE-TOKEN: $gitlab_token" \
        "http://localhost/api/v4/projects" | \
        jq -r '.[] | .path_with_namespace' | while read -r project_path; do
            clone_repository "$project_path"
        done

    # Verificar se há repositórios para backup
    if [ -z "$(ls -A repos)" ]; then
        print_error "Nenhum repositório encontrado para backup"
        cd /
        rm -rf "$TEMP_DIR"
        return 1
    fi

    # Adicionar todos os repositórios ao Git
    print_info "Preparando backup..."
    cd "$TEMP_DIR" || exit 1
    git add .
    git commit -m "Backup dos repositórios GitLab - $(date +%Y%m%d_%H%M%S)"

    # Enviar para GitHub
    print_info "Enviando para GitHub..."
    git remote add origin "https://${github_token}@github.com/${github_repo}.git"
    if ! git push -u origin main --force; then
        print_error "Falha ao enviar para o GitHub"
        cd /
        rm -rf "$TEMP_DIR"
        return 1
    fi

    # Limpar
    cd /
    rm -rf "$TEMP_DIR"

    print_success "Backup dos repositórios concluído com sucesso!"
}


# Criar backup
create_backup() {
    local service=$1
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/${service}_${timestamp}.tar.gz"

    print_info "Criando backup de $service..."

    case $service in
        "gitlab")
            docker run --rm --volumes-from gitlab \
                -v $BACKUP_DIR:/backup \
                gitlab/gitlab-ce:latest \
                tar czf "/backup/gitlab_${timestamp}.tar.gz" \
                /etc/gitlab /var/opt/gitlab /var/log/gitlab
            ;;
        "portainer")
            docker run --rm --volumes-from portainer \
                -v $BACKUP_DIR:/backup \
                alpine tar czf "/backup/portainer_${timestamp}.tar.gz" \
                /data
            ;;
        "prometheus")
            docker run --rm --volumes-from prometheus \
                -v $BACKUP_DIR:/backup \
                alpine tar czf "/backup/prometheus_${timestamp}.tar.gz" \
                /prometheus
            ;;
        "grafana")
            docker run --rm --volumes-from grafana \
                -v $BACKUP_DIR:/backup \
                alpine tar czf "/backup/grafana_${timestamp}.tar.gz" \
                /var/lib/grafana
            ;;
        *)
            print_error "Serviço não suportado para backup: $service"
            return 1
            ;;
    esac

    print_success "Backup criado: $backup_file"
}

# Restaurar backup
restore_backup() {
    local service=$1
    local backup_file=$2

    if [ ! -f "$backup_file" ]; then
        print_error "Arquivo de backup não encontrado: $backup_file"
        return 1
    fi

    print_info "Restaurando backup de $service..."

    # Parar serviço antes da restauração
    docker service rm $service || true
    sleep 5

    case $service in
        "gitlab")
            docker run --rm --volumes-from gitlab \
                -v $BACKUP_DIR:/backup \
                gitlab/gitlab-ce:latest \
                tar xzf "/backup/$(basename $backup_file)" -C /
            ;;
        "portainer")
            docker run --rm --volumes-from portainer \
                -v $BACKUP_DIR:/backup \
                alpine tar xzf "/backup/$(basename $backup_file)" -C /
            ;;
        "prometheus")
            docker run --rm --volumes-from prometheus \
                -v $BACKUP_DIR:/backup \
                alpine tar xzf "/backup/$(basename $backup_file)" -C /
            ;;
        "grafana")
            docker run --rm --volumes-from grafana \
                -v $BACKUP_DIR:/backup \
                alpine tar xzf "/backup/$(basename $backup_file)" -C /
            ;;
        *)
            print_error "Serviço não suportado para restore: $service"
            return 1
            ;;
    esac

    # Reiniciar serviço
    create_service $service

    print_success "Backup restaurado com sucesso"
}

# Listar backups
list_backups() {
    local service=$1

    print_info "Backups disponíveis:"
    if [ -z "$service" ]; then
        ls -lh $BACKUP_DIR
    else
        ls -lh $BACKUP_DIR | grep $service
    fi
}

# Limpar backups antigos
clean_backups() {
    local retention_days=${1:-7}

    print_info "Limpando backups mais antigos que $retention_days dias..."
    find $BACKUP_DIR -type f -mtime +$retention_days -delete
    print_success "Limpeza concluída"
}

# Handler principal de backup
handle_backup() {
    local action=$1
    shift

    case $action in
        "create")
            if [ -z "$1" ]; then
                print_error "Serviço não especificado"
                print_info "Uso: nixx backup create [gitlab|portainer|prometheus|grafana]"
                return 1
            fi
            create_backup "$1"
            ;;
        "restore")
            if [ -z "$1" ] || [ -z "$2" ]; then
                print_error "Serviço ou arquivo não especificado"
                print_info "Uso: nixx backup restore [SERVIÇO] [ARQUIVO]"
                return 1
            fi
            restore_backup "$1" "$2"
            ;;
        "list")
            list_backups "$1"
            ;;
        "clean")
            clean_backups "${1:-7}"  # Default 7 days retention
            ;;
        "github-setup")
            setup_github_backup "$@"
            ;;
        "github-list")
            list_github_backups "$@"
            ;;
        "github-now")
            execute_backup_now "$@"
            ;;
        *)
            print_error "Ação de backup desconhecida: $action"
            print_info "Ações disponíveis:"
            print_info "  create [SERVIÇO]        - Criar backup"
            print_info "  restore [SERVIÇO] [ARQ] - Restaurar backup"
            print_info "  list [SERVIÇO]          - Listar backups"
            print_info "  clean [DIAS]            - Limpar backups antigos"
            print_info "  github-setup            - Configurar backup GitHub"
            print_info "  github-list             - Listar backups no GitHub"
            print_info "  github-now              - Executar backup imediatamente"
            return 1
            ;;
    esac
}