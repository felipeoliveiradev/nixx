# src/commands/backup.sh
#!/bin/bash
# Função para obter o IP do servidor
get_server_ip() {
    # Tenta diferentes métodos para obter o IP
    local ip=""
    
    # Método 1: hostname -I (primeiro IP)
    if command -v hostname >/dev/null 2>&1; then
        ip=$(hostname -I | awk '{print $1}')
    fi
    
    # Método 2: ip addr (se hostname falhar)
    if [ -z "$ip" ] && command -v ip >/dev/null 2>&1; then
        ip=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -n1)
    fi
    
    # Método 3: ifconfig (fallback)
    if [ -z "$ip" ] && command -v ifconfig >/dev/null 2>&1; then
        ip=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -n1)
    fi
    
    echo "$ip"
}


setup_gitlab_webhook() {
    local gitlab_token=$1
    local source_repo=$2
    local webhook_url=$3
    local server_ip=$(get_server_ip)

    print_info "Configurando webhook no GitLab para $source_repo..."

    # Obter ID do projeto
    local project_id
    project_id=$(curl -s --header "PRIVATE-TOKEN: $gitlab_token" \
        "http://$server_ip/api/v4/projects/${source_repo/\//%2F}" | \
        jq -r '.id')

    if [ -z "$project_id" ] || [ "$project_id" = "null" ]; then
        print_error "Não foi possível encontrar o projeto no GitLab"
        return 1
    fi

    # Criar webhook
    curl -s --request POST --header "PRIVATE-TOKEN: $gitlab_token" \
        "http://$server_ip/api/v4/projects/$project_id/hooks" \
        --form "url=$webhook_url" \
        --form "push_events=true" \
        --form "tag_push_events=true"

    print_success "Webhook do GitLab configurado com sucesso!"
}

# Função para configurar webhook no GitHub
setup_github_webhook() {
    local github_token=$1
    local source_repo=$2
    local webhook_url=$3

    print_info "Configurando webhook no GitHub para $source_repo..."

    curl -s -H "Authorization: token $github_token" \
        "https://api.github.com/repos/$source_repo/hooks" \
        -d "{
            \"name\": \"web\",
            \"active\": true,
            \"events\": [\"push\", \"create\"],
            \"config\": {
                \"url\": \"$webhook_url\",
                \"content_type\": \"json\"
            }
        }"

    print_success "Webhook do GitHub configurado com sucesso!"
}

# Função para criar o serviço de webhook
setup_webhook_service() {
    local webhook_port="9000"
    local webhook_service="/etc/systemd/system/repo-sync-webhook.service"
    local webhook_script="$CONFIG_DIR/repo-sync-webhook.sh"

    # Criar script do webhook
    cat > "$webhook_script" << 'EOF'
#!/bin/bash

PORT="9000"
LOGFILE="/var/log/repo-sync-webhook.log"

# Função para processar o webhook
handle_webhook() {
    local payload="$1"
    local source="$2"
    
    # Extrair informações do payload
    if [ "$source" = "gitlab" ]; then
        repo=$(echo "$payload" | jq -r '.project.path_with_namespace')
    else
        repo=$(echo "$payload" | jq -r '.repository.full_name')
    fi
    
    # Executar sincronização
    echo "[$(date)] Iniciando sincronização do repositório $repo" >> "$LOGFILE"
    nixx backup sync "$source" "${source#git}" "$repo" "$DEST_REPO" "$GITLAB_TOKEN" "$GITHUB_TOKEN" >> "$LOGFILE" 2>&1
}

# Iniciar servidor web simples
while true; do
    echo -e "HTTP/1.1 200 OK\n\n$(date)" | nc -l -p $PORT | while read line; do
        if [[ "$line" == *"POST"* ]]; then
            # Ler o payload
            length=$(grep "Content-Length:" -m1 | cut -d' ' -f2)
            payload=$(dd bs=$length count=1 2>/dev/null)
            
            # Determinar fonte baseado no payload
            if echo "$payload" | jq -e '.object_kind' >/dev/null 2>&1; then
                handle_webhook "$payload" "gitlab" &
            else
                handle_webhook "$payload" "github" &
            fi
        fi
    done
done
EOF

    chmod +x "$webhook_script"

    # Criar serviço systemd
    cat > "$webhook_service" << EOF
[Unit]
Description=Repository Sync Webhook Service
After=network.target

[Service]
ExecStart=$webhook_script
Restart=always
Environment=GITLAB_TOKEN=$1
Environment=GITHUB_TOKEN=$2
Environment=DEST_REPO=$3

[Install]
WantedBy=multi-user.target
EOF

    # Recarregar systemd e iniciar serviço
    systemctl daemon-reload
    systemctl enable repo-sync-webhook
    systemctl start repo-sync-webhook

    print_success "Serviço de webhook configurado na porta $webhook_port"
    return 0
}


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
#!/bin/bash

