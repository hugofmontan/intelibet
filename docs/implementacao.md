# Etapa 2 — Implementação

| Peça | Papel | Arquivo |
|---|---|---|
| **InteliBet** | o token ERC-20 — a entrega | [`contracts/InteliBet.sol`](../contracts/InteliBet.sol) |
| **Ranking** | página estática que lê os eventos e mostra pote, líder e classificação | [`ranking/index.html`](../ranking/index.html) |

Compilador: **Solidity ^0.8.20** · Biblioteca: **OpenZeppelin Contracts v5.x**
Um contrato, cerca de 330 linhas com comentários.

---

## 1. Por que herdar de biblioteca auditada

A aula trata explicitamente de reutilização segura via OpenZeppelin. Reescrever
`transfer`, `approve` e a contabilidade de allowance à mão significaria
reintroduzir bugs que a biblioteca já resolveu.

| Herança | O que traz |
|---|---|
| `ERC20` | saldo, allowance, eventos `Transfer` / `Approval` |
| `ERC20Burnable` | `burn` e `burnFrom`, usados pelo resgate |
| `Ownable` | `owner`, `onlyOwner` |

O autoral é o que a ideia exige: prova de reserva, invariante do peg, registro
de aposta e o mecanismo de época/prêmio.

> **O que ficou de fora.** `ERC20Pausable` e lista de contas congeladas
> existiram numa versão anterior. Saíram: controles de compliance de stablecoin
> operada comercialmente, que aqui só aumentariam a superfície sem servir ao
> problema.

---

## 2. Prova de reserva

```solidity
uint256 public reservesAttested;   // reserva em centavos
bytes32 public reserveProofHash;   // hash do extrato publicado off-chain
uint64  public reserveAttestedAt;  // quando foi atestada
```

`attestReserves(amount, proofHash)` publica os três de uma vez e emite
`ReserveAttested`.

**Não valida contra o supply, de propósito.** Atestar reserva *abaixo* do supply
é um evento legítimo — significa que o token está subcolateralizado, e isso
precisa ser visível em vez de impossível de declarar. O efeito é automático:
`collateralizationBps()` cai abaixo de 10000 e `mint` para de funcionar sozinho.

## 3. A invariante do peg

```solidity
function mint(address to, uint256 amount) external onlyOwner {
    if (amount == 0) revert ZeroAmount();
    if (block.timestamp > reserveAttestedAt + ATTESTATION_MAX_AGE) {
        revert StaleAttestation(reserveAttestedAt, ATTESTATION_MAX_AGE);
    }
    uint256 supplyAfter = totalSupply() + amount;
    if (supplyAfter > reservesAttested) revert ReserveInsufficient(supplyAfter, reservesAttested);
    _mint(to, amount);
}
```

Três guardas: valor zero, atestação vencida, teto de reserva.

Efeito colateral elegante da segunda: como `reserveAttestedAt` começa em zero,
**o primeiro `mint` reverte enquanto não houver nenhuma atestação**. O contrato
nasce impedido de emitir sem lastro. Nenhum IBET é emitido no construtor, pelo
mesmo motivo.

**A taxa não interfere aqui.** Os 5% saem de uma conta e entram na do próprio
contrato — o `totalSupply` não muda, então a invariante continua valendo. O pote
é IBET lastreado como qualquer outro.

## 4. `settleBet` — transferir, cobrar e registrar

```solidity
function settleBet(address winner, uint256 amount, string calldata description) external {
    if (winner == address(0)) revert ZeroAddress();
    if (winner == msg.sender || winner == address(this)) revert InvalidCounterparty();

    uint256 minimum = 10_000 / FEE_BPS;               // 20 = R$ 0,20
    if (amount < minimum) revert AmountTooSmall(amount, minimum);

    uint256 len = bytes(description).length;
    if (len == 0 || len > MAX_DESCRIPTION_LENGTH) revert InvalidDescription(len, MAX_DESCRIPTION_LENGTH);

    uint256 fee   = (amount * FEE_BPS) / 10_000;
    uint256 epoch = currentEpoch();

    _transfer(msg.sender, winner, amount - fee);
    _transfer(msg.sender, address(this), fee);

    prizePool[epoch] += fee;
    _registerWin(epoch, winner, msg.sender, amount);

    emit BetSettled(msg.sender, winner, amount, fee, epoch, description);
}
```

Decisões que importam:

