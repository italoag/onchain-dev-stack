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
├── README.md                                # Este documento
├── applications/                            # Definições de ArgoCD Applications
│   ├── README.md                            # Documentação antiga (substituída)
│   ├── ipfs-app.yaml                        # IPFS storage (Kubo v0.35.0)
│   ├── firefly-signer-app.yaml              # Transaction Signer x86_64
│   ├── firefly-signer-arm64-app.yaml        # Transaction Signer ARM64
│   ├── firefly-gateway-app.yaml             # Gateway Mode x86_64 (valores inline)
│   ├── firefly-gateway-arm64-app.yaml       # Gateway Mode ARM64 (valores inline)
│   ├── firefly-multiparty-app.yaml          # Multiparty Mode x86_64 (valores inline)
│   ├── firefly-multiparty-arm64-app.yaml    # Multiparty Mode ARM64 (valores inline)
│   ├── multiparty-app.yaml                  # Multiparty Mode x86_64 (valores externos)
│   ├── multiparty-app-arm64.yaml            # Multiparty Mode ARM64 (valores externos)
│   ├── firefly-ingress-app.yaml             # Ingress HTTPS com TLS
│   └── firefly-cors-middleware-app.yaml     # Traefik CORS Middleware
├── values/                                  # Valores Helm e manifestos Kubernetes
│   ├── multiparty.yaml                      # Helm values Multiparty x86_64
│   ├── multiparty-arm64.yaml                # Helm values Multiparty ARM64
│   ├── gateway.yaml                         # Helm values Gateway x86_64 (não usado)
│   ├── gateway-arm64.yaml                   # Helm values Gateway ARM64 (não usado)
│   ├── ingress.yaml                         # Manifesto Ingress Kubernetes
│   ├── firefly-cors-middleware.yaml         # Manifesto Traefik Middleware
│   ├── firefly-config.yaml                  # ConfigMap geral (não usado)
│   └── ipfs.yaml                            # Config IPFS (não usado)
└── backup/                                  # Configurações antigas/experimentais
    ├── firefly-api-rewrite-middleware.yaml
    ├── firefly-gateway-argocd-final.yaml
    ├── firefly-gateway-argocd.yaml
    ├── firefly-gateway-direct.yaml
    ├── firefly-gateway-fixed.yaml
    └── firefly-gateway-inline.yaml
```

### Detalhamento dos Arquivos

#### applications/

**IPFS (Storage Layer)**
- `ipfs-app.yaml`: Deploy do IPFS Kubo v0.35.0 com PersistentVolume de 10Gi. Usa `fullnameOverride: ipfs` para criar serviço `ipfs.firefly.svc`. Chart oficial Hyperledger.

**FireFly Signer (Transaction Manager)**
- `firefly-signer-app.yaml`: Signer x86_64 conectado ao Besu (`besu-node1-rpc.paladin.svc:8545`). Usa imagem oficial `ghcr.io/hyperledger/firefly-signer:latest`.
- `firefly-signer-arm64-app.yaml`: Versão ARM64 com `nodeSelector: kubernetes.io/arch: arm64` e imagem customizada `ghcr.io/italoag/firefly-signer:latest`.

**FireFly Gateway Mode (Single Node, Multi-Org)**
- `firefly-gateway-app.yaml`: Gateway x86_64 com `multipartyEnabled: false`. Valores Helm inline. Inclui Core, DataExchange, EVMConnect, ERC1155, ERC20/721 connectors. Usa imagens oficiais Hyperledger.
- `firefly-gateway-arm64-app.yaml`: Versão ARM64 com imagens customizadas `ghcr.io/italoag/*:latest-arm64` e `nodeSelector` em todos os componentes.

**FireFly Multiparty Mode (True Multi-Party)**
- `firefly-multiparty-app.yaml`: Multiparty x86_64 com `multipartyEnabled: true`. Valores Helm inline completos. InitContainers para criar database e aguardar DataExchange. Imagens oficiais.
- `firefly-multiparty-arm64-app.yaml`: Versão ARM64 com imagens customizadas e `nodeSelector` em Core, EVMConnect, ERC1155, ERC20/721.
- `multiparty-app.yaml`: Alternativa x86_64 que referencia `values/multiparty.yaml`. Arquivo mais compacto mas depende de valores externos.
- `multiparty-app-arm64.yaml`: Alternativa ARM64 que referencia `values/multiparty-arm64.yaml`.

**Ingress e Middleware**
- `firefly-ingress-app.yaml`: ArgoCD App que aplica `values/ingress.yaml`. Cria Ingress com TLS para expor FireFly externamente em `firefly.cluster.eita.cloud`.
- `firefly-cors-middleware-app.yaml`: ArgoCD App que aplica `values/firefly-cors-middleware.yaml`. Cria Traefik Middleware CRD para CORS.

#### values/

**Helm Values (para multiparty-app*.yaml)**
- `multiparty.yaml`: Helm values completos para Multiparty Mode x86_64. Inclui todas as configs de Core, Signer, EVMConnect, Tokens, DataExchange.
- `multiparty-arm64.yaml`: Versão ARM64 com imagens customizadas e `nodeSelector`.
- `gateway.yaml` / `gateway-arm64.yaml`: Helm values para Gateway Mode. **Atualmente não usados** (apps gateway usam valores inline).

**Manifestos Kubernetes Raw**
- `ingress.yaml`: Manifesto Kubernetes `kind: Ingress` com TLS para expor FireFly.
- `firefly-cors-middleware.yaml`: Manifesto Traefik `kind: Middleware` para CORS.
- `firefly-config.yaml`: ConfigMap com configurações gerais. **Não usado atualmente**.
- `ipfs.yaml`: Manifesto IPFS. **Não usado** (ipfs-app usa chart com valores inline).

#### backup/

Experimentos e configurações antigas do Gateway. Podem ser removidos após validação que não são mais necessários.

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
1. ✅ Usar Secrets do Kubernetes para senhas (atualmente hardcoded)
2. ✅ Usar certificados válidos (Let's Encrypt) em produção
3. ✅ Habilitar autenticação e autorização no FireFly Core

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

### Backup
O diretório `backup/` contém configurações antigas que podem ser removidas se não forem mais necessárias.
