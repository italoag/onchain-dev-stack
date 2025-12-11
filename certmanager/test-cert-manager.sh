#!/usr/bin/env bash
# Script de teste para validar o deployment do cert-manager
# Testa todas as funcionalidades e configurações

set -Eeuo pipefail

# --- Cores ---
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m' # No Color

# --- Variáveis ---
readonly NS="cert-manager"
readonly CERT_SECRET_NAME="corporate-ca-certs"

# --- Funções de Log ---
info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[✗]${NC} $*"; }
test_header() { echo -e "\n${GREEN}=== $* ===${NC}"; }

# Contadores de teste
TESTS_PASSED=0
TESTS_FAILED=0

# Função para executar teste
run_test() {
  local test_name=$1
  local test_command=$2
  
  echo -n "  Testando $test_name... "
  
  if eval "$test_command" &>/dev/null; then
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
  else
    echo -e "${RED}✗${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
}

# Função para validar deployment
validate_deployment() {
  local deploy_name=$1
  
  # Verifica se deployment existe
  if ! kubectl -n "$NS" get deployment "$deploy_name" &>/dev/null; then
    err "Deployment $deploy_name não encontrado"
    return 1
  fi
  
  # Verifica se tem o volume ca-certs
  if ! kubectl -n "$NS" get deployment "$deploy_name" -o yaml | grep -q "name: ca-certs"; then
    warn "Deployment $deploy_name não tem volume ca-certs configurado"
    return 1
  fi
  
  # Verifica se tem o volumeMount
  if ! kubectl -n "$NS" get deployment "$deploy_name" -o yaml | grep -q "mountPath: /etc/ssl/certs/corporate-ca.crt"; then
    warn "Deployment $deploy_name não tem volumeMount configurado"
    return 1
  fi
  
  # Verifica se tem a variável SSL_CERT_FILE
  if ! kubectl -n "$NS" get deployment "$deploy_name" -o yaml | grep -q "SSL_CERT_FILE"; then
    warn "Deployment $deploy_name não tem variável SSL_CERT_FILE configurada"
    return 1
  fi
  
  info "Deployment $deploy_name configurado corretamente"
  return 0
}

