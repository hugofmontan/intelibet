# Deploy na Sepolia e evidências on-chain

Roteiro operacional. Tudo aqui depende de ações manuais no navegador.

---

## 0. Pré-requisitos

| Item | Status | Observação |
|---|---|---|
| MetaMask instalada | [ ] | autoestudo da Semana 03 |
| Seed phrase guardada fora do computador | [ ] | não fotografar, não colar em nuvem |
| Rede Sepolia visível | [ ] | MetaMask → redes → mostrar redes de teste |
| **Conta A** — tesouraria | [ ] | `0x...` |
| **Conta B** — a outra pessoa da aposta | [ ] | `0x...` |
| ETH de teste em A e B | [ ] | ver abaixo |

Duas contas bastam, e as duas podem ser da mesma MetaMask (menu de contas →
*Adicionar conta*). Uma terceira conta deixa a demonstração do prêmio mais
convincente, mas não é obrigatória.

**Sobre o ETH de teste:** o faucet libera cota diária por conta Google, para um
endereço de cada vez. Colete tudo na **Conta A** e envie ~0,01 ETH de A para B
pela própria MetaMask.

> **Colete o faucet hoje.** Sem ETH de teste nada abaixo funciona, e não há como
> acelerar isso na véspera da entrega.

Faucet: `cloud.google.com/application/web3/faucet/ethereum/sepolia`
Explorador: `sepolia.etherscan.io`

---

## 1. Compilar no Remix

1. Abrir `remix.ethereum.org`.
2. Criar `contracts/InteliBet.sol` e colar o conteúdo do arquivo deste repositório.
3. Aba **Solidity Compiler**: versão **0.8.20** ou superior.
4. Marcar **Enable optimization** (200 runs).
5. Compilar. O Remix baixa a OpenZeppelin do npm pelos imports.

### Se a compilação falhar

| Erro | Causa | Correção |
|---|---|---|
| `Ownable: wrong argument count` | Remix resolveu OpenZeppelin **v4** | v4: `Ownable()` sem argumento + `transferOwnership(treasury)` no construtor |
| `Source not found @openzeppelin/...` | npm/rede | importar por URL fixando a versão: `https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/token/ERC20/ERC20.sol` |

---

## 2. Deploy

Aba **Deploy & Run Transactions** → Environment **Injected Provider – MetaMask**.
Confirmar **Sepolia (11155111)** e a **Conta A** selecionada.

O construtor pede **três** argumentos. Clique na setinha ao lado do botão
*Deploy* para abrir os campos:

| Campo | Valor para a demonstração | Valor em produção |
|---|---|---|
| `treasury` | endereço da **Conta A** | carteira da tesouraria |
| `epochDuration_` | **`600`** (10 minutos) | `2592000` (30 dias) |
| `minDistinctOpponents_` | **`1`** | `3` |

> **Por que 600 e não 2592000.** A época precisa **virar durante a gravação**
> para você conseguir mostrar o `claimPrize` funcionando. Com 30 dias, o vídeo
> descreveria o prêmio em vez de demonstrá-lo. Os dois parâmetros existem
> justamente para permitir isso, e explicar essa escolha no vídeo conta a seu
> favor: mostra que o contrato foi pensado para ser testável.
>
> Dez minutos é folgado para gravar. Se preferir apertado, `300`.

Deploy → confirmar → copiar o endereço do contrato **e o número do bloco** (a
página da transação no Etherscan mostra; o ranking precisa dele).

Diferente da maioria dos tokens, **o supply nasce em zero** — não há emissão no
construtor. É intencional e vale mostrar no vídeo.

---

## 3. Roteiro de interação

Lembrete permanente: `decimals = 2`, então **todo valor vai em centavos**.
`50000` = R$ 500,00.

### 3.1 Lastro e emissão (Conta A)

