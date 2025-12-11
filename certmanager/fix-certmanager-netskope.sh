#!/usr/bin/env bash
# Script para adicionar certificados corporativos Netskope ao cert-manager
# Corrige erro: "x509: certificate signed by unknown authority"

set -Eeuo pipefail

# --- Configurações ---
readonly NS="cert-manager"
readonly CERT_SECRET_NAME="corporate-ca-certs"
readonly TEMP_CERT_DIR="/tmp/certmanager-certs-$$"
readonly LETSENCRYPT_URL="https://acme-v02.api.letsencrypt.org"

# --- Funções de Log ---
info()  { printf '\e[32m[INFO]\e[0m  %s\n' "$*"; }
warn()  { printf '\e[33m[WARN]\e[0m %s\n' "$*"; }
err()   { printf '\e[31m[ERR ]\e[0m  %s\n' "$*"; }
success() { printf '\e[32m[✓]\e[0m    %s\n' "$*"; }

# Trap para limpeza
cleanup() {
  [[ -d "$TEMP_CERT_DIR" ]] && rm -rf "$TEMP_CERT_DIR"
}
trap cleanup EXIT

# Extrai certificados do Let's Encrypt (que passam pelo Netskope)
extract_netskope_cert() {
  info "Extraindo certificado Netskope do servidor Let's Encrypt..."
  
  mkdir -p "$TEMP_CERT_DIR"
  
  local domain
  domain=$(echo "$LETSENCRYPT_URL" | sed -E 's|^https://([^/]+).*|\1|')
  
  # Extrai toda a cadeia de certificados
  if timeout 10 openssl s_client -showcerts -connect "$domain:443" -servername "$domain" </dev/null 2>/dev/null | \
     awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/ {print}' > "$TEMP_CERT_DIR/netskope-chain.pem"; then
    
    if [[ -s "$TEMP_CERT_DIR/netskope-chain.pem" ]]; then
      # Valida que é um certificado válido
      if openssl x509 -noout -in "$TEMP_CERT_DIR/netskope-chain.pem" &>/dev/null; then
        local issuer
        issuer=$(openssl x509 -noout -issuer -in "$TEMP_CERT_DIR/netskope-chain.pem" | sed 's/issuer=//')
        
        success "Certificado extraído com sucesso"
        info "Emissor: $issuer"
        
        # Verifica se é Netskope
        if echo "$issuer" | grep -qi "netskope"; then
          success "Confirmado certificado Netskope"
          return 0
        else
          warn "Certificado não parece ser da Netskope, mas continuando..."
          return 0
        fi
      fi
    fi
  fi
  
  err "Falha ao extrair certificado"
  return 1
}

# Verifica se o secret já existe
check_existing_secret() {
  info "Verificando se secret '$CERT_SECRET_NAME' já existe..."
  
  if kubectl -n "$NS" get secret "$CERT_SECRET_NAME" &>/dev/null; then
    warn "Secret '$CERT_SECRET_NAME' já existe"
    return 0
  else
    info "Secret não existe, será criado"
    return 1
  fi
}

# Cria ou atualiza o secret com certificados
create_or_update_secret() {
  local cert_file=$1
  
  info "Criando/atualizando secret '$CERT_SECRET_NAME' no namespace '$NS'..."
  
  # Verifica se namespace existe
  if ! kubectl get namespace "$NS" &>/dev/null; then
    err "Namespace '$NS' não existe. Execute deploy-cert-manager.sh primeiro."
    return 1
  fi
  
  # Cria ou atualiza o secret
  kubectl -n "$NS" create secret generic "$CERT_SECRET_NAME" \
    --from-file=ca.crt="$cert_file" \
    --dry-run=client -o yaml | kubectl apply -f -
  
  success "Secret '$CERT_SECRET_NAME' criado/atualizado"
}

# Verifica se os deployments do cert-manager têm o volume montado
check_volume_mounts() {
  info "Verificando se deployments têm o volume configurado..."
  
  local deployments=("cert-manager" "cert-manager-webhook" "cert-manager-cainjector")
  local needs_update=false
  
  for deploy in "${deployments[@]}"; do
    if kubectl -n "$NS" get deployment "$deploy" &>/dev/null; then
      # Verifica se tem o volume ca-certs
      if ! kubectl -n "$NS" get deployment "$deploy" -o yaml | grep -q "name: ca-certs"; then
        warn "Deployment '$deploy' não tem volume 'ca-certs' configurado"
        needs_update=true
      else
        success "Deployment '$deploy' já tem volume configurado"
      fi
    fi
  done
  
  if [[ "$needs_update" == "true" ]]; then
    return 1
  else
    return 0
  fi
}

