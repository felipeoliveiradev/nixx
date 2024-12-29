# Remover o stack
docker stack rm gitlab-server

# Aguardar
sleep 30

# Remover volumes antigos do GitLab
docker volume rm gitlab-server_gitlab_config gitlab-server_gitlab_logs gitlab-server_gitlab_data

# Criar novos volumes
docker volume create gitlab-server_gitlab_config
docker volume create gitlab-server_gitlab_logs
docker volume create gitlab-server_gitlab_data

# Reimplantar
docker stack deploy -c docker-compose.gitlab-server.yml gitlab-server

# Verificar status
docker service ls