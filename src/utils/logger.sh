# src/utils/logger.sh
#!/bin/bash

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Funções de logging
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

print_info() {
    local message=$1
    echo -e "${BLUE}[INFO]${NC} $message"
    log "INFO" "$message"
}

print_success() {
    local message=$1
    echo -e "${GREEN}[SUCCESS]${NC} $message"
    log "SUCCESS" "$message"
}

print_error() {
    local message=$1
    echo -e "${RED}[ERROR]${NC} $message"
    log "ERROR" "$message"
}

print_warning() {
    local message=$1
    echo -e "${YELLOW}[WARN]${NC} $message"
    log "WARN" "$message"
}