# Atualiza deployments para montar o certificado
update_cert_manager_deployments() {
  info "Atualizando deployments do cert-manager para usar certificados corporativos..."
  
  # Lista de deployments para atualizar
  local deployments=("cert-manager" "cert-manager-webhook" "cert-manager-cainjector")
  
  for deploy in "${deployments[@]}"; do
    if ! kubectl -n "$NS" get deployment "$deploy" &>/dev/null; then
      warn "Deployment '$deploy' não encontrado, pulando..."
      continue
    fi
    
    info "Atualizando deployment: $deploy"
    
    # Identifica o nome do container baseado no deployment
    local container_name
    case "$deploy" in
      cert-manager-webhook)
        container_name="cert-manager-webhook"
        ;;
      cert-manager-cainjector)
        container_name="cert-manager-cainjector"
        ;;
      *)
        container_name="cert-manager-controller"
        ;;
    esac
    
    # Cria patch JSON para adicionar volume, volumeMount E variável de ambiente
    cat > "$TEMP_CERT_DIR/${deploy}-patch.yaml" <<EOF
spec:
  template:
    spec:
      volumes:
      - name: ca-certs
        secret:
          secretName: $CERT_SECRET_NAME
      containers:
      - name: $container_name
        env:
        - name: SSL_CERT_FILE
          value: /etc/ssl/certs/corporate-ca.crt
        volumeMounts:
        - name: ca-certs
          mountPath: /etc/ssl/certs/corporate-ca.crt
          subPath: ca.crt
          readOnly: true
EOF
    
    # Aplica o patch (merge estratégico)
    if kubectl -n "$NS" patch deployment "$deploy" --patch-file "$TEMP_CERT_DIR/${deploy}-patch.yaml"; then
      success "Deployment '$deploy' atualizado"
    else
      warn "Falha ao atualizar deployment '$deploy'"
    fi
  done
}

