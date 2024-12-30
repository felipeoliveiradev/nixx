# src/commands/backup.sh
#!/bin/bash

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
            print_error "Ação de backup inválida: $action"
            return 1
            ;;
    esac
}