# Função para obter o IP do servidor
get_server_ip() {
    # Tenta diferentes métodos para obter o IP
    local ip=""
    
    # Método 1: hostname -I (primeiro IP)
    if command -v hostname >/dev/null 2>&1; then
        ip=$(hostname -I | awk '{print $1}')
    fi
    
    # Método 2: ip addr (se hostname falhar)
    if [ -z "$ip" ] && command -v ip >/dev/null 2>&1; then
        ip=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -n1)
    fi
    
    # Método 3: ifconfig (fallback)
    if [ -z "$ip" ] && command -v ifconfig >/dev/null 2>&1; then
        ip=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -n1)
    fi
    
    echo "$ip"
}

# Função para executar backup imediatamente
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
        print_error "Token do GitLab não fornecido"
        print_info "Por favor, forneça o token do GitLab como terceiro parâmetro:"
        print_info "nixx backup github-now GITHUB_TOKEN GITHUB_REPO GITLAB_TOKEN"
        print_info "Você pode gerar um token no GitLab em: User Settings > Access Tokens"
        return 1
    fi

    local TEMP_DIR="/tmp/gitlab-repos-backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR" || exit 1

    # Detectar IP do servidor
    print_info "Detectando IP do servidor..."
    local SERVER_IP=$(get_server_ip)
    
    if [ -z "$SERVER_IP" ]; then
        print_error "Não foi possível detectar o IP do servidor"
        cd /
        rm -rf "$TEMP_DIR"
        return 1
    fi

    print_info "IP do servidor detectado: $SERVER_IP"
    local GITLAB_URL="http://$SERVER_IP"

    # Verificar token do GitLab
    print_info "Verificando credenciais do GitLab em $GITLAB_URL..."
    local gitlab_test
    gitlab_test=$(curl -s --header "PRIVATE-TOKEN: $gitlab_token" "$GITLAB_URL/api/v4/projects")
    
    if ! echo "$gitlab_test" | jq -e '.' >/dev/null 2>&1; then
        print_error "Não foi possível conectar ao GitLab ou token inválido"
        print_error "URL: $GITLAB_URL"
        print_error "Verifique se:"
        print_info "1. O GitLab está acessível em $GITLAB_URL"
        print_info "2. O token está correto"
        print_info "3. O token tem permissões de API e read_repository"
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
        
        # Clonar o repositório usando oauth2
        if ! git clone --mirror "http://oauth2:${gitlab_token}@${SERVER_IP}/${project_path}.git" .; then
            print_error "Falha ao clonar $project_path"
            return 1
        fi
        
        # Atualizar todas as refs
        git remote update
        
        cd "$TEMP_DIR" || return 1
    }

    # Listar e clonar todos os repositórios
    print_info "Obtendo lista de projetos do GitLab..."
    local projects_json
    projects_json=$(curl -s --header "PRIVATE-TOKEN: $gitlab_token" "$GITLAB_URL/api/v4/projects")
    
    if ! echo "$projects_json" | jq -e 'length > 0' > /dev/null; then
        print_error "Nenhum projeto encontrado no GitLab"
        print_info "Verifique se o token tem as permissões necessárias"
        cd /
        rm -rf "$TEMP_DIR"
        return 1
    fi

    echo "$projects_json" | jq -r '.[] | .path_with_namespace' | while read -r project_path; do
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

