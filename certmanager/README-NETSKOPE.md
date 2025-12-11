# Cert-Manager com Suporte a Netskope - Guia Completo

## 📋 Resumo das Alterações

O script `deploy-cert-manager.sh` foi atualizado para suportar automaticamente proxies corporativos como Netskope, Zscaler, etc.

### Principais Mudanças:

1. **Variável de ambiente `SSL_CERT_FILE`** adicionada automaticamente a todos os componentes
2. **Email padrão válido** (`eita@gmail.com` em vez de `admin@example.com`)
3. **Validação de email** para prevenir uso de domínios proibidos
4. **Montagem correta** dos certificados corporativos

## 🚀 Como Usar

### Deploy Limpo (Recomendado)

```bash
cd Projects/lab/onchain-dev-stack/certmanager

# Com email personalizado
EMAIL="cluster@eita.cloud" ./deploy-cert-manager.sh

# Ou use o padrão
./deploy-cert-manager.sh
```

### Reinstalação Completa

Se já tiver o cert-manager instalado e precisar reinstalar:

```bash
FORCE_REINSTALL=true EMAIL="seu-email@dominio.com" ./deploy-cert-manager.sh
```

### Atualização de Instalação Existente

Se já tiver cert-manager instalado e só precisar adicionar suporte a certificados corporativos:

```bash
# 1. Extrair e configurar certificados Netskope
./fix-certmanager-netskope.sh

# 2. Atualizar via Helm (alternativa)
./update-cert-manager.sh
```

## 🔍 Validação

Execute o script de teste para verificar se tudo está configurado corretamente:

```bash
./test-deploy.sh
```

O script verifica:
- ✓ Namespace e pods
- ✓ Secret de certificados
- ✓ CRDs instalados
- ✓ Configuração dos deployments
- ✓ Variáveis de ambiente
- ✓ Status do ClusterIssuer
- ✓ Conectividade com Let's Encrypt

## 📝 O Que Foi Corrigido

### 1. Problema Original
```
Failed to register ACME account: Get "https://acme-v02.api.letsencrypt.org/directory": 
tls: failed to verify certificate: x509: certificate signed by unknown authority
```

**Causa**: O cert-manager não tinha o certificado CA da Netskope no trust store.

### 2. Solução Implementada

#### A. Extração Automática de Certificados
O script agora:
- Detecta automaticamente proxies corporativos (Netskope, Zscaler, etc.)
- Extrai o certificado CA corretamente
- Cria um Kubernetes Secret com o certificado

#### B. Configuração via Helm Values
```yaml
# Controller
volumes:
- name: ca-certs
  secret:
    secretName: corporate-ca-certs
volumeMounts:
- name: ca-certs
  mountPath: /etc/ssl/certs/corporate-ca.crt
  subPath: ca.crt
  readOnly: true
extraEnv:
- name: SSL_CERT_FILE
  value: /etc/ssl/certs/corporate-ca.crt

# (mesmo para webhook e cainjector)
```

#### C. Validação de Email
```bash
# Não permite mais example.com
if [[ "$email_to_use" == *"example.com"* ]]; then
  warn "Email 'example.com' não é permitido pelo Let's Encrypt!"
  email_to_use="italo@gmail.com"
fi
```

## 🛠️ Scripts Disponíveis

| Script | Descrição |
|--------|-----------|
| `deploy-cert-manager.sh` | Deployment completo com suporte a certificados corporativos |
| `fix-certmanager-netskope.sh` | Corrige instalação existente adicionando certificados |
| `update-cert-manager.sh` | Atualiza via Helm uma instalação existente |
| `test-deploy.sh` | Valida a configuração completa |
| `fix-docker-certificates.sh` | Adiciona certificados ao Docker/Rancher Desktop |
| `fix-docker-netskope.sh` | Versão simplificada para Docker |

## 📊 Verificação Manual

### Verificar Secret
```bash
kubectl -n cert-manager get secret corporate-ca-certs -o yaml
kubectl -n cert-manager get secret corporate-ca-certs -o jsonpath='{.data.ca\.crt}' | base64 -d | openssl x509 -noout -issuer
```

### Verificar Variável de Ambiente
```bash
kubectl -n cert-manager get pod -l app.kubernetes.io/component=controller \
  -o jsonpath='{.items[0].spec.containers[0].env}' | jq .
```

### Verificar ClusterIssuer
```bash
kubectl get clusterissuer letsencrypt-certmanager
kubectl describe clusterissuer letsencrypt-certmanager
```

### Verificar Logs
```bash
kubectl -n cert-manager logs -l app.kubernetes.io/component=controller --tail=50
```

## ✅ Checklist de Validação

- [ ] Namespace `cert-manager` existe
- [ ] 3 pods estão Running
- [ ] Secret `corporate-ca-certs` existe com certificado Netskope
- [ ] Deployments têm volume `ca-certs` montado
- [ ] Deployments têm variável `SSL_CERT_FILE` configurada
- [ ] CRDs estão instalados
- [ ] ClusterIssuer está READY (status: True)
- [ ] Email configurado não é `example.com`

## 🐛 Troubleshooting

### Problema: ClusterIssuer com erro de certificado

```bash
# 1. Verificar se o secret tem o certificado correto
kubectl -n cert-manager get secret corporate-ca-certs -o jsonpath='{.data.ca\.crt}' | base64 -d | openssl x509 -noout -issuer

# 2. Se o emissor NÃO for Netskope, extrair novamente:
openssl s_client -showcerts -connect acme-v02.api.letsencrypt.org:443 -servername acme-v02.api.letsencrypt.org </dev/null 2>/dev/null | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/ {print}' > /tmp/netskope-cert.pem

# 3. Atualizar o secret:
kubectl -n cert-manager create secret generic corporate-ca-certs --from-file=ca.crt=/tmp/netskope-cert.pem --dry-run=client -o yaml | kubectl apply -f -

# 4. Reiniciar pods:
kubectl -n cert-manager delete pods -l app.kubernetes.io/instance=cert-manager
```

### Problema: Email example.com

```bash
# Atualizar email do ClusterIssuer
kubectl patch clusterissuer letsencrypt-certmanager --type='json' \
  -p='[{"op": "replace", "path": "/spec/acme/email", "value": "seu-email@dominio.com"}]'
```

### Problema: Variável SSL_CERT_FILE não configurada

```bash
# Reinstalar com configurações corretas
FORCE_REINSTALL=true ./deploy-cert-manager.sh
```

## 📚 Referências

- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Let's Encrypt ACME](https://letsencrypt.org/docs/acme-protocol/)
- [Netskope SSL Inspection](https://docs.netskope.com/)

## 🎯 Próximos Passos

Após validação bem-sucedida:

1. **Criar certificado para Ingress**:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-certmanager"
    kubernetes.io/tls-acme: "true"
spec:
  tls:
  - hosts:
    - example.com
    secretName: example-tls
  rules:
  - host: example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-service
            port:
              number: 80
```

2. **Monitorar certificado**:
```bash
kubectl get certificate -n my-namespace
kubectl describe certificate example-tls -n my-namespace
```

---

**Última atualização**: 11 de dezembro de 2025
**Versão cert-manager**: v1.17.1
**Status**: ✅ Totalmente funcional com Netskope