- **O pagador é sempre `msg.sender`**, nunca um parâmetro. Ninguém consegue
  plantar uma derrota na conta de outra pessoa, porque o valor sai do saldo de
  quem chama.
- **A taxa não incide sobre `transfer`.** Um ERC-20 que entrega menos do que foi
  mandado (*fee on transfer*) quebra carteira, exchange e qualquer contrato que
  faça conta antes de transferir. Aqui `transfer` continua limpo e previsível.
- **Aposta mínima de 20 unidades base.** Abaixo disso `(amount * 500) / 10000`
  trunca para zero, e a aposta entraria no ranking **sem** alimentar o pote —
  um caminho de registro gratuito. A guarda fecha isso.
- **Duas transferências, dois eventos `Transfer`.** Uma para o vencedor, outra
  para o contrato. É mais legível no explorador do que uma transferência única
  com contabilidade escondida.
- **`description` obrigatória e limitada a 200 bytes.** Sem limite superior o
  evento vira depósito de lixo; sem limite inferior, alguém registra aposta sem
  dizer sobre o quê.

## 5. O ranking on-chain: por que **bruto** e não saldo líquido

```solidity
function _registerWin(uint256 epoch, address winner, address loser, uint256 amount) private {
    if (!_alreadyBeat[epoch][winner][loser]) {
        _alreadyBeat[epoch][winner][loser] = true;
        distinctOpponents[epoch][winner] += 1;
    }

    uint256 total = grossWon[epoch][winner] + amount;
    grossWon[epoch][winner] = total;

    if (total > epochLeaderAmount[epoch] && distinctOpponents[epoch][winner] >= minDistinctOpponents) {
        epochLeaderAmount[epoch] = total;
        epochLeader[epoch] = winner;
        emit LeaderChanged(epoch, winner, total);
    }
}
```

**A restrição técnica que virou decisão de produto.** Saldo líquido
(ganhou − perdeu) **desce** quando alguém perde. Se o líder fosse por líquido,
uma derrota do primeiro colocado obrigaria a percorrer todos os participantes
para achar o novo líder — o que não cabe numa transação e pode estourar o gás do
bloco.

Ganho bruto só sobe. Manter o líder vira uma comparação de uma linha. E, como
métrica, "quem mais ganhou apostas neste mês" é mais direto de entender do que
saldo líquido. A página mostra os dois: bruto da época (que decide o prêmio) e
líquido geral (o retrato de longo prazo).

**Sobre a elegibilidade.** A condição de adversários distintos é reavaliada a
cada aposta. Como o bruto só cresce, quem se torna elegível numa chamada já é
comparado com o líder ali mesmo — não fica um caso em que alguém "virou
elegível" e ninguém percebeu.

## 6. Épocas

```solidity
function currentEpoch() public view returns (uint256) {
    return (block.timestamp - startTime) / epochDuration;
}
```

`startTime` é o momento do deploy; `epochDuration` é **parâmetro do
construtor**, não constante. Produção e demonstração querem coisas diferentes:

| Uso | `epochDuration` | Por quê |
|---|---|---|
| Produção | `2592000` (30 dias) | ciclo mensal |
| Demonstração / vídeo | `600` (10 min) | dá para mostrar apostas, virada de época e prêmio numa gravação |

Sem esse parâmetro, o vídeo teria que descrever o prêmio em vez de mostrá-lo
acontecendo. `minDistinctOpponents` é parâmetro pelo mesmo motivo: 3 em
produção, 1 numa demonstração com duas contas.

Ambos são `immutable` — regra de prêmio que muda no meio do jogo não é regra.

## 7. `claimPrize`

```solidity
function claimPrize(uint256 epoch) external {
    uint256 current = currentEpoch();
    if (epoch >= current) revert EpochNotFinished(epoch, current);
    if (prizeSettled[epoch]) revert PrizeAlreadySettled(epoch);

    prizeSettled[epoch] = true;
    uint256 pot = prizePool[epoch];
    address winner = epochLeader[epoch];
    if (pot == 0) return;

    prizePool[epoch] = 0;

    if (winner == address(0)) {
        prizePool[current] += pot;
        emit PrizeRolledOver(epoch, pot, current);
        return;
    }

    _transfer(address(this), winner, pot);
    emit PrizeClaimed(epoch, winner, pot);
}
```