| # | Chamada | Resultado esperado |
|---|---|---|
| 1 | `mint` → `A`, `30000` | **reverte `StaleAttestation`** — não há reserva atestada |
| 2 | `attestReserves` → `50000`, `<hash>` | evento `ReserveAttested`, reserva de R$ 500,00 |
| 3 | `mintableAmount` | `50000` |
| 4 | `mint` → `A`, `30000` | sucesso — 300,00 IBET para a Conta A |
| 5 | `collateralizationBps` | `16666` (≈166%) |
| 6 | `mint` → `A`, `30000` | **reverte `ReserveInsufficient(60000, 50000)`** |

Os passos 1 e 6 são o coração da entrega. Não pule nenhum dos dois na gravação.

**Como gerar o `<hash>`:** no terminal do Remix, `ethers.utils.id("extrato-reserva-agosto-2026")`.
Se não funcionar, `emn178.github.io/online-tools/keccak_256.html` — qualquer
bytes32 válido serve para a demonstração.

### 3.1b Registrar os nomes do painel

Cada conta registra o próprio nome — `msg.sender` é a chave, então ninguém
nomeia outra pessoa. A Conta B precisa ter ETH de teste para isso.

| # | Chamada | Conta |
|---|---|---|
| 6b | `setName` → `Hugo` | A |
| 6c | `setName` → `Ana` | B |

Sem texto entre aspas nos campos expandidos do Remix. Quem não registrar
continua aparecendo no ranking, só que pelo endereço abreviado.

### 3.2 Transferência entre carteiras (item exigido pelo enunciado)

| # | Chamada | Conta | Resultado |
|---|---|---|---|
| 7 | `transfer` → `B`, `10000` | A | sucesso — 100,00 IBET, **sem taxa nenhuma** |
| 8 | `balanceOf` → `B` | — | `10000` exatos |

Chegar exatamente `10000` é o ponto: prova que a taxa **não** incide sobre
transferência comum. Vale falar isso em voz alta no vídeo.

Importar o token nas duas contas da MetaMask (**Importar tokens** → endereço do
contrato): símbolo e casas decimais se preenchem sozinhos.

### 3.3 Pagamento de aposta — agora com taxa

Cenário: a Conta B perdeu uma aposta de 20,00 IBET para a Conta A.

| # | Chamada | Conta | Resultado |
|---|---|---|---|
| 9 | `settleBet` → `<A>`, `2000`, `"Inteli vence o interclasses"` | **B** | A recebe `1900`, o contrato fica com `100` |
| 10 | `prizePool` → `0` | — | `100` — o pote da época zero |
| 11 | `balanceOf` → `<endereço do contrato>` | — | `100` |
| 12 | `grossWon` → `0`, `<A>` | — | `2000` — ranking por **bruto**, não pelo líquido recebido |
| 13 | `epochLeader` → `0` | — | endereço da Conta A |
| 14 | `settleBet` → `<B>`, `1000`, `"teste"` | B | **reverte `InvalidCounterparty`** |
| 15 | `settleBet` → `<A>`, `10`, `"x"` | B | **reverte `AmountTooSmall(10, 20)`** |

No Etherscan, a transação do passo 9 mostra **dois `Transfer`** (um para a
Conta A, um para o contrato) e o `BetSettled` com o campo `fee`. Boa tela para
o vídeo.

Repita o passo 9 mais duas ou três vezes, alternando quem paga e variando a
descrição, para o ranking e o pote ficarem interessantes.

### 3.4 O prêmio

Confira quando a época vira: `epochEndsAt(0)` devolve um timestamp Unix. Com
`epochDuration = 600`, são dez minutos depois do deploy.

| # | Chamada | Resultado |
|---|---|---|
| 16 | `claimPrize` → `0` (**antes** de virar) | **reverte `EpochNotFinished(0, 0)`** |
| 17 | `currentEpoch` (depois de esperar) | `1` |
| 18 | `claimPrize` → `0` | evento `PrizeClaimed` — o líder recebe o pote inteiro |
| 19 | `balanceOf` → líder | subiu no valor do pote |
| 20 | `claimPrize` → `0` de novo | **reverte `PrizeAlreadySettled(0)`** |

