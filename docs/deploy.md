# Deploy na Sepolia e evidências on-chain

Roteiro operacional. Tudo aqui depende de ações manuais no navegador.

---

## 0. Pré-requisitos

| Papel | Endereço | Precisa de ETH de teste? |
|---|---|---|
| **Hugo** — tesouraria e jogador A | `0xf6e3a81cf77979eeac3874fc8245573c92e8eaf0` | sim, faz quase tudo |
| **Leon** — jogador B | `0xf4a3d4add2c15df016e66138ad96f30302b0134d` | sim, aceita apostas |
| **Rodrigo** — juiz | `0x6d240b001307b577500195846af94dbaf0061fe4` | sim, resolve apostas |

Os três precisam assinar transações, então os três precisam de gás. Colete no
faucet com a conta do Hugo e envie **0,01 ETH** para o Leon e para o Rodrigo pela
MetaMask — sobra bastante.

> Se o Leon e o Rodrigo não estiverem disponíveis, dá para criar as três contas
> na sua própria MetaMask e demonstrar tudo sozinho. O contrato não sabe a
> diferença; só verifica endereços.

Faucet: `cloud.google.com/application/web3/faucet/ethereum/sepolia`
Explorador: `sepolia.etherscan.io`

---

## 1. Compilar

1. Abrir `remix.ethereum.org`, criar `contracts/InteliBet.sol` e colar o arquivo
   deste repositório.
2. **Solidity Compiler**: versão 0.8.20+, *Enable optimization* (200 runs).
3. Compilar. O arquivo tem **dois contratos** — no dropdown de deploy vão
   aparecer `InteliBet` e `InteliCredit`.

> **Selecione `InteliBet`.** O `InteliCredit` não deve ser publicado à mão: ele é
> criado pelo próprio InteliBet no construtor. Publicar separado geraria um token
> órfão, com controlador errado.

### Se a compilação falhar

| Erro | Correção |
|---|---|
| `Ownable: wrong argument count` | o Remix resolveu OpenZeppelin v4 — trocar por `Ownable()` + `transferOwnership` |
| `Source not found @openzeppelin/...` | importar por URL fixando `v5.0.2` |

---

## 2. Deploy

**Deploy & Run** → *Injected Provider – MetaMask* → Sepolia → conta do **Hugo**.
Contract: **`InteliBet`**. Expanda os campos (setinha `˅`):

| Campo | Valor |
|---|---|
| `treasury_` | `0xf6e3a81cf77979eeac3874fc8245573c92e8eaf0` |
| `playerA_` | `0xf6e3a81cf77979eeac3874fc8245573c92e8eaf0` |
| `playerB_` | `0xf4a3d4add2c15df016e66138ad96f30302b0134d` |
| `judge_` | `0x6d240b001307b577500195846af94dbaf0061fe4` |
| `settlementThreshold_` | `10000` (R$ 100,00) |
| `epochDuration_` | `0` (mês de calendário) |

Copie o endereço do contrato. Para achar o endereço do **crédito**, chame
`credit()` — ele foi criado na mesma transação.

O deploy custa mais gás que o normal porque publica dois contratos de uma vez.

---

## 3. Roteiro de interação

Lembrete: `decimals = 2`, então **todo valor vai em centavos**. `10000` = R$ 100,00.

### 3.1 Preparar a mesa (conta do Hugo)

| # | Chamada | Resultado |
|---|---|---|
| 1 | `mintChips` → `<Hugo>`, `100000` | 1.000,00 fichas |
| 2 | `mintChips` → `<Leon>`, `100000` | 1.000,00 fichas |
| 3 | `mintChips` → `<Rodrigo>`, `1000` | **reverte `NotAPlayer`** — ficha fora da mesa não existe |
| 4 | `setName` → `Hugo` | nome no painel |

Depois, com o Leon: `setName` → `Leon`. Com o Rodrigo: `setName` → `Rodrigo`.

### 3.2 A transferência exigida pelo enunciado

| # | Chamada | Conta |
|---|---|---|
| 5 | `transfer` → `<Leon>`, `5000` | Hugo |

Fichas circulam livremente — é um ERC-20 comum. Importe o token nas carteiras
(**Importar tokens** → endereço do InteliBet) e mostre o saldo aparecendo.

### 3.3 Primeira aposta — decidida pelo juiz

