# FireFly ArgoCD Deployment

Este diretório contém as configurações necessárias para fazer o deployment do Hyperledger FireFly no Kubernetes usando ArgoCD, suportando tanto arquiteturas **x86_64** quanto **ARM64**.

## 📋 Pré-requisitos

### Cluster Kubernetes
- Kubernetes 1.24+
- ArgoCD instalado e configurado
- Traefik ou outro Ingress Controller (para exposição de serviços)
- cert-manager com ClusterIssuer `selfsigned-ca` configurado

### Dependências Externas
- **PostgreSQL**: Banco de dados para o FireFly Core
  - URL: `postgres://postgres:<password>@postgres-postgresql.database.svc:5432/`
  - Databases necessários: `firefly`, `firefly_gateway`
- **Besu/Ethereum Node**: Node blockchain para o Signer
  - URL: `http://besu-node1-rpc.paladin.svc:8545`
  - Chain ID: `1337`

### Repositórios Git
- https://github.com/hyperledger/firefly-helm-charts.git - Charts oficiais do FireFly
- https://github.com/italoag/firefly-helm-charts.git - Charts customizados (fork com suporte ARM64)
- https://github.com/italoag/bacen-drex-k8s-dev-stack.git - Repositório atual

## 📁 Estrutura de Diretórios

```
argocd/
├── applications/          # Definições de ArgoCD Applications
│   ├── ipfs-app.yaml                        # IPFS storage
│   ├── firefly-signer-app.yaml              # FireFly Signer (x86_64)
│   ├── firefly-signer-arm64-app.yaml        # FireFly Signer (ARM64)
│   ├── firefly-gateway-app.yaml             # FireFly Gateway (x86_64)
│   ├── firefly-gateway-arm64-app.yaml       # FireFly Gateway (ARM64)
│   ├── firefly-multiparty-app.yaml          # FireFly Multiparty (x86_64) - inline values
│   ├── firefly-multiparty-arm64-app.yaml    # FireFly Multiparty (ARM64) - inline values
│   ├── multiparty-app.yaml                  # FireFly Multiparty (x86_64) - external values
│   ├── multiparty-app-arm64.yaml            # FireFly Multiparty (ARM64) - external values
│   ├── firefly-ingress-app.yaml             # Ingress HTTPS
│   └── firefly-cors-middleware-app.yaml     # CORS Middleware
├── values/               # Arquivos de valores para Helm (usados por alguns apps)
│   ├── multiparty.yaml              # Values para multiparty x86_64
│   ├── multiparty-arm64.yaml        # Values para multiparty ARM64
│   ├── gateway.yaml                 # Values para gateway x86_64
│   ├── gateway-arm64.yaml           # Values para gateway ARM64
│   ├── ingress.yaml                 # Configuração de ingress
│   └── firefly-cors-middleware.yaml # Configuração CORS
└── backup/               # Arquivos de backup (não são usados)
```

## 🎯 Modos de Deployment

O FireFly pode ser deployado em dois modos principais:

### 1. **Gateway Mode** (Multiorg, Single Node)
- Um único node FireFly que gerencia múltiplas organizações
- Mais simples para desenvolvimento e testes
- `multipartyEnabled: false`

### 2. **Multiparty Mode** (True Multiparty)
- Múltiplos nodes FireFly independentes
- Cada organização tem seu próprio node
- `multipartyEnabled: true`

## 🚀 Procedimento de Deployment

### Ordem de Deployment Recomendada

1. **IPFS** (storage layer)
2. **FireFly Signer** (blockchain transaction signer)
3. **FireFly Core** (Gateway ou Multiparty)
4. **CORS Middleware** (opcional)
5. **Ingress** (exposição externa)

### Deploy para x86_64

#### 1. Deploy IPFS
```bash
kubectl apply -f argocd/applications/ipfs-app.yaml
```

Aguarde o IPFS estar saudável:
```bash
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=ipfs -n firefly --timeout=300s
```

#### 2. Deploy FireFly Signer
```bash
kubectl apply -f argocd/applications/firefly-signer-app.yaml
```

Aguarde o Signer estar saudável:
```bash
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=firefly-signer -n firefly --timeout=300s
```

#### 3a. Deploy FireFly Gateway Mode (escolha uma opção)

**Opção A: Usando valores inline** (recomendado - autocontido)
```bash
kubectl apply -f argocd/applications/firefly-gateway-app.yaml
```

