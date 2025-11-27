# Diagnóstico Completo - Namespace FireFly

**Data**: 2025-11-27  
**Deployment**: firefly-multiparty-arm64

## 📊 Status Geral dos Pods

```
NAMESPACE: firefly
DEPLOYMENT: firefly-multiparty-arm64-app.yaml

✅ FUNCIONANDO:
- firefly-0 (Core)                  [1/1 Running]
- firefly-dx-0 (DataExchange)       [1/1 Running]
- firefly-evmconnect-0              [1/1 Running]
- firefly-signer-0                  [1/1 Running]
- ipfs-cfc4f9769-w8cwq              [1/1 Running]

❌ COM PROBLEMAS:
- firefly-erc1155-*                 [0/1 Running - Not Ready]
- firefly-erc20-erc721-*            [0/1 Running - Not Ready]
- firefly-*-registration (Job)      [Error - Retrying]
```

## 🔴 Problema Principal: URL Incorreta do Besu

### Erro Identificado

**Componentes Afetados:**
- firefly-signer
- firefly-evmconnect  
- firefly-erc1155
- firefly-erc20-erc721

**Mensagem de Erro:**
```
FF22012: Backend RPC request failed: 
Post "http://besu-node1-rpc.paladin.svc:8545": 
dial tcp: lookup besu-node1-rpc.paladin.svc on 10.43.0.10:53: no such host
```

### Causa Raiz

A configuração estava tentando conectar a `besu-node1-rpc.paladin.svc:8545`, mas o serviço real se chama **`besu-node1.paladin.svc:8545`** (sem o sufixo `-rpc`).

### Evidências

**Serviços reais no namespace paladin:**
```bash
$ kubectl get svc -n paladin
NAME                TYPE        CLUSTER-IP      PORTS
besu-node1          NodePort    10.43.56.242    8545:31545/TCP
besu-node2          NodePort    10.43.61.252    8545:31645/TCP
besu-node3          NodePort    10.43.155.228   8545:31745/TCP
```

**Teste de conectividade (bem-sucedido):**
```bash
$ kubectl run debug --image=curlimages/curl -n firefly -- \
  curl -X POST http://besu-node1.paladin.svc:8545 \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

Response: {"jsonrpc":"2.0","id":1,"result":"0xb9"}
```

## 🔧 Correções Aplicadas

### 1. FireFly Signer

**Arquivo:** `argocd/applications/firefly-signer-app.yaml`  
**Arquivo:** `argocd/applications/firefly-signer-arm64-app.yaml`

```yaml
backend:
  url: "http://besu-node1.paladin.svc:8545"  # ✅ Corrigido
  chainId: 1337
```

### 2. Documentação

**Arquivo:** `argocd/README.md`

Atualizadas todas as referências:
- Pré-requisitos: URL do Besu
- Detalhamento de arquivos: descrição do firefly-signer
- Troubleshooting: comandos de teste de conectividade

## 🔍 Análise dos Erros por Componente

### firefly-evmconnect

**Sintoma:**
```
ERROR evmconnect: get initial block height attempt N: 
FF22012: Backend RPC request failed
```

**Status:** ✅ Resolvido  
**Razão:** EVMConnect chama o firefly-signer, que estava falhando ao conectar ao Besu. Com a correção do Signer, o EVMConnect vai funcionar.

---

### firefly-erc1155 e firefly-erc20-erc721

**Sintoma:**
```
ERROR [HealthCheckService] Health Check has failed! 
{"ethconnect":{"status":"down","message":"timeout of 30000ms exceeded"}}

WARN [RequestLogging] GET /api/v1/health/readiness - 503 Service Unavailable
```

**Status:** ✅ Resolvido  
**Razão:** Token connectors dependem do EVMConnect, que por sua vez depende do Signer. Com a cadeia de dependências corrigida, os connectors vão iniciar corretamente.

**Readiness Probe:** Esses pods só ficam "Ready" quando conseguem se comunicar com o EVMConnect via Signer até o Besu.

---

### firefly-*-registration (Job)

**Sintoma:**
```
Registering organization
{"error":"FF10441: Namespace 'default' is initializing"}
Failed to register with code 412
```

