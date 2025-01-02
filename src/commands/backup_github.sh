# src/commands/backup_github.sh
#!/bin/bash

# Configurar backup para GitHub
setup_github_backup() {
    local github_token=$1
    local github_repo=$2
    local backup_interval=${3:-"0 */6 * * *"}  # Default: a cada 6 horas

    print_info "Configurando backup automático para GitHub..."

    # Verificar parâmetros
    if [ -z "$github_token" ] || [ -z "$github_repo" ]; then
        print_error "Token do GitHub e repositório são necessários"
        print_info "Uso: nixx backup github-setup TOKEN REPO [CRON_SCHEDULE]"
        print_info "Exemplo: nixx backup github-setup ghp_xxx123 usuario/repo '0 */6 * * *'"
        return 1
    }

    # Criar script de backup
    local backup_script="$CONFIG_DIR/backup-gitlab.sh"
    cat > "$backup_script" << EOF
#!/bin/bash

# Configurações
BACKUP_DIR="$BACKUP_DIR"
GITHUB_TOKEN="$github_token"
GITHUB_REPO="$github_repo"
DATE=\$(date +%Y%m%d_%H%M%S)

# Criar backup do GitLab
echo "Criando backup do GitLab..."
docker exec \$(docker ps -q -f name=gitlab) gitlab-backup create STRATEGY=copy

# Criar diretório temporário
TEMP_DIR="/tmp/gitlab-backup-\$DATE"
mkdir -p "\$TEMP_DIR"

# Copiar arquivos de backup
cp "\$BACKUP_DIR"/gitlab_backup_* "\$TEMP_DIR/"
cp /etc/gitlab/gitlab.rb "\$TEMP_DIR/gitlab.rb"
cp /etc/gitlab/gitlab-secrets.json "\$TEMP_DIR/gitlab-secrets.json"

# Inicializar repositório Git
cd "\$TEMP_DIR"
git init
git config user.email "gitlab-backup@local"
git config user.name "GitLab Backup"

# Adicionar arquivos ao Git
git add .
git commit -m "Backup GitLab - \$DATE"

# Configurar e enviar para GitHub
git remote add origin https://\${GITHUB_TOKEN}@github.com/\${GITHUB_REPO}.git
git push -u origin master --force

# Limpar
cd /
rm -rf "\$TEMP_DIR"

echo "Backup concluído e enviado para GitHub"
EOF

    # Tornar script executável
    chmod +x "$backup_script"

    # Configurar cron
    print_info "Configurando cron job..."
    (crontab -l 2>/dev/null; echo "$backup_interval $backup_script") | crontab -

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
        return 1
    fi

    print_info "Listando backups no GitHub..."
    curl -s -H "Authorization: token $github_token" \
        "https://api.github.com/repos/$github_repo/commits" | \
        jq -r '.[] | "[\(.commit.author.date)] \(.commit.message)"'
}

# Handler principal de backup GitHub
handle_backup_github() {
    local action=$1
    shift

    case $action in
        "setup")
            setup_github_backup "$@"
            ;;
        "list")
            list_github_backups "$@"
            ;;
        *)
            print_error "Ação desconhecida: $action"
            echo "Ações disponíveis:"
            echo "  setup TOKEN REPO [CRON] - Configurar backup automático"
            echo "  list TOKEN REPO         - Listar backups"
            return 1
            ;;
    esac
}