# Etapa 2 — Implementação

| Peça | Papel | Onde |
|---|---|---|
| **InteliBet** (`IBET`) | ficha, custódia, apostas, placar | [`contracts/InteliBet.sol`](../contracts/InteliBet.sol) |
| **InteliCredit** (`IBRL`) | registro de dívida | mesmo arquivo |
| **Painel** | estado da mesa + explicação | [`index.html`](../index.html) |

Compilador **Solidity ^0.8.20**, biblioteca **OpenZeppelin v5**.
Dois contratos, um arquivo, **um único deploy**.

---

## 1. Por que herdar de biblioteca auditada

A aula trata explicitamente de reutilização segura via OpenZeppelin. Reescrever
`transfer`, `approve` e a contabilidade de allowance à mão significaria
reintroduzir bugs que a biblioteca já resolveu.

O que é autoral é só o que a ideia exige: custódia, compensação de dívida,
papéis e aritmética de calendário.

## 2. Um deploy, dois contratos

```solidity
constructor(...) ERC20("InteliBet Chip", "IBET") Ownable(treasury_) {
    ...
    credit = new InteliCredit(address(this));
}
```

O token de crédito é criado **pelo próprio contrato da mesa**, dentro do
construtor, já apontando para ele como `controller`. Três ganhos:

- **um deploy publica os dois**, sem ordem para errar;
- não existe janela em que o crédito esteja sem controlador definido;
- o `controller` é `immutable` e nunca foi um endereço externo, então não há
  passo de "autorizar o contrato" que alguém possa esquecer ou fazer errado.

## 3. O crédito, e as duas restrições que o definem

```solidity
function _update(address from, address to, uint256 value) internal override {
    if (from != address(0) && to != address(0)) revert NonTransferable();
    super._update(from, to, value);
}
```

Mint (`from == 0`) e burn (`to == 0`) passam; transferência entre pessoas, não.
`_update` é o ponto único por onde toda movimentação de saldo passa na v5, então
não existe caminho que escape da regra.

A segunda restrição é `onlyController` em `mint` e `burn`. Somadas, produzem a
garantia central do projeto:

> **Crédito só nasce de aposta resolvida, e só morre por confirmação de quem
> tinha a receber.** O devedor não tem função nenhuma que reduza a própria
> dívida.

## 4. A compensação

```solidity
function _netCredit(address winner, address loser, uint256 amount) private {
    uint256 anterior  = credit.balanceOf(winner);
    uint256 contraria = credit.balanceOf(loser);
    uint256 abatido   = contraria >= amount ? amount : contraria;

    if (abatido > 0) credit.burn(loser, abatido);
    uint256 emitido = amount - abatido;
    if (emitido > 0) credit.mint(winner, emitido);
    ...
}
```

Abate primeiro, emite depois. A invariante que isso mantém — **no máximo um dos
dois com saldo** — não é verificada em lugar nenhum: é consequência da ordem das
operações. Se o vencedor recebe, é porque a dívida contrária foi zerada antes; e
ele só tinha saldo se o oponente já estava zerado.

O evento `SettlementDue` é emitido **na travessia** do limiar, não a cada
liquidação: a comparação usa o saldo anterior e o novo, então o aviso aparece uma
vez, quando a dívida cruza a linha.

## 5. A custódia

O valor da aposta sai da carteira e vai para o endereço do contrato via
`_transfer` interno — sem `approve`, sem `transferFrom`, sem passo de aprovação
para o usuário esquecer.

A máquina de estados:

```
                accept()              agreeOn() x2 / resolveBet()
   Open  ──────────────────►  Active  ──────────────────────────►  Resolved
     │                          │
     │ cancel()                 │ refundExpired()
     ▼                          ▼
  Cancelled                  Refunded
```

**Todo estado terminal devolve ficha para alguém.** É o requisito mais importante
de um contrato de custódia, e o que a máquina foi desenhada para garantir: não
existe caminho que deixe IBET preso.

`refundExpired` cobre os dois casos — proposta não aceita (devolve só o
proponente) e aposta ativa (devolve os dois) — e é **chamável por qualquer
pessoa**. Se dependesse do juiz, a inércia dele prenderia o dinheiro dos dois.

## 6. Papéis garantidos por construção

```solidity
if (playerA_ == playerB_ || judge_ == playerA_ || judge_ == playerB_) revert DuplicateRole();
```

O juiz fora da mesa é verificado **uma vez, no deploy**, e vale para sempre. A
alternativa — checar a cada aposta — seria mais cara e teria um caminho a mais
para esquecer.

Consequência de projeto: `createBet` **não recebe o endereço do oponente**. Só
existem dois jogadores, então `opponentOf(msg.sender)` resolve sozinho. Um campo
a menos para o usuário errar.

## 7. `agreeOn`: o juiz como desempate

```solidity
agreementVote[id][msg.sender] = winner;
if (agreementVote[id][opponentOf(msg.sender)] == winner) _settle(id, winner, true);
```

Cada jogador registra quem acha que ganhou. Quando os dois apontam a mesma
pessoa, liquida na hora. Se discordarem, nada acontece e o juiz decide.