- **Sem restrição de quem chama.** O valor vai para o líder registrado, não para
  quem chamou. Se dependesse do ganhador, um ganhador desatento deixaria o pote
  parado; se dependesse da tesouraria, ela teria poder de reter.
- **Marca antes de pagar** (`prizeSettled = true` na frente do `_transfer`):
  ordem checks-effects-interactions, mesmo o destinatário sendo o próprio token.
- **Época sem líder elegível não queima o pote** — ele passa para a época
  corrente. Prêmio que evapora desincentiva participar justamente nos meses
  fracos, que são os que mais precisam de incentivo.
- **Não existe função que permita ao owner sacar o pote.** Este é o único
  caminho de saída do saldo do contrato, e vale conferir isso lendo o código —
  é a garantia central do "a tesouraria não fica com nada".

## 8. Erros customizados

`ReserveInsufficient`, `StaleAttestation`, `InvalidCounterparty`,
`InvalidDescription(len, max)`, `AmountTooSmall(amount, min)`,
`EpochNotFinished(epoch, current)`, `PrizeAlreadySettled`, `ZeroAmount`,
`ZeroAddress`. Além de gastarem menos gás que `require` com string, **carregam o
dado** — no Remix aparece exatamente qual época é a corrente, quanto foi
tentado, qual era a reserva. A reversão vira conteúdo demonstrável.

---

## 9. O ranking

`ranking/index.html`: um arquivo, sem banco, sem servidor, sem chave de API.

Lê **on-chain** o que é autoritativo (época atual, pote, líder, fim da época,
mínimo de adversários) e **dos eventos** o que é histórico (todas as apostas).
A separação é intencional: se a página e o contrato discordarem, o contrato está
certo, e o pote mostrado é o que o `claimPrize` vai pagar.

Mostra: pote da época · líder · tempo restante · classificação da época com
adversários distintos e selo de elegibilidade · placar geral por saldo líquido ·
feed das últimas apostas com valor, taxa e link para a transação.

**Configuração** — duas linhas no topo do `<script>`: `CONTRATO` e
`BLOCO_INICIAL`, mais o mapa opcional de `APELIDOS`.

---

## 10. Matriz de verificação antes do deploy

| # | Cenário | Esperado |
|---|---|---|
| 1 | `mint` sem nenhuma atestação | reverte `StaleAttestation` |
| 2 | `attestReserves(50000, hash)` → `mint(A, 30000)` | sucesso, 300,00 IBET |
| 3 | `mint` acima da reserva | reverte `ReserveInsufficient(60000, 50000)` |
| 4 | `transfer(B, 5000)` | sucesso, **sem** taxa |
| 5 | `settleBet(A, 2000, "…")` por B | A recebe 1900, contrato fica com 100 |
| 6 | `prizePool(epoca)` | `100` |
| 7 | `settleBet` para si mesmo | reverte `InvalidCounterparty` |
| 8 | `settleBet` com valor 10 | reverte `AmountTooSmall(10, 20)` |
| 9 | `settleBet` com descrição vazia | reverte `InvalidDescription(0, 200)` |
| 10 | `epochLeader(epoca)` após apostas suficientes | endereço do líder |
| 11 | `claimPrize(epoca)` com a época em curso | reverte `EpochNotFinished` |
| 12 | `claimPrize(epoca)` após virar a época | líder recebe o pote |
| 13 | `claimPrize` da mesma época de novo | reverte `PrizeAlreadySettled` |
| 14 | Época sem líder elegível | pote passa adiante (`PrizeRolledOver`) |

Metade são casos que **devem** reverter. Um contrato testado só no caminho feliz
não está testado.

---

## Limitações conhecidas

1. **Sem garantia de pagamento** — é o desenho, não um bug.
2. **Auto-aposta ainda é possível em grupo coordenado.** A exigência de
   adversários distintos encarece, não impede. Ver modelagem §7.2.
3. **Atestação depende de auditoria externa.**
4. **Owner único** — deveria ser multisig.
5. **A página não pagina eventos.** Com milhares de apostas, o `queryFilter`
   único precisaria ser quebrado em faixas de blocos.
6. **`grossWon` e `distinctOpponents` crescem sem limpeza.** Storage por época
   nunca é liberado. Aceitável no volume esperado; num uso grande valeria
   arquivar épocas antigas.

---

← [README](../README.md) · [Modelagem](modelagem.md) · [Deploy](deploy.md)
