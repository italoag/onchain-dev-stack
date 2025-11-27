# Problemas Pendentes - Namespace FireFly

**Data**: 2025-11-27 02:23  
**Status**: Parcialmente funcional

## ✅ Problemas Resolvidos

1. ✅ **URL do Besu** - Corrigido de `besu-node1-rpc` para `besu-node1`
2. ✅ **Token Connectors** - ERC1155 e ERC20/721 agora estão Running 1/1
3. ✅ **Ingress Sandbox** - Referência removida do `ingress.yaml`

## ❌ Problemas Ativos

### 1. FireFly Contract Não Deployado (CRÍTICO)

**Sintoma:**
```
ERROR <== POST http://firefly-evmconnect.firefly.svc:5000/ [404] (39ms)
ERROR namespace default attempt 12: FF10111: Error from ethereum connector: 
FF00164: No result found
```

**Contexto:**
```
Resolving FireFly contract at index 0 using networkVersion
Contract: 0xDEdB3f6382B73129Ad3f72AD737F348b44Ffc749
```

**Causa Raiz:**
O FireFly está configurado em **Multiparty Mode** (`multipartyEnabled: true`) que requer um **FireFly Custom Contract** deployado na blockchain. Este contrato hardcoded `0xDEdB3f6382B73129Ad3f72AD737F348b44Ffc749` não existe no Besu local.

**Impacto:**
- ❌ FireFly Core não consegue inicializar namespace `default`
- ❌ Registration job falhando com "Namespace 'default' is initializing"
- ⚠️ Application "firefly" mostra status "Degraded" no ArgoCD

**Soluções Possíveis:**

#### Opção A: Mudar para Gateway Mode (Recomendado para Dev/Test)
Gateway Mode não requer custom contract.

**Mudança necessária:** Editar `firefly-multiparty-arm64-app.yaml`
```yaml
config:
  multipartyEnabled: false  # ← Mudar para false
  # Remover ou comentar:
  # fireflyContractAddress: ...
  # fireflyContracts: ...
```

**Vantagens:**
- Não precisa deployar contrato
- Mais simples para desenvolvimento
- Funciona imediatamente

**Desvantagens:**
- Não é true multiparty
- Apenas um node gerenciando múltiplas orgs

#### Opção B: Deploy do FireFly Custom Contract
Deploy do contrato `FireFlyCustom.sol` no Besu.

**Passos necessários:**
1. Obter o bytecode do FireFly Custom Contract
2. Deployar usando FireFly CLI ou script
3. Atualizar config com endereço real do contrato
4. Reiniciar FireFly

**Vantagens:**
- True multiparty setup
- Cada org tem seu próprio node

**Desvantagens:**
- Requer processo de deploy adicional
- Mais complexo para gerenciar

**Recomendação:** Para ambiente de desenvolvimento, use **Opção A (Gateway Mode)**.

---

### 2. Ingress Não Criado

**Status:** ⚠️ Parcialmente resolvido

**Situação:**
- ArgoCD Application `firefly-ingress` mostra "Synced" e "Healthy"
- Mas `kubectl get ingress -n firefly` retorna "No resources found"
- ArgoCD logs mostram "Successfully deleted 0 resources"

**Causa:**
A aplicação ArgoCD usa `directory` source type que não está aplicando os manifestos corretamente.

**Configuração Atual:**
```yaml
source:
  repoURL: https://github.com/italoag/onchain-dev-stack.git
  path: firefly/argocd
  directory:
    include: "values/ingress.yaml"
```

**Problema:** 
O ArgoCD directory source busca manifestos em `firefly/argocd/values/ingress.yaml`, mas não os está aplicando.

**Soluções Possíveis:**

#### Opção A: Aplicar Ingress Manualmente (Quick Fix)
```bash
kubectl apply -f argocd/values/ingress.yaml
```

#### Opção B: Mudar para Plain YAML Application (Recomendado)
Atualizar `firefly-ingress-app.yaml`:
```yaml
source:
  repoURL: https://github.com/italoag/onchain-dev-stack.git
  path: firefly/argocd/values
  targetRevision: main
  directory:
    include: "ingress.yaml"
    recurse: false
```

#### Opção C: Usar Helm Chart para Ingress
Criar um helm chart simples que gerencia o Ingress.

**Recomendação:** Usar **Opção A** como quick fix, depois implementar **Opção B**.

---

### 3. Registration Job Falhando (Consequência)

**Sintoma:**
```
Registering organization
{"error":"FF10441: Namespace 'default' is initializing"}
Failed to register with code 412
```

**Causa:**
Este é um efeito cascata do **Problema #1**. O namespace não inicializa porque o FireFly Contract não foi encontrado.

**Status:** ⏳ Aguardando resolução do Problema #1

