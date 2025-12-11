#!/usr/bin/env bash
# Script simplificado para adicionar certificados Netskope ao Docker
set -e

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err() { echo -e "${RED}[ERROR]${NC} $*"; }

# Variáveis
REGISTRY="${1:-ghcr.io}"
TEMP_CERT="/tmp/netskope-ca.crt"
DOCKER_CERT_DIR="$HOME/.docker/certs.d/$REGISTRY"

info "=== Configurando certificados corporativos para Docker ==="
echo ""

# 1. Extrair certificado do registry
info "Extraindo certificado de $REGISTRY..."
if openssl s_client -showcerts -connect "$REGISTRY:443" -servername "$REGISTRY" </dev/null 2>/dev/null | \
   sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' > "$TEMP_CERT"; then
  
  if [ -s "$TEMP_CERT" ]; then
    info "✅ Certificado extraído com sucesso"
    
    # Mostra informações do certificado
    ISSUER=$(openssl x509 -noout -issuer -in "$TEMP_CERT" 2>/dev/null | sed 's/issuer=//')
    info "Emissor: $ISSUER"
  else
    err "Arquivo de certificado vazio"
    exit 1
  fi
else
  err "Falha ao extrair certificado"
  exit 1
fi

echo ""

# 2. Adicionar ao Docker
info "Adicionando certificado ao Docker para registry $REGISTRY..."
mkdir -p "$DOCKER_CERT_DIR"
cp "$TEMP_CERT" "$DOCKER_CERT_DIR/ca.crt"
info "✅ Certificado copiado para: $DOCKER_CERT_DIR/ca.crt"

echo ""

# 3. Adicionar ao Keychain do macOS (requer senha de administrador)
info "Adicionando certificado ao macOS Keychain (pode solicitar senha)..."
if sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$TEMP_CERT" 2>/dev/null; then
  info "✅ Certificado adicionado ao Keychain"
else
  warn "Certificado já existe no Keychain ou houve erro (pode ignorar se já foi adicionado antes)"
fi

echo ""

# 4. Verificar se está usando Rancher Desktop ou Docker Desktop
if pgrep -f "rancher-desktop" > /dev/null; then
  warn "🐮 Detectado Rancher Desktop"
  warn ""
  warn "Para o Rancher Desktop, você precisa configurar manualmente:"
  warn "1. Abra Rancher Desktop"
  warn "2. Vá em Preferences > Container Engine > General"
  warn "3. Em 'Allowed Images', certifique-se que 'ghcr.io' está permitido"
  warn "4. Ou adicione o certificado ao containerd diretamente:"
  echo ""
  info "Comando para containerd (copie e execute):"
  echo ""
  echo "sudo mkdir -p /etc/rancher/k3s/containerd"
  echo "sudo cp $TEMP_CERT /etc/rancher/k3s/containerd/netskope-ca.crt"
  echo ""
  warn "Depois reinicie o Rancher Desktop"
  
elif pgrep -f "Docker" > /dev/null || [ -d "/Applications/Docker.app" ]; then
  info "🐳 Detectado Docker Desktop"
  warn ""
  warn "⚠️  IMPORTANTE: Reinicie o Docker Desktop:"
  warn "   1. Clique no ícone do Docker na barra de menu"
  warn "   2. Selecione 'Quit Docker Desktop'"
  warn "   3. Abra o Docker Desktop novamente"
  warn ""
  warn "Ou execute:"
  echo "   killall Docker && open -a Docker"
else
  warn "Não foi possível detectar Docker Desktop ou Rancher Desktop em execução"
fi

echo ""
info "=== Configuração Concluída ==="
echo ""
info "Após reiniciar o Docker/Rancher, teste com:"
echo "  docker pull $REGISTRY/italoag/public/postgres:17.4"
echo ""

# Limpar
rm -f "$TEMP_CERT"