sync_repositories() {
    local source=$1      # gitlab ou github
    local dest=$2        # github ou gitlab
    local source_repo=$3 # caminho/do/repo
    local dest_repo=$4   # usuario/repo
    local gitlab_token=$5
    local github_token=$6

    if [ -z "$source_repo" ] || [ -z "$dest_repo" ] || [ -z "$gitlab_token" ] || [ -z "$github_token" ]; then
        print_error "Todos os parâmetros são necessários"
        print_info "Uso: nixx backup sync SOURCE DEST SOURCE_REPO DEST_REPO GITLAB_TOKEN GITHUB_TOKEN"
        return 1
    fi

    print_info "Iniciando sincronização de $source para $dest..."
    local TEMP_DIR="/tmp/repo-sync-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR" || exit 1

    # Definir URLs e tokens baseado na direção
    local SERVER_IP=$(get_server_ip)
    local GITLAB_URL="http://$SERVER_IP"
    
    case $source in
        "gitlab")
            print_info "Clonando repositório do GitLab..."
            git clone --mirror "http://oauth2:${gitlab_token}@${SERVER_IP}/${source_repo}.git" repo
            CLONE_EXIT_CODE=$?
            if [ $CLONE_EXIT_CODE -ne 0 ]; then
                print_error "Falha ao clonar do GitLab (Código de saída: $CLONE_EXIT_CODE)"
                print_info "Detalhes:"
                print_info "URL: http://oauth2:***@${SERVER_IP}/${source_repo}.git"
                print_info "Verifique:"
                print_info "1. A URL do repositório está correta"
                print_info "2. O token do GitLab tem permissões de leitura"
                print_info "3. O repositório existe"
                cd /
                rm -rf "$TEMP_DIR"
                return 1
            fi
            
            cd repo || exit 1
            git remote add github "https://${github_token}@github.com/${dest_repo}.git"
            
            print_info "Enviando para GitHub..."
            git push github --mirror
            PUSH_EXIT_CODE=$?
            if [ $PUSH_EXIT_CODE -ne 0 ]; then
                print_error "Falha ao enviar para GitHub (Código de saída: $PUSH_EXIT_CODE)"
                print_info "Detalhes:"
                print_info "URL do destino: https://***/github.com/${dest_repo}.git"
                print_info "Verifique:"
                print_info "1. O token do GitHub é válido"
                print_info "2. Você tem permissão para enviar para o repositório"
                print_info "3. O repositório de destino existe"
                cd /
                rm -rf "$TEMP_DIR"
                return 1
            fi
            ;;
            
        "github")
            print_info "Clonando repositório do GitHub..."
            git clone --mirror "https://${github_token}@github.com/${source_repo}.git" repo
            CLONE_EXIT_CODE=$?
            if [ $CLONE_EXIT_CODE -ne 0 ]; then
                print_error "Falha ao clonar do GitHub (Código de saída: $CLONE_EXIT_CODE)"
                print_info "Detalhes:"
                print_info "URL: https://***/github.com/${source_repo}.git"
                print_info "Verifique:"
                print_info "1. A URL do repositório está correta"
                print_info "2. O token do GitHub é válido"
                print_info "3. O repositório existe"
                cd /
                rm -rf "$TEMP_DIR"
                return 1
            fi
            
            cd repo || exit 1
            git remote add gitlab "http://oauth2:${gitlab_token}@${SERVER_IP}/${dest_repo}.git"
            
            print_info "Enviando para GitLab..."
            git push gitlab --mirror
            PUSH_EXIT_CODE=$?
            if [ $PUSH_EXIT_CODE -ne 0 ]; then
                print_error "Falha ao enviar para GitLab (Código de saída: $PUSH_EXIT_CODE)"
                print_info "Detalhes:"
                print_info "URL do destino: http://oauth2:***@${SERVER_IP}/${dest_repo}.git"
                print_info "Verifique:"
                print_info "1. O token do GitLab é válido"
                print_info "2. Você tem permissão para enviar para o repositório"
                print_info "3. O repositório de destino existe"
                cd /
                rm -rf "$TEMP_DIR"
                return 1
            fi
            ;;
            
        *)
            print_error "Origem inválida. Use 'gitlab' ou 'github'"
            cd /
            rm -rf "$TEMP_DIR"
            return 1
            ;;
    esac

    # Limpar
    cd /
    rm -rf "$TEMP_DIR"
    print_success "Sincronização concluída com sucesso!"
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

