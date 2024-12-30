# src/commands/config.sh
#!/bin/bash

# Definir configuração
set_config() {
    local key=$1
    local value=$2

    if [ -z "$key" ] || [ -z "$value" ]; then
        print_error "Chave e valor são necessários"
        return 1
    fi

    # Verificar se a chave já existe
    if grep -q "^$key=" "$CONFIG_FILE"; then
        # Atualizar valor existente
        sed -i "s|^$key=.*|$key=\"$value\"|" "$CONFIG_FILE"
    else
        # Adicionar nova configuração
        echo "$key=\"$value\"" >> "$CONFIG_FILE"
    fi

    print_success "Configuração definida: $key = $value"
}

# Obter configuração
get_config() {
    local key=$1

    if [ -z "$key" ]; then
        print_error "Chave é necessária"
        return 1
    fi

    local value=$(grep "^$key=" "$CONFIG_FILE" | cut -d'=' -f2- | tr -d '"')
    if [ -z "$value" ]; then
        print_error "Configuração não encontrada: $key"
        return 1
    fi

    echo "$value"
}

# Listar configurações
list_config() {
    print_info "Configurações atuais:"
    cat "$CONFIG_FILE" | grep -v "^#"
}

# Importar configurações
import_config() {
    local file=$1

    if [ ! -f "$file" ]; then
        print_error "Arquivo não encontrado: $file"
        return 1
    fi

    cp "$file" "$CONFIG_FILE"
    print_success "Configurações importadas de $file"
}

# Exportar configurações
export_config() {
    local file=$1

    if [ -z "$file" ]; then
        print_error "Nome do arquivo é necessário"
        return 1
    fi

    cp "$CONFIG_FILE" "$file"
    print_success "Configurações exportadas para $file"
}

# Handler principal de configurações
handle_config() {
    local action=$1
    shift

    case $action in
        "set")
            set_config "$1" "$2"
            ;;
        "get")
            get_config "$1"
            ;;
        "list")
            list_config
            ;;
        "import")
            import_config "$1"
            ;;
        "export")
            export_config "$1"
            ;;
        *)
            print_error "Ação de configuração inválida: $action"
            return 1
            ;;
    esac
}