**Ação:** Nenhuma. Vai se resolver automaticamente quando o contract issue for corrigido.

---

## 📊 Status dos Componentes

```
✅ FUNCIONANDO (100%):
- firefly-signer-0              [1/1 Running] - Conectado ao Besu
- firefly-evmconnect-0          [1/1 Running] - Processando blocks
- firefly-dx-0                  [1/1 Running] - DataExchange OK
- firefly-erc1155               [1/1 Running] - Health checks passing
- firefly-erc20-erc721          [1/1 Running] - Health checks passing
- ipfs                          [1/1 Running] - Storage OK

⚠️ PARCIALMENTE FUNCIONANDO:
- firefly-0                     [1/1 Running] - Pod OK, mas namespace não inicializa

❌ FALHANDO:
- firefly-registration (Job)    [0/1 Error]   - Namespace initializing
- Ingress                       [Not Created] - ArgoCD issue

📊 ARGOCD STATUS:
- firefly                       [Synced, Degraded]  ← Contract issue
- firefly-signer                [Synced, Healthy]
- firefly-ingress               [Synced, Healthy]   ← Mas não criou recurso
- firefly-cors-middleware       [Synced, Healthy]
```

## 🎯 Plano de Ação Recomendado

### Passo 1: Resolver FireFly Contract (PRIORITÁRIO)

**Opção Rápida - Mudar para Gateway Mode:**
```bash
# 1. Editar arquivo
vi argocd/applications/firefly-multiparty-arm64-app.yaml

# Mudar:
multipartyEnabled: false

# Comentar/remover:
# fireflyContractAddress: ...
# fireflyContracts: ...

# 2. Commit e push
git add argocd/applications/firefly-multiparty-arm64-app.yaml
git commit -m "fix: Mudar FireFly para Gateway Mode"
git push

# 3. Aguardar ArgoCD sync ou forçar
kubectl delete pods -n firefly firefly-0

# 4. Aguardar namespace inicializar (1-2 minutos)
kubectl logs -n firefly firefly-0 -f | grep "namespace default"
```

### Passo 2: Criar Ingress Manualmente

```bash
# Quick fix
kubectl apply -f argocd/values/ingress.yaml

# Verificar
kubectl get ingress -n firefly

# Testar
curl -k https://firefly.cluster.eita.cloud/api/v1/status
```

### Passo 3: Validar Funcionamento Completo

```bash
# 1. Verificar pods
kubectl get pods -n firefly

# 2. Verificar registration job
kubectl get jobs -n firefly
# Deve mostrar: firefly-*-registration COMPLETIONS: 1/1

# 3. Verificar FireFly API
curl https://firefly.cluster.eita.cloud/api/v1/namespaces/default/status

# 4. Acessar UI
open https://firefly.cluster.eita.cloud/ui/
```

## 🔍 Comandos de Diagnóstico

### Verificar Status do Namespace FireFly
```bash
kubectl logs -n firefly firefly-0 | grep -i "namespace.*default" | tail -20
```

### Verificar se Contract Existe no Besu
```bash
kubectl exec -n firefly firefly-signer-0 -- \
  wget -O- --post-data='{"jsonrpc":"2.0","method":"eth_getCode","params":["0xDEdB3f6382B73129Ad3f72AD737F348b44Ffc749","latest"],"id":1}' \
  --header='Content-Type: application/json' \
  http://besu-node1.paladin.svc:8545

# Se retornar "0x" = contrato não existe
# Se retornar bytecode = contrato existe
```

### Verificar Logs do EVMConnect
```bash
kubectl logs -n firefly firefly-evmconnect-0 | grep -i error
```

### Verificar ArgoCD Application Status
```bash
kubectl describe application firefly -n argocd | grep -A10 "Conditions:"
```

## 📝 Arquivos Afetados

### Já Corrigidos (Commitados):
- ✅ `argocd/applications/firefly-signer-app.yaml` - URL Besu
- ✅ `argocd/applications/firefly-signer-arm64-app.yaml` - URL Besu
- ✅ `argocd/values/ingress.yaml` - Removido sandbox
- ✅ `argocd/README.md` - URLs atualizadas
- ✅ `DIAGNOSTICO_FIREFLY.md` - Documentação

### Pendentes de Correção:
- ⏳ `argocd/applications/firefly-multiparty-arm64-app.yaml` - Mudar para Gateway Mode
- ⏳ `argocd/applications/firefly-ingress-app.yaml` - Corrigir directory source

## 🔗 Referências

- [FireFly Modes](https://hyperledger.github.io/firefly/overview/multiparty/blockchain.html)
- [FireFly Custom Smart Contract](https://github.com/hyperledger/firefly/tree/main/smart_contracts)
- [ArgoCD Directory Applications](https://argo-cd.readthedocs.io/en/stable/user-guide/directory/)