# Reinicia pods do cert-manager para aplicar mudanças
restart_cert_manager_pods() {
  info "Reiniciando pods do cert-manager..."
  
  # Deleta pods para forçar recriação com novos certificados
  kubectl -n "$NS" delete pods -l app.kubernetes.io/instance=cert-manager
  
  info "Aguardando pods reiniciarem..."
  sleep 5
  
  # Aguarda pods ficarem prontos
  local max_wait=60
  local waited=0
  
  while [[ $waited -lt $max_wait ]]; do
    local ready_pods
    ready_pods=$(kubectl -n "$NS" get pods -l app.kubernetes.io/instance=cert-manager \
                 -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' | grep -c "Running" || echo "0")
    
    if [[ "$ready_pods" -ge 3 ]]; then
      success "Todos os pods estão rodando"
      return 0
    fi
    
    echo -n "."
    sleep 5
    waited=$((waited + 5))
  done
  
  warn "Timeout aguardando pods. Verifique manualmente: kubectl -n $NS get pods"
  return 1
}

# Verifica o status do ClusterIssuer
check_cluster_issuer() {
  info "Verificando status do ClusterIssuer..."
  
  # Aguarda um pouco para o cert-manager processar
  sleep 10
  
  local issuer_status
  issuer_status=$(kubectl get clusterissuer letsencrypt-certmanager -o jsonpath='{.status.conditions[0]}' 2>/dev/null || echo "")
  
  if [[ -n "$issuer_status" ]]; then
    echo "$issuer_status" | jq -r '"\(.type): \(.status) - \(.reason): \(.message)"' 2>/dev/null || echo "$issuer_status"
    
    # Verifica se está Ready
    if echo "$issuer_status" | jq -r '.status' 2>/dev/null | grep -q "True"; then
      success "ClusterIssuer está funcionando!"
      return 0
    else
      warn "ClusterIssuer ainda com problemas"
      return 1
    fi
  else
    warn "Não foi possível verificar status do ClusterIssuer"
    return 1
  fi
}

# Mostra logs do cert-manager para diagnóstico
show_cert_manager_logs() {
  info "Últimos logs do cert-manager controller:"
  echo ""
  
  local controller_pod
  controller_pod=$(kubectl -n "$NS" get pods -l app.kubernetes.io/component=controller -o name | head -1)
  
  if [[ -n "$controller_pod" ]]; then
    kubectl -n "$NS" logs "$controller_pod" --tail=20 | grep -i "error\|certificate\|tls" || \
      kubectl -n "$NS" logs "$controller_pod" --tail=10
  else
    warn "Pod do controller não encontrado"
  fi
}

# Diagnóstico completo
run_diagnostics() {
  echo ""
  info "=== DIAGNÓSTICO DO PROBLEMA ==="
  echo ""
  
  # 1. Verifica se namespace existe
  if ! kubectl get namespace "$NS" &>/dev/null; then
    err "Namespace '$NS' não existe!"
    err "Execute primeiro: ./deploy-cert-manager.sh"
    return 1
  fi
  success "Namespace '$NS' existe"
  
  # 2. Verifica pods
  info "Status dos pods:"
  kubectl -n "$NS" get pods -l app.kubernetes.io/instance=cert-manager
  echo ""
  
  # 3. Verifica secret de certificados
  if kubectl -n "$NS" get secret "$CERT_SECRET_NAME" &>/dev/null; then
    success "Secret '$CERT_SECRET_NAME' existe"
  else
    warn "Secret '$CERT_SECRET_NAME' NÃO existe (este é o problema!)"
  fi
  echo ""
  
  # 4. Verifica ClusterIssuer
  info "Status do ClusterIssuer:"
  kubectl get clusterissuer letsencrypt-certmanager -o jsonpath='{.status.conditions[0]}' | jq . 2>/dev/null || \
    kubectl get clusterissuer letsencrypt-certmanager -o yaml | grep -A 5 "conditions:"
  echo ""
  
  # 5. Mostra logs recentes
  show_cert_manager_logs
  echo ""
}

# Função principal
main() {
  echo ""
  info "=== Fix cert-manager com Netskope ==="
  info "=== Corrige: x509: certificate signed by unknown authority ==="
  echo ""
  
  # Verifica dependências
  for cmd in kubectl openssl jq; do
    if ! command -v "$cmd" &>/dev/null; then
      err "Comando '$cmd' não encontrado. Instale-o primeiro."
      if [[ "$cmd" == "jq" ]]; then
        warn "macOS: brew install jq"
      fi
      exit 1
    fi
  done
  
  # Executa diagnóstico inicial
  run_diagnostics
  
  echo ""
  info "=== INICIANDO CORREÇÃO ==="
  echo ""
  
  # 1. Extrai certificado Netskope
  if ! extract_netskope_cert; then
    err "Falha ao extrair certificado. Verifique sua conexão."
    exit 1
  fi
  echo ""
  
  # 2. Cria/atualiza secret
  if ! create_or_update_secret "$TEMP_CERT_DIR/netskope-chain.pem"; then
    err "Falha ao criar secret"
    exit 1
  fi
  echo ""
  
  # 3. Verifica e atualiza deployments se necessário
  if ! check_volume_mounts; then
    warn "Deployments precisam ser atualizados para montar os certificados"
    echo ""
    update_cert_manager_deployments
    echo ""
  fi
  
  # 4. Reinicia pods
  restart_cert_manager_pods
  echo ""
  
  # 5. Verifica resultado
  info "=== VERIFICAÇÃO FINAL ==="
  echo ""
  
  if check_cluster_issuer; then
    echo ""
    success "==================================="
    success "✅ PROBLEMA CORRIGIDO COM SUCESSO!"
    success "==================================="
    echo ""
    info "O cert-manager agora pode acessar o Let's Encrypt através do proxy Netskope"
    echo ""
  else
    echo ""
    warn "========================================"
    warn "⚠️  Correção aplicada, mas ainda há problemas"
    warn "========================================"
    echo ""
    info "Execute novamente o diagnóstico:"
    info "  kubectl describe clusterissuer letsencrypt-certmanager"
    echo ""
    info "Ou verifique logs:"
    info "  kubectl -n $NS logs -l app.kubernetes.io/component=controller --tail=50"
    echo ""
  fi
}

# Executa
main "$@"