Enquanto espera a época virar, aproveite para gravar os blocos de contexto do
vídeo — problema, tipo do token, parâmetros. O tempo passa sozinho.

### 3.5 Opcionais

| Chamada | Conta | Resultado |
|---|---|---|
| `redeem` → `1000`, `"pix:..."` | B | queima 10,00 IBET + `RedemptionRequested` |
| `settleBet` acima do saldo | B | reverte `ERC20InsufficientBalance` |
| `settleBet` com descrição vazia | B | reverte `InvalidDescription(0, 200)` |

---

## 4. Ligar o ranking

Abrir `ranking/index.html` e preencher no topo do `<script>`:

```js
const CONTRATO      = "0xSEU_CONTRATO";
const BLOCO_INICIAL = 1234567;                    // bloco do deploy
const APELIDOS      = { "0xSUA_CONTA_A": "Hugo", "0xSUA_CONTA_B": "Ana" };
```

Abrir o arquivo no navegador — dois cliques, não precisa de servidor. A página
mostra o pote, o líder, o tempo restante da época e as duas classificações.

**Já está publicado** em https://hugofmontan.github.io/intelibet/ — o GitHub Pages serve o
repositório e a raiz redireciona para `ranking/`. Depois de editar as constantes,
faça `git add -A && git commit && git push`: em um ou dois minutos a página no ar
reflete a mudança.

Se a página não carregar: o RPC público pode estar fora. Trocar a constante
`RPC` por `https://rpc.sepolia.org` ou `https://sepolia.drpc.org` resolve —
nenhum deles exige cadastro.

---

## 5. Verificar o código no Etherscan (recomendado)

`sepolia.etherscan.io` → contrato → **Contract** → **Verify and Publish**.
Solidity single file (Remix: botão direito no arquivo → *Flatten*), mesma versão
de compilador e mesma configuração de otimização. Os três argumentos do
construtor precisam ser informados na mesma ordem do deploy.

Vale mais aqui do que na média dos projetos: a modelagem se apoia em "qualquer um
pode conferir a reserva" **e** em "não existe função que permita à tesouraria
sacar o pote". As duas afirmações só são verificáveis com o código publicado.

---

## Evidências on-chain

> Preencher conforme executar. Vão para o README e para o vídeo.

| Item | Valor |
|---|---|
| Rede | Sepolia (chainId 11155111) |
| Contrato `InteliBet` | `0xed37b31a32d3d498ab75751add0057f28e05f062` |
| Bloco do deploy | 11525419 |
| `epochDuration` usado | 600 (10 minutos) |
| `minDistinctOpponents` usado | 1 |
| Tx de deploy | `0x585101a8ae06df7d1c8a04b28a7080e4c2a1a9ef01d102c69df21892ada62382` |
| Tx `attestReserves` | `0x` |
| Tx `mint` | `0x` |
| **Tx de transferência A → B** | `0x` |
| Tx `settleBet` | `0x` |
| **Tx `claimPrize`** | `0x` |
| Conta A (tesouraria) | `0xf6e3a81cf77979eeac3874fc8245573c92e8eaf0` |
| Conta B | `0x` |
| URL do ranking (GitHub Pages) | https://hugofmontan.github.io/intelibet/ |
| Código verificado | Etherscan ✅ · Sourcify ✅ · Blockscout ✅ |
| Data/hora do deploy | |

Capturas em [`../assets/`](../assets/): `deploy.png` · `revert-reserva.png` ·
`transfer-etherscan.png` · `logs-betsettled.png` · `ranking.png` ·
`prize-claimed.png`

---

← [README](../README.md) · [Modelagem](modelagem.md) · [Implementação](implementacao.md)