setup_sync_trigger() {
    local source=$1      # gitlab ou github
    local dest=$2        # github ou gitlab
    local source_repo=$3
    local dest_repo=$4
    local gitlab_token=$5
    local github_token=$6

    # Validação de parâmetros
    if [ -z "$source_repo" ] || [ -z "$dest_repo" ] || [ -z "$gitlab_token" ] || [ -z "$github_token" ]; then
        print_error "Todos os parâmetros são necessários"
        print_info "Uso: nixx backup sync --trigger SOURCE DEST SOURCE_REPO DEST_REPO GITLAB_TOKEN GITHUB_TOKEN"
        print_info "Exemplo: nixx backup sync --trigger github gitlab usuario/repo grupo/projeto gitlab_token github_token"
        return 1
    fi

    # Obter IP público para webhook
    print_info "Detectando IP do servidor..."
    local server_ip=$(get_server_ip)
    
    if [ -z "$server_ip" ]; then
        print_error "Não foi possível detectar o IP do servidor"
        return 1
    fi

    local webhook_url="http://$server_ip:9003/webhook"

    # Verificação de tokens antes de configurar webhook
    print_info "Verificando credenciais..."

    # Verificar token do GitLab
    local gitlab_test
    gitlab_test=$(curl -s --header "PRIVATE-TOKEN: $gitlab_token" "http://$server_ip/api/v4/projects")
    
    if ! echo "$gitlab_test" | jq -e '.' >/dev/null 2>&1; then
        print_error "Token do GitLab inválido ou sem permissões"
        print_info "Verifique: 
1. O token está correto
2. O token tem permissões de API
3. O GitLab está acessível"
        return 1
    fi

    # Verificar token do GitHub
    local github_test
    github_test=$(curl -s -H "Authorization: token $github_token" "https://api.github.com/user")
    
    if ! echo "$github_test" | jq -e '.login' >/dev/null 2>&1; then
        print_error "Token do GitHub inválido ou sem permissões"
        print_info "Verifique:
1. O token está correto
2. O token tem permissões de repositório
3. Sua conexão com GitHub"
        return 1
    fi

    # Configurar serviço de webhook
    print_info "Configurando serviço de webhook..."
    setup_webhook_service "$gitlab_token" "$github_token" "$dest_repo"

    # Configurar webhook baseado na origem
    case $source in
        "gitlab")
            print_info "Configurando webhook do GitLab para $source_repo..."
            local gitlab_webhook_result
            gitlab_webhook_result=$(curl -s --request POST \
                --header "PRIVATE-TOKEN: $gitlab_token" \
                "http://$server_ip/api/v4/projects/${source_repo//\//%2F}/hooks" \
                --form "url=$webhook_url" \
                --form "push_events=true" \
                --form "tag_push_events=true")

            if ! echo "$gitlab_webhook_result" | jq -e '.url' >/dev/null 2>&1; then
                print_error "Falha ao configurar webhook do GitLab"
                print_error "Resposta: $gitlab_webhook_result"
                return 1
            fi
            ;;

        "github")
            print_info "Configurando webhook do GitHub para $source_repo..."
            local github_webhook_result
            github_webhook_result=$(curl -s -H "Authorization: token $github_token" \
                "https://api.github.com/repos/$source_repo/hooks" \
                -d "{
                    \"name\": \"web\",
                    \"active\": true,
                    \"events\": [\"push\", \"create\"],
                    \"config\": {
                        \"url\": \"$webhook_url\",
                        \"content_type\": \"json\"
                    }
                }")

            if ! echo "$github_webhook_result" | jq -e '.url' >/dev/null 2>&1; then
                print_error "Falha ao configurar webhook do GitHub"
                print_error "Resposta: $github_webhook_result"
                return 1
            fi
            ;;
        *)
            print_error "Origem inválida. Use 'gitlab' ou 'github'"
            return 1
            ;;
    esac

    print_success "Trigger de sincronização configurado com sucesso!"
    print_info "Webhook URL: $webhook_url"
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
        "sync")
            if [ "$1" = "--trigger" ]; then
                shift
                setup_sync_trigger "$@"
            else
                sync_repositories "$@"
            fi
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
            print_info "  github-now              - Executar backup imediatamente"
            print_info "  github-setup            - Configurar backup automático"
            print_info "  github-list             - Listar backups no GitHub"
            print_info "  sync SOURCE DEST REPO   - Sincronizar repositórios"
            print_info ""
            print_info "Exemplos de sync:"
            print_info "  GitLab para GitHub:"
            print_info "    nixx backup sync gitlab github grupo/projeto usuario/repo gitlab_token github_token"
            print_info ""
            print_info "  GitHub para GitLab:"
            print_info "    nixx backup sync github gitlab usuario/repo grupo/projeto gitlab_token github_token"
            return 1
            ;;
    esac
}