# INTELIBET — a stablecoin de aposta do Inteli

`1 IBET = R$ 1,00`. Quem perde a aposta paga chamando uma função que **transfere
e registra**. 5% de cada aposta paga fica num pote, e no fim do mês **quem mais
ganhou leva o pote inteiro**.

> Entrega individual — **Questão de Computação 1**, Semana 03
> Módulo AD07 · Tokenização de Ativos e Web3 · Inteli · Turma 2026-2B-T19
> Aluno: Hugo de Freitas Montan · Professor: Bryan Kano Ferreira

---

## Onde está cada coisa

| Documento | Conteúdo |
|---|---|
| [`docs/modelagem.md`](docs/modelagem.md) | **Etapa 1** — problema, tipo, parâmetros, circulação, taxa e prêmio, riscos |
| [`docs/implementacao.md`](docs/implementacao.md) | **Etapa 2** — o contrato e o ranking, decisão por decisão |
| [`docs/deploy.md`](docs/deploy.md) | Passo a passo Sepolia + evidências on-chain |
| [`docs/uso-de-ia.md`](docs/uso-de-ia.md) | Prompts usados, o que foi aceito e o que foi rejeitado |
| [`contracts/InteliBet.sol`](contracts/InteliBet.sol) | O token ERC-20 |
| [`ranking/index.html`](ranking/index.html) | Pote, líder e classificação, lidos direto da blockchain |
| [`ROTEIRO-VIDEO.md`](ROTEIRO-VIDEO.md) | Roteiro cronometrado da demonstração |

---

## Resumo em uma tela

**Problema.** Aposta entre amigos falha no depois: o pagamento fica no fiado, não
sobra registro, ninguém tem histórico de quem realmente ganha — e honrar aposta
não traz vantagem nenhuma sobre não honrar.

O caminho óbvio — "faz um contrato que obrigue a pagar" — não existe: pelo
**art. 814 do Código Civil, dívida de aposta é obrigação natural** e não pode ser
cobrada em juízo. Não há execução forçada nem em tese. Sobram dois desenhos:
travar o valor antes (custódia, árbitro, prazo) ou **trocar a garantia jurídica
por garantia reputacional**. Este projeto escolhe o segundo.

> O contrato não garante o pagamento — garante que todo mundo saiba quem pagou,
> e paga um prêmio a quem mais ganha.

**Tipo: stablecoin.** O argumento é temporal — a aposta é feita hoje e paga
depois. Se o token oscilasse no intervalo, quem *ganhou* poderia receber menos
poder de compra do que arriscou, e o resultado passaria a depender do mercado em
vez do que foi combinado. O pote reforça: valor que se acumula por trinta dias
precisa ser estável. Não é utility (não libera produto nem serviço — o token
**é** o valor em disputa) e não é governance (nada aqui é votado).

| Parâmetro | Valor |
|---|---|
| Nome / símbolo | InteliBet / `IBET` |
| Paridade | 1 IBET = R$ 1,00 |
| Divisibilidade | `decimals = 2` — pareia com o centavo do real |
| Supply | **sem teto fixo** — o teto é a reserva |
| Lastro | `reservesAttested`: valor + hash do comprovante + timestamp, on-chain |
| Emissão | `mint` da tesouraria, rejeitado se romper a invariante |
| Pagamento de aposta | `settleBet` — 95% ao vencedor, 5% ao pote, emite `BetSettled` |
| Taxa | 5%, **só sobre aposta paga** — `transfer` comum não paga nada |
| Época | `epochDuration` definido no deploy — 30 dias em produção |
| Prêmio | `claimPrize` — o pote da época vai para quem mais ganhou |

---

## As três decisões que sustentam o projeto

### 1. O peg é uma invariante, não uma promessa

Dizer "1 IBET = R$ 1,00" não vale nada sozinho; a pergunta que qualquer um faz é
*"o que impede a tesouraria de emitir o dobro amanhã?"*. Aqui a resposta está em
código:

```
                totalSupply() <= reservesAttested
```

`mint` é o único caminho de emissão e recusa qualquer valor que quebre a
desigualdade. Como `reserveAttestedAt` começa em zero, **o contrato nasce
impedido de emitir**: sem atestação publicada, a primeira tentativa já reverte.

Corolário: uma stablecoin **não pode** ter teto fixo de supply. Num token de
governança o teto imutável é a garantia central; aqui seria defeito — o supply
precisa subir quando entra dinheiro na reserva e cair no resgate.

**A taxa não afeta o peg:** os 5% saem de uma conta e entram na do próprio
contrato. O supply não muda, e o pote é IBET lastreado como qualquer outro.

### 2. `settleBet` marca o que foi aposta

Um `Transfer` de 20 IBET pode ser aposta paga, rateio de lanche ou empréstimo
devolvido. Ranking montado em cima de `Transfer` puro seria lixo.

```solidity
_transfer(msg.sender, winner, amount - fee);
_transfer(msg.sender, address(this), fee);
emit BetSettled(msg.sender, winner, amount, fee, epoch, description);
```

