#!/bin/bash

# Obter senha inicial do GitLab
get_gitlab_credentials() {
    print_info "Obtendo credenciais do GitLab..."
    
    # Verificar se o container do GitLab está rodando
    if ! docker ps | grep -q gitlab; then
        print_error "Container do GitLab não está rodando"
        return 1
    fi

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

# Redefinir senha do GitLab
reset_gitlab_password() {
    local new_password=$1

    print_info "Redefinindo senha do GitLab..."
    
    # Verificar se o container está rodando
    if ! docker ps | grep -q gitlab; then
        print_error "Container do GitLab não está rodando"
        return 1
    fi

    # Redefinir a senha do root via Rails console
    docker exec -it gitlab gitlab-rails runner "
        user = User.find_by_username('root')
        user.password = '$new_password'
        user.password_confirmation = '$new_password'
        user.save!
        puts 'Senha atualizada com sucesso!'
    "

    print_success "Senha do GitLab redefinida"
    print_info "Novas credenciais:"
    print_info "Usuário: root"
    print_info "Senha: $new_password"
}

# Redefinir senha do Portainer
reset_portainer_password() {
    local new_password=$1

    print_info "Redefinindo senha do Portainer..."
    
    # Verificar se o container está rodando
    if ! docker ps | grep -q portainer; then
        print_error "Container do Portainer não está rodando"
        return 1
    fi

    # Parar o container atual
    docker stop portainer
    
    # Remover o container (mantendo o volume)
    docker rm portainer
    
    # Recriar o container com a nova senha
    docker run -d \
        -p 9000:9000 \
        --name portainer \
        --restart always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce \
        --admin-password-file <(echo -n "$new_password")

    print_success "Senha do Portainer redefinida"
    print_info "Novas credenciais:"
    print_info "Usuário: admin"
    print_info "Senha: $new_password"
}

# Redefinir senha do Grafana
reset_grafana_password() {
    local new_password=$1

    print_info "Redefinindo senha do Grafana..."
    
    # Verificar se o container está rodando
    if ! docker ps | grep -q grafana; then
        print_error "Container do Grafana não está rodando"
        return 1
    fi

    # Redefinir senha via API
    docker exec -it grafana grafana-cli admin reset-admin-password "$new_password"

    print_success "Senha do Grafana redefinida"
    print_info "Novas credenciais:"
    print_info "Usuário: admin"
    print_info "Senha: $new_password"
}

# Gerar senha aleatória segura
generate_secure_password() {
    # Gera uma senha de 16 caracteres com letras, números e símbolos
    local password=$(tr -dc 'A-Za-z0-9!@#$%^&*()' < /dev/urandom | head -c 16)
    echo $password
}

# Redefinir todas as senhas
reset_all_passwords() {
    local use_same_password=$1
    local password

    if [ "$use_same_password" = "true" ]; then
        password=$(generate_secure_password)
        print_info "Usando a mesma senha para todos os serviços: $password"
    fi

    print_info "=== Redefinindo todas as senhas ==="
    echo ""
    
    # GitLab
    local gitlab_pass=${password:-$(generate_secure_password)}
    reset_gitlab_password "$gitlab_pass"
    echo ""
    
    # Portainer
    local portainer_pass=${password:-$(generate_secure_password)}
    reset_portainer_password "$portainer_pass"
    echo ""
    
    # Grafana
    local grafana_pass=${password:-$(generate_secure_password)}
    reset_grafana_password "$grafana_pass"
}

# Handler principal de credenciais
handle_credentials() {
    local action=$1
    local service=$2
    local password=$3

    case $action in
        "show")
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
            ;;
        "reset")
            # Se não foi fornecida uma senha, gerar uma
            local new_password=${password:-$(generate_secure_password)}
            
            case $service in
                "gitlab")
                    reset_gitlab_password "$new_password"
                    ;;
                "portainer")
                    reset_portainer_password "$new_password"
                    ;;
                "grafana")
                    reset_grafana_password "$new_password"
                    ;;
                "all")
                    reset_all_passwords "${password:-false}"
                    ;;
                *)
                    print_error "Serviço não suportado: $service"
                    echo "Serviços disponíveis: gitlab, portainer, grafana, all"
                    return 1
                    ;;
            esac
            ;;
        *)
            print_error "Ação desconhecida: $action"
            echo "Ações disponíveis:"
            echo "  show SERVICE          - Mostrar credenciais do serviço"
            echo "  reset SERVICE [SENHA] - Redefinir senha do serviço"
            return 1
            ;;
    esac
}