#!/usr/bin/env bash
# Script para adicionar volume e variável SSL_CERT_FILE aos deployments
set -Eeuo pipefail

readonly NS="cert-manager"
readonly SECRET_NAME="corporate-ca-certs"
readonly MOUNT_PATH="/etc/ssl/certs"
readonly CERT_FILE="$MOUNT_PATH/corporate-ca.crt"

info()  { printf '\e[32m[INFO]\e[0m  %s\n' "$*"; }
success() { printf '\e[32m[✓]\e[0m    %s\n' "$*"; }
error() { printf '\e[31m[ERR]\e[0m  %s\n' "$*"; }

add_volume_and_env() {
  local deploy="$1"
  
  info "Configurando $deploy..."
  
  # Primeiro, adiciona o volume se não existir
  if ! kubectl -n "$NS" get deployment "$deploy" -o jsonpath='{.spec.template.spec.volumes[?(@.name=="corporate-ca-certs")]}' | grep -q corporate; then
    info "Adicionando volume corporate-ca-certs..."
    kubectl -n "$NS" patch deployment "$deploy" --type='json' -p='[
      {
        "op": "add",
        "path": "/spec/template/spec/volumes/-",
        "value": {
          "name": "corporate-ca-certs",
          "secret": {
            "secretName": "'"$SECRET_NAME"'",
            "defaultMode": 420
          }
        }
      }
    ]'
  fi
  
  # Segundo, adiciona o volumeMount se não existir
  if ! kubectl -n "$NS" get deployment "$deploy" -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.name=="corporate-ca-certs")]}' | grep -q corporate; then
    info "Adicionando volumeMount..."
    kubectl -n "$NS" patch deployment "$deploy" --type='json' -p='[
      {
        "op": "add",
        "path": "/spec/template/spec/containers/0/volumeMounts/-",
        "value": {
          "name": "corporate-ca-certs",
          "mountPath": "'"$MOUNT_PATH"'",
          "readOnly": true
        }
      }
    ]'
  fi
  
  # Terceiro, adiciona a variável de ambiente se não existir
  if ! kubectl -n "$NS" get deployment "$deploy" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="SSL_CERT_FILE")]}' | grep -q SSL_CERT_FILE; then
    info "Adicionando variável SSL_CERT_FILE..."
    kubectl -n "$NS" patch deployment "$deploy" --type='json' -p='[
      {
        "op": "add",
        "path": "/spec/template/spec/containers/0/env/-",
        "value": {
          "name": "SSL_CERT_FILE",
          "value": "'"$CERT_FILE"'"
        }
      }
    ]'
  fi
  
  success "$deploy configurado"
}

main() {
  info "Verificando se Secret $SECRET_NAME existe..."
  if ! kubectl -n "$NS" get secret "$SECRET_NAME" &>/dev/null; then
    error "Secret $SECRET_NAME não encontrado no namespace $NS"
    error "Execute primeiro: ./fix-certmanager-netskope.sh"
    exit 1
  fi
  
  info "Adicionando volume e variável SSL_CERT_FILE aos deployments..."
  
  # Deployments que precisam do certificado corporativo
  for deploy in cert-manager cert-manager-webhook cert-manager-cainjector; do
    add_volume_and_env "$deploy"
  done
  
  info "Aguardando rollout dos deployments..."
  kubectl -n "$NS" rollout status deployment/cert-manager --timeout=60s
  kubectl -n "$NS" rollout status deployment/cert-manager-webhook --timeout=60s  
  kubectl -n "$NS" rollout status deployment/cert-manager-cainjector --timeout=60s
  
  success "Todos os deployments atualizados!"
  
  echo ""
  info "Status dos pods:"
  kubectl -n "$NS" get pods
  
  echo ""
  info "Verificando configuração no controller:"
  echo "Volume:"
  kubectl -n "$NS" get pod -l app.kubernetes.io/component=controller \
    -o jsonpath='{.items[0].spec.volumes[?(@.name=="corporate-ca-certs")]}' | jq '.'
  echo "VolumeMount:"
  kubectl -n "$NS" get pod -l app.kubernetes.io/component=controller \
    -o jsonpath='{.items[0].spec.containers[0].volumeMounts[?(@.name=="corporate-ca-certs")]}' | jq '.'
  echo "Variável SSL_CERT_FILE:"
  kubectl -n "$NS" get pod -l app.kubernetes.io/component=controller \
    -o jsonpath='{.items[0].spec.containers[0].env[?(@.name=="SSL_CERT_FILE")]}' | jq '.'
}

main "$@"