#### 3b. Deploy FireFly Multiparty Mode (alternativa)

**Opção A: Usando valores inline** (recomendado - autocontido)
```bash
kubectl apply -f argocd/applications/firefly-multiparty-app.yaml
```

**Opção B: Usando valores externos**
```bash
kubectl apply -f argocd/applications/multiparty-app.yaml
```

#### 4. Deploy Ingress e Middleware (Opcional)
```bash
kubectl apply -f argocd/applications/firefly-cors-middleware-app.yaml
kubectl apply -f argocd/applications/firefly-ingress-app.yaml
```

### Deploy para ARM64

O procedimento é idêntico, mas use os arquivos com sufixo `-arm64`:

#### 1. Deploy IPFS
```bash
kubectl apply -f argocd/applications/ipfs-app.yaml  # Mesmo arquivo
```

#### 2. Deploy FireFly Signer ARM64
```bash
kubectl apply -f argocd/applications/firefly-signer-arm64-app.yaml
```

#### 3a. Deploy FireFly Gateway Mode ARM64

**Opção A: Usando valores inline** (recomendado)
```bash
kubectl apply -f argocd/applications/firefly-gateway-arm64-app.yaml
```

#### 3b. Deploy FireFly Multiparty Mode ARM64

**Opção A: Usando valores inline** (recomendado)
```bash
kubectl apply -f argocd/applications/firefly-multiparty-arm64-app.yaml
```

**Opção B: Usando valores externos**
```bash
kubectl apply -f argocd/applications/multiparty-app-arm64.yaml
```

#### 4. Deploy Ingress e Middleware
```bash
kubectl apply -f argocd/applications/firefly-cors-middleware-app.yaml
kubectl apply -f argocd/applications/firefly-ingress-app.yaml
```

## ⚙️ Configurações Importantes

### Diferenças entre Arquivos de Aplicação

| Arquivo | Abordagem | Vantagens | Desvantagens |
|---------|-----------|-----------|--------------|
| `firefly-*-app.yaml` | Valores inline | Autocontido, versionamento simples | Arquivo maior |
| `multiparty-app*.yaml` | Valores externos | Arquivo menor | Dependência de arquivos externos |

**Recomendação**: Use os arquivos com valores inline (`firefly-*-app.yaml`) por serem mais fáceis de manter.

### Imagens Docker

#### x86_64 (Imagens oficiais)
- Core: `ghcr.io/hyperledger/firefly:latest`
- Signer: `ghcr.io/hyperledger/firefly-signer:latest`
- EVMConnect: `ghcr.io/hyperledger/firefly-evmconnect:latest`
- DataExchange: `ghcr.io/hyperledger/firefly-dataexchange-https:latest`
- Tokens ERC1155: `ghcr.io/hyperledger/firefly-tokens-erc1155:latest`
- Tokens ERC20/721: `ghcr.io/hyperledger/firefly-tokens-erc20-erc721:latest`

#### ARM64 (Imagens customizadas)
- Core: `ghcr.io/italoag/firefly:latest-arm64`
- Signer: `ghcr.io/italoag/firefly-signer:latest`
- EVMConnect: `ghcr.io/italoag/firefly-evmconnect:latest-arm64`
- DataExchange: `ghcr.io/italoag/firefly-dataexchange-https:latest-arm64`
- Tokens ERC1155: `ghcr.io/italoag/firefly-tokens-erc1155:latest-arm64`
- Tokens ERC20/721: `ghcr.io/italoag/firefly-tokens-erc20-erc721:latest-arm64`

### Endpoints Importantes

**Gateway Mode:**
- API: `https://firefly.cluster.eita.cloud`
- UI: `https://firefly.cluster.eita.cloud/ui/`

**Multiparty Mode:**
- API: `https://firefly.cluster.eita.cloud`
- UI: `https://firefly.cluster.eita.cloud/ui/`

**Serviços Internos:**
- IPFS API: `http://ipfs.firefly.svc:5001`
- IPFS Gateway: `http://ipfs.firefly.svc:8080`
- Signer: `http://firefly-signer.firefly.svc:8545`

## 🔍 Verificação e Troubleshooting

### Verificar Status das Aplicações ArgoCD
```bash
kubectl get applications -n argocd
```

### Verificar Pods no Namespace FireFly
```bash
kubectl get pods -n firefly
```