O pagador é sempre `msg.sender` — ninguém consegue plantar uma derrota na conta
de outra pessoa. E a taxa incide **só aqui**: um ERC-20 que entrega menos do que
foi mandado quebraria carteira, exchange e qualquer contrato que faça conta antes
de transferir. Aposta paga tem rake; mandar dinheiro para um amigo não.

### 3. O prêmio é por ganho bruto — e isso é técnico antes de ser de produto

Para pagar o pote, o contrato precisa saber quem é o primeiro. Saldo líquido
(ganhou − perdeu) **desce** quando alguém perde, e achar o novo líder exigiria
percorrer todos os participantes dentro de uma transação — o que não cabe no gás
de um bloco.

Ganho bruto só sobe. Manter o líder vira uma comparação de uma linha a cada
aposta. E, como métrica, "quem mais ganhou apostas neste mês" é mais direto de
entender do que saldo líquido. A página mostra os dois.

---

## O ranking

**Ao vivo: https://hugofmontan.github.io/intelibet/**

[`ranking/index.html`](ranking/index.html) é um arquivo só. Lê **on-chain** o que
é autoritativo — época, pote, líder, tempo restante — e **dos eventos** o
histórico completo de apostas.

Não tem banco de dados, não tem servidor, não tem chave de API, não decide nada.
Se a página sair do ar, o histórico continua na blockchain e qualquer pessoa monta
outra igual. Numa plataforma de apostas tradicional, o servidor cair significa o
saldo sumir junto — a diferença é o argumento Web3 inteiro deste projeto.

---

## Design responsável

| Recorte | Como é garantido |
|---|---|
| **A tesouraria não fica com nada da taxa** | Não existe função que permita ao owner sacar o pote. O único caminho de saída do saldo do contrato é `claimPrize`, e ela paga o líder registrado |
| Não existe banca | O contrato não define cotação, não toma o outro lado e não lucra — os 5% voltam integralmente para os participantes |
| Não existe crédito | Só se paga com IBET que já se tem; saldo insuficiente reverte |
| O valor da aposta nunca fica em custódia | Vai direto de quem perdeu para quem ganhou; o contrato só segura o pote |
| Comunidade fechada | A distribuição parte da tesouraria da comunidade, não de mercado aberto |
| Ambiente de teste | Sepolia; nenhum valor real transita neste projeto |

### As duas limitações centrais, declaradas

**Não há garantia de pagamento.** Quem perde e some não é obrigado a nada — e
nunca seria. A garantia é reputacional.

**Auto-aposta pode farmar o prêmio.** Como `settleBet` é auto-declaratório,
alguém pode criar uma segunda carteira e registrar vitórias fabricadas. Custa 5%
por rodada; se o pote for maior que o custo de lavar, compensa. A mitigação
implementada — só concorre quem venceu N adversários **distintos** na época —
encarece o ataque e o expõe publicamente, mas não o elimina. Os caminhos para
fechar mais estão em [`docs/modelagem.md §7`](docs/modelagem.md).

---

## Evidências on-chain

> Preencher após o deploy. Detalhe e capturas em [`docs/deploy.md`](docs/deploy.md).

| Item | Valor |
|---|---|
| Rede | Sepolia (chainId 11155111) |
| `InteliBet` | `0x` |
| **Tx de transferência entre carteiras** | `0x` |
| Tx `settleBet` | `0x` |
| Tx `claimPrize` | `0x` |
| Ranking publicado | https://hugofmontan.github.io/intelibet/ |
| Vídeo (≤ 10 min) | *link* |

---

## Como reproduzir

1. Abrir [`contracts/InteliBet.sol`](contracts/InteliBet.sol) no Remix IDE.
2. Compilar com Solidity 0.8.20+ e otimização ligada.
3. Deploy com *Injected Provider – MetaMask* na Sepolia, com três argumentos:
   endereço da tesouraria, `epochDuration` (use `600` para conseguir demonstrar
   o prêmio) e `minDistinctOpponents` (use `1` com duas contas).
4. Seguir a sequência de [`docs/deploy.md §3`](docs/deploy.md) — ela inclui os
   casos que **devem reverter**, que são o que demonstra a modelagem
   funcionando.
5. Preencher `CONTRATO` e `BLOCO_INICIAL` no topo de
   [`ranking/index.html`](ranking/index.html) e abrir no navegador.

Todos os valores vão em centavos: `decimals = 2`, então `50000` = R$ 500,00.

---

## Status da entrega

- [x] Etapa 1 — ideação e modelagem documentadas
- [x] Etapa 2 — contrato escrito e comentado
- [x] Documentação técnica organizada no repositório
- [x] Ranking com pote, líder e classificação
- [ ] Deploy na Sepolia realizado
- [ ] Transferência entre duas carteiras visível no explorador
- [ ] Apostas registradas e prêmio distribuído
- [ ] Ranking ligado ao contrato publicado
- [ ] Vídeo de até 10 minutos gravado
- [ ] Repositório publicado e link entregue na AdaLove
