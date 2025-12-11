#!/usr/bin/env bash
# Script para adicionar certificados corporativos ao Docker/Rancher Desktop
# Funciona SEM SUDO - apenas no contexto do usuário
# Resolve problemas de TLS com proxies corporativos como Netskope, Zscaler, etc.

set -Eeuo pipefail

# --- Configurações ---
readonly TEMP_DIR="/tmp/docker-certs-$$"
readonly DOCKER_CERT_DIR="${HOME}/.docker/certs.d"
readonly TEST_REGISTRY="${1:-ghcr.io}"

# Rancher Desktop específico
readonly RANCHER_CONFIG="${HOME}/.local/share/rancher-desktop"
readonly RANCHER_LIMA_CONFIG="${HOME}/.lima/rancher-desktop"

# --- Funções de Log ---
info()  { printf '\e[32m[INFO]\e[0m  %s\n' "$*" >&2; }
warn()  { printf '\e[33m[WARN]\e[0m %s\n' "$*" >&2; }
err()   { printf '\e[31m[ERR ]\e[0m  %s\n' "$*" >&2; }
success() { printf '\e[32m[✓]\e[0m    %s\n' "$*" >&2; }

# Detecta qual runtime Docker está sendo usado
detect_docker_runtime() {
  if docker context ls 2>/dev/null | grep -q "rancher-desktop"; then
    echo "rancher-desktop"
  elif [[ -d "/Applications/Docker.app" ]] && pgrep -x "Docker" >/dev/null 2>&1; then
    echo "docker-desktop"
  elif [[ -d "${HOME}/.rd" ]] || [[ -d "$RANCHER_CONFIG" ]]; then
    echo "rancher-desktop"
  elif docker info 2>/dev/null | grep -qi "lima"; then
    echo "lima"
  else
    echo "unknown"
  fi
}

# Extrai certificados de um domínio
extract_certificates() {
  local domain=$1
  local output_file=$2
  
  info "Extraindo certificados de $domain..."
  
  # Extrai toda a cadeia de certificados
  if timeout 10 openssl s_client -showcerts -connect "$domain:443" -servername "$domain" </dev/null 2>/dev/null | \
     awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/ {print}' > "$output_file"; then
    
    if [[ -s "$output_file" ]] && openssl x509 -noout -in "$output_file" &>/dev/null; then
      local issuer
      issuer=$(openssl x509 -noout -issuer -in "$output_file" 2>/dev/null | sed 's/issuer=//')
      success "Certificados extraídos"
      info "Emissor: $issuer"
      
      # Detecta se é proxy corporativo
      if echo "$issuer" | grep -qi "netskope\|zscaler\|proxy\|corporate"; then
        warn "🔒 Detectado proxy corporativo: ${issuer}"
      fi
      
      return 0
    fi
  fi
  
  err "Falha ao extrair certificados de $domain"
  return 1
}

# Adiciona certificado ao Keychain do USUÁRIO (sem sudo)
add_to_user_keychain() {
  local cert_file=$1
  
  info "Adicionando certificado ao Keychain do usuário..."
  
  # Usa o Keychain do login do usuário (não requer sudo)
  if security add-trusted-cert -d -r trustRoot -k "${HOME}/Library/Keychains/login.keychain-db" "$cert_file" 2>/dev/null; then
    success "Certificado adicionado ao Keychain do usuário"
    return 0
  else
    warn "Não foi possível adicionar ao Keychain (pode já existir ou requer autorização)"
    return 1
  fi
}

# Adiciona certificado ao diretório Docker padrão
add_to_docker_certs() {
  local cert_file=$1
  local registry=$2
  
  info "Configurando certificado para registry: $registry"
  
  local registry_dir="$DOCKER_CERT_DIR/$registry"
  mkdir -p "$registry_dir"
  
  cp "$cert_file" "$registry_dir/ca.crt"
  chmod 644 "$registry_dir/ca.crt"
  
  success "Certificado instalado em: $registry_dir/ca.crt"
}

