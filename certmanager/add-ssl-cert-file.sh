#!/usr/bin/env bash
# Script simples para adicionar apenas a variável SSL_CERT_FILE
# Os volumes já foram configurados via Helm
set -Eeuo pipefail

readonly NS="cert-manager"
readonly CERT_FILE="/etc/ssl/certs/corporate-ca.crt"

info()  { printf '\e[32m[INFO]\e[0m  %s\n' "$*"; }
success() { printf '\e[32m[✓]\e[0m    %s\n' "$*"; }

main() {
  info "Adicionando variável SSL_CERT_FILE aos deployments..."
  
  for deploy in cert-manager cert-manager-webhook cert-manager-cainjector; do
    info "Configurando $deploy..."
    kubectl -n "$NS" set env deployment/"$deploy" SSL_CERT_FILE="$CERT_FILE"
    success "$deploy configurado"
  done
  
  info "Aguardando rollout..."
  kubectl -n "$NS" rollout status deployment/cert-manager --timeout=60s
  kubectl -n "$NS" rollout status deployment/cert-manager-webhook --timeout=60s
  kubectl -n "$NS" rollout status deployment/cert-manager-cainjector --timeout=60s
  
  success "Variável SSL_CERT_FILE adicionada a todos os deployments!"
  
  echo ""
  info "Pods atualizados:"
  kubectl -n "$NS" get pods
  
  echo ""
  info "Verificando SSL_CERT_FILE no controller:"
  kubectl -n "$NS" get pod -l app.kubernetes.io/component=controller \
    -o jsonpath='{.items[0].spec.containers[0].env[?(@.name=="SSL_CERT_FILE")]}' | jq '.'
}

main "$@"
