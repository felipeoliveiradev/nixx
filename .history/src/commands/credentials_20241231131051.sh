# src/commands/credentials.sh
#!/bin/bash

# Obter senha inicial do GitLab
get_gitlab_credentials() {
    print_info "Obtendo credenciais do GitLab..."
    
    # Verificar se o container do GitLab está rodando
    if ! docker ps | grep -q gitlab; then
        print_error "Container do GitLab não está rodando"
        return 1
    }

    print_info "Credenciais padrão do GitLab:"
    print_info "Usuário: root"
    
    # Tentar obter a senha inicial
    if [ -f "/etc/gitlab/initial_root_password" ]; then
        local password=$(sudo cat /etc/gitlab/initial_root_password | grep Password: | awk '{print $2}')
        print_info "Senha inicial: $password"
    else
        # Tentar obter de dentro do container
        docker exec gitlab cat /etc/gitlab/initial_root_password 2>/dev/null || {
            print_warning "Arquivo de senha inicial não encontrado"
            print_info "A senha padrão é 'password123' se não foi alterada durante a instalação"
        }
    fi

    local gitlab_url=$(docker port gitlab 80)
    print_info "URL de acesso: http://${gitlab_url}"
}

# Obter credenciais do Portainer
get_portainer_credentials() {
    print_info "Credenciais do Portainer:"
    print_info "Usuário: admin"
    print_info "Senha: Definida no primeiro acesso"
    
    local portainer_url=$(docker port portainer 9000)
    print_info "URL de acesso: http://${portainer_url}"
}

# Obter credenciais do Grafana
get_grafana_credentials() {
    print_info "Credenciais padrão do Grafana:"
    print_info "Usuário: admin"
    print_info "Senha: admin"
    
    local grafana_url=$(docker port grafana 3000)
    print_info "URL de acesso: http://${grafana_url}"
}

# Handler principal de credenciais
handle_credentials() {
    local service=$1
    
    case $service in
        "gitlab")
            get_gitlab_credentials
            ;;
        "portainer")
            get_portainer_credentials
            ;;
        "grafana")
            get_grafana_credentials
            ;;
        "all")
            print_info "=== Credenciais de todos os serviços ==="
            echo ""
            get_gitlab_credentials
            echo ""
            get_portainer_credentials
            echo ""
            get_grafana_credentials
            ;;
        *)
            print_error "Serviço não suportado: $service"
            echo "Serviços disponíveis: gitlab, portainer, grafana, all"
            return 1
            ;;
    esac
}