# Adiciona certificado ao Rancher Desktop (Lima VM)
add_to_rancher_desktop() {
  local cert_file=$1
  local registry=$2
  
  info "Configurando certificado para Rancher Desktop..."
  
  # 1. Adiciona ao diretório Docker padrão
  add_to_docker_certs "$cert_file" "$registry"
  
  # 2. Adiciona ao Keychain do usuário (Rancher Desktop respeita isso)
  add_to_user_keychain "$cert_file"
  
  # 3. Copia para dentro da VM Lima do Rancher Desktop
  if [[ -d "$RANCHER_LIMA_CONFIG" ]]; then
    info "Copiando certificado para VM Lima..."
    
    # Cria script de instalação dentro da VM
    cat > "$TEMP_DIR/install-cert.sh" <<'EOF'
#!/bin/sh
CERT_FILE="/tmp/host/corporate-ca.crt"
if [ -f "$CERT_FILE" ]; then
  mkdir -p /usr/local/share/ca-certificates
  cp "$CERT_FILE" /usr/local/share/ca-certificates/corporate-ca.crt
  update-ca-certificates 2>/dev/null || true
  echo "Certificado instalado na VM"
fi
EOF
    chmod +x "$TEMP_DIR/install-cert.sh"
    
    # Copia certificado para local compartilhado
    mkdir -p "$RANCHER_LIMA_CONFIG/host"
    cp "$cert_file" "$RANCHER_LIMA_CONFIG/host/corporate-ca.crt"
    
    # Tenta executar dentro da VM via rdctl
    if command -v rdctl &>/dev/null; then
      rdctl shell <<EOF 2>/dev/null || warn "Não foi possível executar na VM (pode requerer senha)"
sudo mkdir -p /usr/local/share/ca-certificates
sudo cp /tmp/host/corporate-ca.crt /usr/local/share/ca-certificates/ 2>/dev/null || true
sudo update-ca-certificates 2>/dev/null || true
EOF
      success "Certificado copiado para VM Lima"
    else
      warn "rdctl não encontrado, pule esta etapa"
    fi
  fi
  
  # 4. Instruções para reiniciar
  echo ""
  warn "⚠️  IMPORTANTE: Reinicie o Rancher Desktop para aplicar as mudanças:"
  warn ""
  warn "   Opção 1 (Interface):"
  warn "   1. Clique no ícone do Rancher Desktop"
  warn "   2. Selecione 'Quit Rancher Desktop'"
  warn "   3. Abra novamente o Rancher Desktop"
  warn ""
  warn "   Opção 2 (Terminal):"
  warn "   rdctl shutdown && open -a 'Rancher Desktop'"
  echo ""
}

# Adiciona certificado ao Docker Desktop (sem sudo)
add_to_docker_desktop() {
  local cert_file=$1
  local registry=$2
  
  info "Configurando certificado para Docker Desktop..."
  
  # 1. Adiciona ao diretório Docker
  add_to_docker_certs "$cert_file" "$registry"
  
  # 2. Adiciona ao Keychain do usuário (Docker Desktop respeita isso)
  add_to_user_keychain "$cert_file"
  
  echo ""
  warn "⚠️  Reinicie o Docker Desktop:"
  warn "   killall Docker && open -a Docker"
  echo ""
}

# Mostra informações do certificado
show_certificate_info() {
  local domain=$1
  
  info "Analisando certificado de $domain..."
  
  local cert_info
  cert_info=$(timeout 10 openssl s_client -showcerts -connect "$domain:443" -servername "$domain" </dev/null 2>/dev/null | \
              openssl x509 -noout -text 2>/dev/null)
  
  if [[ -n "$cert_info" ]]; then
    echo "$cert_info" | grep -E "Issuer:|Subject:|Not Before|Not After" | sed 's/^/  /'
  fi
}

# Testa conectividade
test_docker_registry() {
  local registry=$1
  
  info "Testando acesso ao registry..."
  
  # Testa com um simples pull
  if timeout 20 docker pull "${registry}/hello-world:latest" &>/dev/null; then
    success "Teste bem-sucedido!"
    return 0
  else
    warn "Teste falhou. Certifique-se de reiniciar o Docker/Rancher Desktop"
    return 1
  fi
}

# Função principal
main() {
  echo ""
  info "=== Fix Docker Certificates (SEM SUDO) ==="
  info "=== Para Proxies Corporativos (Netskope, Zscaler, etc.) ==="
  echo ""
  
  # Verifica dependências
  for cmd in openssl docker; do
    if ! command -v "$cmd" &>/dev/null; then
      err "Comando '$cmd' não encontrado. Instale-o primeiro."
      exit 1
    fi
  done
  
  # Detecta runtime Docker
  local runtime
  runtime=$(detect_docker_runtime)
  info "Runtime detectado: $runtime"
  echo ""
  
  # Cria diretório temporário
  mkdir -p "$TEMP_DIR"
  trap "rm -rf '$TEMP_DIR'" EXIT
  
  # Mostra informações do certificado
  show_certificate_info "$TEST_REGISTRY"
  echo ""
  
  # Extrai certificados
  local cert_file="$TEMP_DIR/corporate-ca.crt"
  if ! extract_certificates "$TEST_REGISTRY" "$cert_file"; then
    err "Falha ao extrair certificados. Verifique sua conexão."
    exit 1
  fi
  
  echo ""
  info "Instalando certificados..."
  echo ""
  
  # Aplica configuração baseada no runtime
  case "$runtime" in
    rancher-desktop)
      add_to_rancher_desktop "$cert_file" "$TEST_REGISTRY"
      ;;
    docker-desktop)
      add_to_docker_desktop "$cert_file" "$TEST_REGISTRY"
      ;;
    *)
      warn "Runtime desconhecido, aplicando configuração genérica..."
      add_to_docker_certs "$cert_file" "$TEST_REGISTRY"
      ;;
  esac
  
  echo ""
  success "=== Configuração Concluída ==="
  echo ""
  info "Após reiniciar o Docker/Rancher Desktop, teste com:"
  info "  docker pull ${TEST_REGISTRY}/italoag/public/postgres:17.4"
  echo ""
  info "Se ainda tiver problemas:"
  info "  1. Verifique se reiniciou completamente"
  info "  2. Execute: docker system info"
  info "  3. Verifique: ls -la ~/.docker/certs.d/${TEST_REGISTRY}/"
  echo ""
}

# Executa
main "$@"