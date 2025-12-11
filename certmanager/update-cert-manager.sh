#!/usr/bin/env bash
# Script para atualizar cert-manager existente com configurações de certificados corporativos
# Use este script se o cert-manager já estiver instalado e você precisa adicionar suporte a Netskope

set -Eeuo pipefail

readonly NS="cert-manager"
readonly RELEASE="cert-manager"
readonly CHART="jetstack/cert-manager"
readonly CERT_SECRET_NAME="corporate-ca-certs"

info()  { printf '\e[32m[INFO]\e[0m  %s\n' "$*"; }
warn()  { printf '\e[33m[WARN]\e[0m %s\n' "$*"; }
err()   { printf '\e[31m[ERR ]\e[0m  %s\n' "$*"; }
success() { printf '\e[32m[✓]\e[0m    %s\n' "$*"; }

main() {
  info "=== Atualizando cert-manager com certificados corporativos ==="
  echo ""
  
  # 1. Verificar se o secret existe
  if ! kubectl -n "$NS" get secret "$CERT_SECRET_NAME" &>/dev/null; then
    err "Secret $CERT_SECRET_NAME não encontrado!"
    warn "Execute primeiro: ./fix-certmanager-netskope.sh"
    exit 1
  fi
  
  success "Secret $CERT_SECRET_NAME encontrado"
  
  # 2. Obter versão atual
  local current_version
  current_version=$(helm list -n "$NS" -o json | jq -r '.[0].app_version' 2>/dev/null || echo "")
  
  if [[ -z "$current_version" ]]; then
    err "Não foi possível detectar a versão do cert-manager instalado"
    exit 1
  fi
  
  info "Versão atual: $current_version"
  
  # 3. Criar valores customizados
  local values_file
  values_file=$(mktemp -t cert-manager-update-XXXXX.yaml)
  
  cat > "$values_file" <<EOF
installCRDs: true

# Configurações para controller
volumes:
- name: ca-certs
  secret:
    secretName: $CERT_SECRET_NAME
volumeMounts:
- name: ca-certs
  mountPath: /etc/ssl/certs/corporate-ca.crt
  subPath: ca.crt
  readOnly: true

extraEnv:
- name: SSL_CERT_FILE
  value: /etc/ssl/certs/corporate-ca.crt

# Configurações para webhook
webhook:
  volumes:
  - name: ca-certs
    secret:
      secretName: $CERT_SECRET_NAME
  volumeMounts:
  - name: ca-certs
    mountPath: /etc/ssl/certs/corporate-ca.crt
    subPath: ca.crt
    readOnly: true
  extraEnv:
  - name: SSL_CERT_FILE
    value: /etc/ssl/certs/corporate-ca.crt

# Configurações para cainjector
cainjector:
  volumes:
  - name: ca-certs
    secret:
      secretName: $CERT_SECRET_NAME
  volumeMounts:
  - name: ca-certs
    mountPath: /etc/ssl/certs/corporate-ca.crt
    subPath: ca.crt
    readOnly: true
  extraEnv:
  - name: SSL_CERT_FILE
    value: /etc/ssl/certs/corporate-ca.crt
EOF
  
  info "Valores customizados criados em: $values_file"
  
  # 4. Fazer upgrade do Helm release
  info "Executando helm upgrade..."
  
  if helm upgrade "$RELEASE" "$CHART" \
      --namespace "$NS" \
      --values "$values_file" \
      --reuse-values \
      --wait \
      --timeout 600s; then
    success "Upgrade concluído!"
  else
    err "Falha no upgrade"
    rm -f "$values_file"
    exit 1
  fi
  
  rm -f "$values_file"
  
  # 5. Aguardar pods reiniciarem
  info "Aguardando pods reiniciarem..."
  sleep 10
  
  kubectl -n "$NS" wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager --timeout=300s || {
    warn "Timeout aguardando pods. Verificando status manualmente..."
    kubectl -n "$NS" get pods
  }
  
  echo ""
  success "=== Atualização concluída ==="
  echo ""
  info "Verificando configuração..."
  kubectl -n "$NS" get pods
  echo ""
  info "Para testar, execute:"
  info "  ./test-deploy.sh"
  echo ""
}

main "$@"