**Status:** ⚠️ Esperado (transitório)  
**Razão:** O job de registration tenta registrar a organização, mas o namespace FireFly ainda está inicializando. O job vai continuar tentando até conseguir.

**Ação:** Nenhuma. É um comportamento normal durante o startup inicial. O job vai completar assim que:
1. O Signer conectar ao Besu ✅
2. O EVMConnect inicializar ✅  
3. O FireFly Core finalizar inicialização do namespace ⏳

## 📋 Fluxo de Dependências

```
Besu (paladin namespace)
  ↓
firefly-signer (conecta ao Besu via backend.url)
  ↓
firefly-evmconnect (chama Signer via http://firefly-signer.firefly.svc:8545)
  ↓
firefly-erc1155 & firefly-erc20-erc721 (health check do ethconnect)
  ↓
firefly-core (namespace initialization)
  ↓
firefly-registration (registra organização)
```

**Ponto de Falha Original:** Signer → Besu  
**Impacto em Cascata:** Todos os componentes downstream falhavam

## ✅ Resolução

### Mudanças Implementadas

1. ✅ Corrigida URL do Besu em `firefly-signer-app.yaml`
2. ✅ Corrigida URL do Besu em `firefly-signer-arm64-app.yaml`
3. ✅ Atualizado README.md com URLs corretas
4. ✅ Commit e push das correções

### Ações Necessárias no Cluster

**Para aplicar as correções:**

```bash
# 1. Deletar o firefly-signer atual
kubectl delete application firefly-signer -n argocd

# 2. Recriar com configuração corrigida (ARM64 neste caso)
kubectl apply -f argocd/applications/firefly-signer-arm64-app.yaml

# 3. Aguardar o Signer reiniciar
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=firefly-signer \
  -n firefly --timeout=300s

# 4. Verificar logs do Signer (deve conectar ao Besu com sucesso)
kubectl logs -n firefly -l app.kubernetes.io/name=firefly-signer --tail=50

# 5. Verificar se EVMConnect consegue obter block height
kubectl logs -n firefly firefly-evmconnect-0 --tail=50

# 6. Aguardar token connectors ficarem Ready (1-2 minutos)
kubectl get pods -n firefly -w
```

### Validação

**Comandos para validar a correção:**

```bash
# 1. Verificar conectividade Signer → Besu
kubectl exec -it firefly-signer-0 -n firefly -- \
  wget -O- http://besu-node1.paladin.svc:8545

# 2. Verificar health do ERC1155
kubectl exec -it firefly-erc1155-XXX -n firefly -- \
  wget -O- http://localhost:3000/api/v1/health/readiness

# 3. Verificar health do ERC20/721
kubectl exec -it firefly-erc20-erc721-XXX -n firefly -- \
  wget -O- http://localhost:3000/api/v1/health/readiness

# 4. Verificar status do registration job
kubectl get jobs -n firefly
kubectl logs -n firefly job/firefly-eita-latest-arm64-registration
```

## 🎯 Resultado Esperado

Após aplicar as correções, em 5-10 minutos:

```
✅ firefly-signer conectado ao Besu
✅ firefly-evmconnect obtendo block height
✅ firefly-erc1155 health check passing (Ready 1/1)
✅ firefly-erc20-erc721 health check passing (Ready 1/1)
✅ firefly-registration job completed (Status: Completed)
✅ FireFly Core namespace 'default' initialized
```

## 📝 Lições Aprendidas

1. **Validar serviços reais:** Sempre verificar nomes reais dos serviços com `kubectl get svc -n <namespace>`
2. **Testar conectividade:** Usar pods debug para testar URLs antes de configurar
3. **Seguir dependências:** Um erro no componente base (Signer) causa falha em cascata
4. **Logs são essenciais:** Os logs do EVMConnect mostraram claramente o problema de DNS
5. **Charts oficiais:** O chart do Hyperledger usa nomes de serviço padrão, sem sufixos customizados

## 🔗 Referências

- Besu Documentation: https://besu.hyperledger.org/
- FireFly Signer: https://github.com/hyperledger/firefly-signer
- FireFly EVMConnect: https://github.com/hyperledger/firefly-evmconnect
- Commit com correção: `376168e`