# Testes
main() {
  echo ""
  test_header "INICIANDO TESTES DE VALIDAÇÃO DO CERT-MANAGER"
  
  # Teste 1: Namespace existe
  test_header "1. Verificando Namespace"
  run_test "namespace cert-manager existe" "kubectl get namespace $NS"
  
  # Teste 2: Pods estão rodando
  test_header "2. Verificando Pods"
  run_test "pods do cert-manager estão Running" "kubectl -n $NS get pods -l app.kubernetes.io/instance=cert-manager --no-headers | grep -q 'Running'"
  
  local pod_count
  pod_count=$(kubectl -n "$NS" get pods -l app.kubernetes.io/instance=cert-manager --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$pod_count" -ge 3 ]]; then
    info "  Encontrados $pod_count pods (esperado: 3)"
  else
    warn "  Encontrados apenas $pod_count pods (esperado: 3)"
  fi
  
  # Teste 3: Secret de certificados existe
  test_header "3. Verificando Secret de Certificados"
  if run_test "secret $CERT_SECRET_NAME existe" "kubectl -n $NS get secret $CERT_SECRET_NAME"; then
    # Valida conteúdo do secret
    local issuer
    issuer=$(kubectl -n "$NS" get secret "$CERT_SECRET_NAME" -o jsonpath='{.data.ca\.crt}' | base64 -d | openssl x509 -noout -issuer 2>/dev/null | sed 's/issuer=//' || echo "")
    if [[ -n "$issuer" ]]; then
      info "  Emissor do certificado: $issuer"
      
      # Verifica se é Netskope
      if echo "$issuer" | grep -qi "netskope"; then
        info "  ✓ Certificado Netskope detectado"
      fi
    fi
  fi
  
  # Teste 4: CRDs instalados
  test_header "4. Verificando CRDs"
  run_test "CRD certificates.cert-manager.io" "kubectl get crd certificates.cert-manager.io"
  run_test "CRD issuers.cert-manager.io" "kubectl get crd issuers.cert-manager.io"
  run_test "CRD clusterissuers.cert-manager.io" "kubectl get crd clusterissuers.cert-manager.io"
  
  # Teste 5: Validação detalhada dos deployments
  test_header "5. Verificando Configuração dos Deployments"
  
  echo ""
  echo "  Validando cert-manager controller..."
  validate_deployment "cert-manager"
  
  echo ""
  echo "  Validando cert-manager webhook..."
  validate_deployment "cert-manager-webhook"
  
  echo ""
  echo "  Validando cert-manager cainjector..."
  validate_deployment "cert-manager-cainjector"
  
  # Teste 6: Variáveis de ambiente nos pods
  test_header "6. Verificando Variáveis de Ambiente nos Pods"
  
  local controller_pod
  controller_pod=$(kubectl -n "$NS" get pods -l app.kubernetes.io/component=controller -o name 2>/dev/null | head -1)
  
  if [[ -n "$controller_pod" ]]; then
    local ssl_cert_file
    ssl_cert_file=$(kubectl -n "$NS" get "$controller_pod" -o jsonpath='{.spec.containers[0].env[?(@.name=="SSL_CERT_FILE")].value}' 2>/dev/null || echo "")
    
    if [[ "$ssl_cert_file" == "/etc/ssl/certs/corporate-ca.crt" ]]; then
      info "  ✓ Variável SSL_CERT_FILE configurada corretamente: $ssl_cert_file"
      TESTS_PASSED=$((TESTS_PASSED + 1))
    else
      err "  ✗ Variável SSL_CERT_FILE não configurada ou incorreta: '$ssl_cert_file'"
      TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
  else
    warn "  Pod controller não encontrado para verificação"
  fi
  
  # Teste 7: ClusterIssuer
  test_header "7. Verificando ClusterIssuer"
  
  if run_test "ClusterIssuer letsencrypt-certmanager existe" "kubectl get clusterissuer letsencrypt-certmanager"; then
    # Verifica status
    local issuer_status
    issuer_status=$(kubectl get clusterissuer letsencrypt-certmanager -o jsonpath='{.status.conditions[0]}' 2>/dev/null || echo "")
    
    if [[ -n "$issuer_status" ]]; then
      local status_type
      local status_value
      local reason
      local message
      
      status_type=$(echo "$issuer_status" | jq -r '.type' 2>/dev/null || echo "")
      status_value=$(echo "$issuer_status" | jq -r '.status' 2>/dev/null || echo "")
      reason=$(echo "$issuer_status" | jq -r '.reason' 2>/dev/null || echo "")
      message=$(echo "$issuer_status" | jq -r '.message' 2>/dev/null || echo "")
      
      echo ""
      echo "  Status do ClusterIssuer:"
      echo "    Type: $status_type"
      echo "    Status: $status_value"
      echo "    Reason: $reason"
      
      if [[ "$status_value" == "True" ]]; then
        info "  ✓ ClusterIssuer está READY!"
        TESTS_PASSED=$((TESTS_PASSED + 1))
      else
        if echo "$message" | grep -qi "example.com"; then
          err "  ✗ Email inválido detectado (example.com)"
          warn "  Execute: EMAIL='seu-email@dominio.com' ./deploy-cert-manager.sh"
        elif echo "$message" | grep -qi "certificate"; then
          err "  ✗ Erro de certificado detectado"
          warn "  O cert-manager ainda não consegue acessar o Let's Encrypt"
          warn "  Mensagem: $message"
        else
          warn "  ⚠ ClusterIssuer não está Ready"
          warn "  Mensagem: $message"
        fi
        TESTS_FAILED=$((TESTS_FAILED + 1))
      fi
    else
      warn "  Não foi possível obter status do ClusterIssuer"
    fi
    
    # Verifica email configurado
    local email
    email=$(kubectl get clusterissuer letsencrypt-certmanager -o jsonpath='{.spec.acme.email}' 2>/dev/null || echo "")
    
    if [[ -n "$email" ]]; then
      if [[ "$email" == *"example.com"* ]]; then
        err "  ✗ Email inválido: $email (example.com não é permitido)"
      else
        info "  ✓ Email válido configurado: $email"
      fi
    fi
  fi
  
  # Teste 8: Conectividade com Let's Encrypt
  test_header "8. Verificando Conectividade com Let's Encrypt"
  
  echo ""
  echo "  Testando acesso a acme-v02.api.letsencrypt.org..."
  
  if curl --connect-timeout 10 -s -o /dev/null -w "%{http_code}" "https://acme-v02.api.letsencrypt.org/directory" | grep -q "200"; then
    info "  ✓ Acesso ao Let's Encrypt funcionando"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    warn "  ⚠ Não foi possível acessar o Let's Encrypt (isso pode ser normal em redes corporativas)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
  
  # Verifica certificado usado
  local cert_issuer
  cert_issuer=$(openssl s_client -showcerts -connect acme-v02.api.letsencrypt.org:443 -servername acme-v02.api.letsencrypt.org </dev/null 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null | sed 's/issuer=//' || echo "")
  
  if [[ -n "$cert_issuer" ]]; then
    if echo "$cert_issuer" | grep -qi "netskope\|zscaler\|proxy"; then
      warn "  ⚠ Detectado proxy corporativo: $cert_issuer"
      info "  O cert-manager está configurado para lidar com isso"
    else
      info "  ✓ Certificado direto do Let's Encrypt"
    fi
  fi
  
  # Resumo Final
  test_header "RESUMO DOS TESTES"
  
  echo ""
  echo "  Testes executados: $((TESTS_PASSED + TESTS_FAILED))"
  echo -e "  ${GREEN}Passou: $TESTS_PASSED${NC}"
  echo -e "  ${RED}Falhou: $TESTS_FAILED${NC}"
  echo ""
  
  if [[ $TESTS_FAILED -eq 0 ]]; then
    info "🎉 TODOS OS TESTES PASSARAM!"
    info ""
    info "O cert-manager está configurado corretamente e pronto para uso."
    info ""
    info "Para criar um certificado, adicione estas anotações ao seu Ingress:"
    info "  annotations:"
    info "    cert-manager.io/cluster-issuer: \"letsencrypt-certmanager\""
    info "    kubernetes.io/tls-acme: \"true\""
    echo ""
    return 0
  else
    err "❌ ALGUNS TESTES FALHARAM"
    echo ""
    warn "Verifique os erros acima e execute novamente o deployment se necessário:"
    warn "  ./deploy-cert-manager.sh"
    echo ""
    return 1
  fi
}

# Executa
main "$@"