| # | Chamada | Conta | Resultado |
|---|---|---|---|
| 6 | `createBet` → `5000`, `Inteli vence o interclasses`, `0` | Hugo | aposta `#0`, status `Aberta`, 50 travados |
| 7 | `acceptBet` → `0` | **Rodrigo** | **reverte `NotAPlayer`** — juiz não aposta |
| 8 | `acceptBet` → `0` | Leon | status `Em andamento`, 100 travados |
| 9 | `resolveBet` → `0`, `<Leon>` | Hugo | **reverte `NotTheJudge`** |
| 10 | `resolveBet` → `0`, `<Leon>` | **Rodrigo** | Leon recebe 100 em ficha **e 50 em crédito** |
| 11 | `netPosition()` | — | `(Leon, Hugo, 5000)` — Hugo deve R$ 50 ao Leon |

O passo 10 é o coração da demonstração: **uma transação move as duas camadas**.

`deadline = 0` usa o padrão de 7 dias.

### 3.4 Segunda aposta — a compensação

| # | Chamada | Conta | Resultado |
|---|---|---|---|
| 12 | `createBet` → `8000`, `Leon corre 5km em menos de 30min`, `0` | Leon | aposta `#1` |
| 13 | `acceptBet` → `1` | Hugo | 160 travados |
| 14 | `agreeOn` → `1`, `<Hugo>` | Hugo | voto registrado, nada liquida ainda |
| 15 | `agreeOn` → `1`, `<Hugo>` | Leon | **liquida na hora, sem o juiz** |
| 16 | `netPosition()` | — | `(Hugo, Leon, 3000)` |

Repare no 16: Hugo devia 50, ganhou 80 — **não** passou a ter 80 a receber e uma
dívida de 50. A vitória abateu a dívida e sobrou R$ 30. É a compensação
funcionando, e é a melhor cena do vídeo.

### 3.5 O crédito não circula

| Chamada | Onde | Resultado |
|---|---|---|
| `transfer` → qualquer endereço, `100` | contrato **InteliCredit** | **reverte `NonTransferable`** |
| `mint` → `<Hugo>`, `999999` | contrato **InteliCredit** | **reverte `OnlyController`** |

Para chamar essas, use *At Address* no Remix com o endereço devolvido por
`credit()`, selecionando o contrato `InteliCredit`.

### 3.6 Quitar

| # | Chamada | Conta | Resultado |
|---|---|---|---|
| 17 | `confirmPayment` → `3000` | Leon | **reverte** — quem deve não apaga dívida |
| 18 | `confirmPayment` → `3000` | Hugo | crédito queimado, `netPosition` zera |

Na história: o Leon pagou R$ 30 por Pix e o Hugo confirmou.

---

## 4. Ligar o painel

Em [`index.html`](../index.html), preencha a constante do topo:

```js
const CONTRATO = "0xSEU_INTELIBET";
```

Só essa — o painel descobre sozinho o endereço do crédito, os três papéis, os
nomes e o limiar. Commit, push, e em um ou dois minutos
https://hugofmontan.github.io/intelibet/ reflete tudo.

---

## 5. Verificar no Etherscan

`sepolia.etherscan.io` → contrato → **Verify and Publish**, Solidity single file
(use o *Flatten* do Remix), mesma versão e otimização, com os seis argumentos do
construtor na mesma ordem.

Vale insistir aqui: a modelagem se apoia em "o devedor não consegue mexer na
conta" e "ninguém cria crédito por fora". As duas afirmações só são verificáveis
com o código publicado.

> Se der `Unable to locate ContractCode`, o Etherscan ainda não indexou o
> contrato. Espere um minuto e reenvie pelo *Contract Verification plugin*, com a
> chave de API salva **dentro do plugin**.

---

## Evidências on-chain

| Item | Valor |
|---|---|
| Rede | Sepolia (chainId 11155111) |
| `InteliBet` (ficha) | `0x` |
| `InteliCredit` (crédito) | `0x` |
| Bloco do deploy | |
| Tx de deploy | `0x` |
| **Tx de transferência entre carteiras** | `0x` |
| Tx `resolveBet` (juiz) | `0x` |
| Tx `agreeOn` (acordo) | `0x` |
| Tx `confirmPayment` | `0x` |
| Painel | https://hugofmontan.github.io/intelibet/ |
| Código verificado | [ ] Etherscan · [ ] Sourcify · [ ] Blockscout |

Capturas em [`../assets/`](../assets/): `deploy.png` · `custodia.png` ·
`resolve.png` · `compensacao.png` · `nao-transferivel.png` · `painel.png`

---

← [README](../README.md) · [Modelagem](modelagem.md) · [Implementação](implementacao.md)