Na maioria das apostas o resultado é óbvio para os dois, e obrigar a passar pelo
juiz seria burocracia. A liquidação guarda `byAgreement` para o painel poder
mostrar *como* cada aposta foi decidida.

## 8. Ordem das operações em `_settle`

```solidity
bet.status = Status.Resolved;                  // estado primeiro
bet.winner = winner;
grossWon[epoch][winner] += stake;

_transfer(address(this), winner, stake * 2);   // fichas
_netCredit(winner, loser, stake);              // dívida
```

Checks-effects-interactions: o estado muda antes de qualquer transferência. Mesmo
que houvesse reentrada, a segunda entrada encontraria `Resolved` e reverteria em
`WrongStatus`.

## 9. Aritmética de calendário

`block.timestamp` é um contador de segundos; não existe "mês" na EVM. Converter
timestamp em ano/mês exige lidar com meses de tamanhos diferentes, anos
bissextos e a regra dos séculos (2000 é bissexto, 2100 não é).

O contrato usa o algoritmo **days_from_civil / civil_from_days de Howard
Hinnant** — aritmética inteira, sem laço, sem tabela de meses. A ideia central: o
calendário gregoriano se repete a cada **400 anos**, que têm exatamente 146.097
dias. Reduzindo a data a "qual ciclo de 400 anos" e "qual dia dentro do ciclo",
as irregularidades viram divisões inteiras.

**Verificação:** as duas funções foram portadas para Python e comparadas com
`datetime` dia a dia de 2024 a 2031, mais os casos de borda (29/02/2024,
31/12 23:59:59, 2000 e 2100). Zero divergências.

> A época 0 quase nunca é um mês inteiro — vai do deploy até a virada. É
> proposital: alinhar ao calendário importa mais do que a primeira época ter
> duração cheia.

## 10. Erros customizados

`NotAPlayer`, `NotTheJudge`, `NotAuthorized`, `WrongStatus(atual, esperado)`,
`DeadlinePassed`, `DeadlineNotReached`, `WinnerNotInBet`, `InvalidText(len, max)`,
`DuplicateRole`, `NonTransferable`, `OnlyController`.

Além de gastarem menos gás que `require` com string, **carregam o dado** — no
Remix aparece exatamente qual status a aposta tem e qual era esperado. A reversão
vira conteúdo demonstrável em vez de mensagem genérica.

## 11. O painel

[`index.html`](../index.html) é um arquivo, sem banco, sem servidor, sem chave de
API. Uma chamada a `tableSummary()` traz época, fim do mês, ganhos, fichas e
posição líquida de uma vez; o resto vem de `getBet(i)`.

Mostra a posição líquida em destaque ("Leon deve R$ X ao Hugo"), o placar do mês,
cada aposta com seu estado, e a explicação da dinâmica com diagramas.

Nomes vêm de `tableNames()` e são **escapados** antes de entrar no HTML: nome é
texto escrito por usuário, e sem tratamento alguém registraria
`<img src=x onerror=...>` e executaria script na página de quem abrisse.

---

## 12. Matriz de verificação antes do deploy

| # | Cenário | Esperado |
|---|---|---|
| 1 | `mintChips` para endereço fora da mesa | reverte `NotAPlayer` |
| 2 | `createBet` por quem não é jogador | reverte `NotAPlayer` |
| 3 | `createBet` + `balanceOf(contrato)` | entrada em custódia |
| 4 | `acceptBet` pelo próprio proponente | reverte `NotAuthorized` |
| 5 | `acceptBet` pelo oponente | status `Active`, duas entradas travadas |
| 6 | `resolveBet` por um jogador | reverte `NotTheJudge` |
| 7 | `resolveBet` pelo juiz | fichas ao vencedor + crédito emitido |
| 8 | `credit.transfer(...)` | reverte `NonTransferable` |
| 9 | `credit.mint(...)` chamado por fora | reverte `OnlyController` |
| 10 | Segunda aposta, vencida pelo outro | crédito **compensa** em vez de somar |
| 11 | `netPosition()` | um credor só, valor líquido |
| 12 | `confirmPayment` pelo devedor | reverte por saldo zero |
| 13 | `confirmPayment` pelo credor | crédito queimado |
| 14 | `agreeOn` pelos dois com o mesmo vencedor | liquida sem o juiz |
| 15 | `refundExpired` antes do prazo | reverte `DeadlineNotReached` |

Boa parte são casos que **devem** reverter. Um contrato testado só no caminho
feliz não está testado.

---

## Limitações conhecidas

1. **Juiz é ponto de confiança** — ver modelagem §7.1.
2. **Mesa de dois** — a compensação depende disso.
3. **`chipsInEscrow()` percorre todas as apostas.** É `view`, então não custa gás
   em transação, mas com milhares de apostas ficaria pesado para o nó.
4. **Sem paginação no painel** — `getBet` é chamado uma vez por aposta.
5. **Tesouraria também é jogador** — dano nulo porque a ficha é fictícia.

---

← [README](../README.md) · [Modelagem](modelagem.md) · [Deploy](deploy.md)