### Verificar Logs do FireFly Core
```bash
# Gateway Mode
kubectl logs -n firefly-gateway deployment/firefly-gateway -f

# Multiparty Mode
kubectl logs -n firefly deployment/firefly -f
```

### Verificar Logs do Signer
```bash
kubectl logs -n firefly deployment/firefly-signer -f
```

### Verificar Logs do IPFS
```bash
kubectl logs -n firefly deployment/ipfs -f
```

### Testar Conectividade

**IPFS:**
```bash
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n firefly -- \
  curl http://ipfs.firefly.svc:5001/api/v0/version
```

**FireFly API:**
```bash
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n firefly -- \
  curl http://firefly:5000/api/v1/status
```

**Signer:**
```bash
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n firefly -- \
  curl -X POST http://firefly-signer.firefly.svc:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

### Problemas Comuns

#### Pod FireFly não inicia
1. Verificar se o PostgreSQL está acessível
2. Verificar se o initContainer de criação de database foi executado com sucesso
3. Verificar se o DataExchange está rodando (`wait-for-dx` initContainer)

#### Sandbox não está disponível
O Sandbox foi removido das configurações de produção por questões de segurança. Se necessário para desenvolvimento, habilite manualmente editando `sandbox.enabled: true` nos valores.

#### IPFS não responde
1. Verificar se o PersistentVolume foi criado
2. Verificar se o pod está com status `Running`
3. Verificar logs para erros de permissão

#### Signer não conecta ao Besu
1. Verificar se o Besu está rodando: `kubectl get pods -n paladin`
2. Verificar conectividade: `kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- curl http://besu-node1-rpc.paladin.svc:8545`
3. Verificar se o `chainId` está correto

## 🔐 Segurança

### Senhas e Credenciais
- **PostgreSQL**: Atualmente hardcoded nos arquivos. **IMPORTANTE**: Migrar para Secrets do Kubernetes
- **TLS Certificates**: Gerados automaticamente pelo cert-manager com o ClusterIssuer `selfsigned-ca`

### Recomendações
1. ❌ **NUNCA** habilitar Sandbox em produção
2. ✅ Usar Secrets do Kubernetes para senhas
3. ✅ Usar certificados válidos (Let's Encrypt) em produção
4. ✅ Habilitar autenticação e autorização no FireFly Core

## 🔄 Sincronização ArgoCD

Todas as aplicações estão configuradas com:
- `prune: true` - Remove recursos que não estão mais nos manifestos
- `selfHeal: true` - Corrige automaticamente drift de configuração
- `CreateNamespace: true` - Cria namespace automaticamente

Para forçar sincronização manual:
```bash
argocd app sync firefly
argocd app sync ipfs
argocd app sync firefly-signer
argocd app sync firefly-ingress
```

## 📊 Monitoramento

As seguintes métricas estão habilitadas:
- FireFly Core: Prometheus metrics em `/metrics`
- IPFS: Prometheus metrics habilitadas
- Signer: Prometheus metrics habilitadas

ServiceMonitors podem ser habilitados para integração com Prometheus Operator.

## 🗑️ Remoção Completa

Para remover completamente o FireFly do cluster:

```bash
# Remover aplicações ArgoCD
kubectl delete application firefly -n argocd
kubectl delete application firefly-gateway -n argocd
kubectl delete application firefly-signer -n argocd
kubectl delete application ipfs -n argocd
kubectl delete application firefly-ingress -n argocd
kubectl delete application firefly-cors-middleware -n argocd

# Remover namespaces
kubectl delete namespace firefly
kubectl delete namespace firefly-gateway

# Remover PVCs (dados serão perdidos!)
kubectl delete pvc -n firefly --all
```

## 📝 Notas Adicionais

### Arquivos Duplicados
Existem duas abordagens para deployment:
1. **Inline values** (`firefly-*-app.yaml`) - Valores Helm dentro do arquivo da aplicação
2. **External values** (`multiparty-app*.yaml`) - Valores Helm em arquivos separados em `values/`

A abordagem inline é recomendada por ser autocontida e mais fácil de versionar.

### Sandbox
Os arquivos de configuração do Sandbox foram removidos (`firefly-sandbox*.yaml`) pois o Sandbox não deve ser deployado em ambientes de produção.

### Backup
O diretório `backup/` contém configurações antigas que podem ser removidas se não forem mais necessárias.
