# src/commands/backup.sh
#!/bin/bash


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
            create_backup "$1"
            ;;
        "setup")
            setup_github_backup "$@"
            ;;
        "list")
            list_github_backups "$@"
            ;;
        "restore")
            restore_backup "$1" "$2"
            ;;
        "list")
            list_backups "$1"
            ;;
        "clean")
            clean_backups "$1"
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