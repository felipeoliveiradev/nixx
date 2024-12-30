# src/commands/runners.sh
#!/bin/bash

# Configurar GitLab Runner
setup_gitlab_runner() {
    local token=$1
    local url=$2
    local tags=$3
    local executor=${4:-docker}
    local name=$(hostname)

    print_info "Configurando GitLab Runner..."

    # Instalar GitLab Runner
    curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | bash
    apt-get update && apt-get install -y gitlab-runner

    # Registrar Runner
    gitlab-runner register \
        --non-interactive \
        --url "$url" \
        --registration-token "$token" \
        --executor "$executor" \
        --docker-image "alpine:latest" \
        --description "$name" \
        --tag-list "$tags" \
        --run-untagged="true" \
        --locked="false" \
        --docker-privileged="true" \
        --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" \
        --docker-volumes "/cache"

    # Configurar permissões
    usermod -aG docker gitlab-runner

    # Reiniciar serviço
    systemctl enable gitlab-runner
    systemctl restart gitlab-runner

    print_success "GitLab Runner configurado com sucesso"
}

# Configurar GitHub Actions Runner
setup_github_runner() {
    local token=$1
    local url=$2
    local name=${3:-$(hostname)}
    local labels=${4:-"self-hosted,Linux,X64"}

    print_info "Configurando GitHub Actions Runner..."

    # Criar diretório para o runner
    mkdir -p /opt/actions-runner
    cd /opt/actions-runner

    # Baixar runner
    curl -o actions-runner-linux-x64.tar.gz -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz
    tar xzf actions-runner-linux-x64.tar.gz

    # Configurar runner
    ./config.sh --url "$url" --token "$token" --name "$name" --labels "$labels" --unattended

    # Instalar como serviço
    ./svc.sh install
    ./svc.sh start

    print_success "GitHub Actions Runner configurado com sucesso"
}

# Configurar Portainer Agent
setup_portainer_agent() {
    local portainer_url=$1
    local agent_port=${2:-9001}

    print_info "Configurando Portainer Agent..."

    docker service create \
        --name portainer_agent \
        --network monitoring \
        --publish ${agent_port}:9001 \
        --mode global \
        --mount type=bind,src=//var/run/docker.sock,dst=/var/run/docker.sock \
        --mount type=bind,src=//var/lib/docker/volumes,dst=/var/lib/docker/volumes \
        portainer/agent:latest

    print_success "Portainer Agent configurado - Adicione este node em ${portainer_url} usando a porta ${agent_port}"
}

# Configurar Datadog Agent
setup_datadog() {
    local api_key=$1
    local tags=${2:-"env:prod"}

    print_info "Configurando Datadog Agent..."

    # Instalar agent via Docker
    docker run -d \
        --name dd-agent \
        --network monitoring \
        -v /var/run/docker.sock:/var/run/docker.sock:ro \
        -v /proc/:/host/proc/:ro \
        -v /sys/fs/cgroup/:/host/sys/fs/cgroup:ro \
        -e DD_API_KEY="${api_key}" \
        -e DD_TAGS="${tags}" \
        -e DD_LOGS_ENABLED=true \
        -e DD_APM_ENABLED=true \
        gcr.io/datadoghq/agent:latest

    print_success "Datadog Agent configurado com sucesso"
}

# Handler principal de runners e agentes
handle_runners() {
    local action=$1
    shift

    case $action in
        "gitlab")
            if [ $# -lt 2 ]; then
                print_error "Uso: nixx runner gitlab TOKEN URL [TAGS] [EXECUTOR]"
                return 1
            fi
            setup_gitlab_runner "$@"
            ;;
        "github")
            if [ $# -lt 2 ]; then
                print_error "Uso: nixx runner github TOKEN URL [NAME] [LABELS]"
                return 1
            fi
            setup_github_runner "$@"
            ;;
        "portainer")
            if [ $# -lt 1 ]; then
                print_error "Uso: nixx runner portainer URL [PORT]"
                return 1
            fi
            setup_portainer_agent "$@"
            ;;
        "datadog")
            if [ $# -lt 1 ]; then
                print_error "Uso: nixx runner datadog API_KEY [TAGS]"
                return 1
            fi
            setup_datadog "$@"
            ;;
        *)
            print_error "Ação desconhecida: $action"
            return 1
            ;;
    esac
}