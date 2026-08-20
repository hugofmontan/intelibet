# INTELIBET — a mesa de apostas do Inteli

Dois amigos apostam, um terceiro julga. **Duas moedas**: uma ficha para apostar e
um crédito que diz quanto precisa ser pago de verdade.

**Painel ao vivo: https://hugofmontan.github.io/intelibet/**

> Entrega individual — **Questão de Computação 1**, Semana 03
> Módulo AD07 · Tokenização de Ativos e Web3 · Inteli · Turma 2026-2B-T19
> Aluno: Hugo de Freitas Montan · Professor: Bryan Kano Ferreira

---

## Onde está cada coisa

| Documento | Conteúdo |
|---|---|
| [`docs/modelagem.md`](docs/modelagem.md) | **Etapa 1** — problema, os dois tipos de token, parâmetros, circulação, ecossistema, riscos |
| [`docs/implementacao.md`](docs/implementacao.md) | **Etapa 2** — os dois contratos, decisão por decisão |
| [`docs/deploy.md`](docs/deploy.md) | Passo a passo Sepolia + evidências on-chain |
| [`docs/uso-de-ia.md`](docs/uso-de-ia.md) | Prompts usados, o que foi aceito e o que foi rejeitado |
| [`contracts/InteliBet.sol`](contracts/InteliBet.sol) | Os dois contratos, num arquivo |
| [`index.html`](index.html) | O painel — estado da mesa e explicação da dinâmica |
| [`ROTEIRO-VIDEO.md`](ROTEIRO-VIDEO.md) | Roteiro cronometrado da demonstração |

---

## O problema

Aposta entre amigos falha no depois: o pagamento fica no fiado, ninguém lembra os
termos, e não há como saber quem está devendo quanto a quem.

E o caminho óbvio — "faz um contrato que obrigue a pagar" — não existe. Pelo
**art. 814 do Código Civil, dívida de jogo ou aposta é obrigação natural**: não
obriga a pagamento e não pode ser cobrada em juízo. Não há execução forçada nem
em tese.

O que dá para construir, então, não é cobrança — é **uma conta única, pública e
que o devedor não consegue manipular**.

---

## Por que dois tokens

Uma aposta entre amigos tem duas coisas dentro dela que não são a mesma coisa: a
**brincadeira** e a **dívida**. Um token só obriga a escolher entre as duas — ou
ele é fictício e a dívida não significa nada, ou ele vale dinheiro e cada aposta
boba vira transação financeira.

| | **Ficha** `IBET` | **Crédito** `IBRL` |
|---|---|---|
| O que é | moeda fictícia da mesa | R$ 1,00 a receber, na vida real |
| Tipo | **utility** | **stablecoin de obrigação** |
| Transferível | **sim** — ERC-20 comum | **não** — é registro, não dinheiro |
| Como nasce | tesouraria emite à vontade | só de aposta resolvida, no valor exato |
| Como morre | queima | só por confirmação de quem tinha a receber |
| Divisibilidade | `decimals = 2` | `decimals = 2` |

**O lastro do crédito não é uma reserva — é a obrigação reconhecida do
perdedor.** Isso é mais honesto do que atestar uma reserva que não existe numa
rede de teste, e mantém a pergunta que importa com resposta em código: *o que
impede alguém de criar dívida do nada?* Nada além de uma aposta resolvida cria
crédito, e o controlador do token de crédito é o contrato da mesa, ninguém mais.

---

## As três decisões que sustentam o projeto

### 1. Custódia, porque a sentença precisa ter efeito

As duas entradas em ficha ficam no contrato desde a criação da aposta. Sem isso o
juiz declararia o vencedor e o perdedor simplesmente não pagaria — travar antes é
o que dá efeito à decisão.

Efeito colateral: com dois jogadores fixos e um juiz que nunca é parte,
**não existe auto-aposta**. Ninguém fabrica vitória contra si mesmo.

### 2. Compensação: abater antes de emitir

Se cada vitória apenas emitisse crédito, os dois acumulariam saldo e ninguém
saberia quem deve a quem. A vitória primeiro **anula a dívida contrária**, e só o
que sobra vira dívida nova.

```
Leon tem R$ 30 a receber.  Hugo ganha R$ 50.
   → queima 30 do Leon · emite 20 para o Hugo
   → Hugo tem R$ 20 a receber
```

**A invariante:** no máximo **um** dos dois tem saldo de crédito em qualquer
momento. O saldo *é* a resposta para "quem deve quanto a quem" — não existe
versão divergente da conta.

### 3. Só o credor confirma o pagamento

O devedor não tem função nenhuma que reduza a própria dívida. Quem recebeu o Pix
chama `confirmPayment(valor)` e o crédito é queimado. Se o devedor pudesse
apagar, o registro não valeria nada.

---

## O ciclo de uma aposta

| Estado | Como se chega | Onde estão as fichas |
|---|---|---|
| **Aberta** | `createBet(valor, termos, prazo)` | entrada do proponente no contrato |
| **Em andamento** | `acceptBet(id)` pelo outro | as duas entradas no contrato |
| **Resolvida** | `agreeOn` pelos dois, ou `resolveBet` pelo juiz | tudo para o vencedor; crédito compensado |
| **Cancelada** | `cancelBet(id)` antes do aceite | devolvidas ao proponente |
| **Devolvida** | `refundExpired(id)` após o prazo | devolvidas aos dois |

Todo estado final devolve ficha para alguém — **não existe estado em que IBET
fique preso no contrato**.

`refundExpired` é chamável por **qualquer pessoa**, de propósito: se dependesse
do juiz, a inércia dele prenderia o dinheiro dos dois para sempre.

E o juiz decide **quem** ganhou, nunca **quanto**: não altera valor, não paga
terceiro e não retém nada. Se os dois concordam, `agreeOn` liquida sem ele — o
juiz é desempate, não pedágio.

---

## Base técnica

Solidity ^0.8.20 sobre OpenZeppelin v5. Dois contratos num arquivo:
`InteliBet` cria o `InteliCredit` no próprio construtor, então **um deploy
publica os dois** e não existe janela em que o crédito esteja sem controlador.

O mês é mês de verdade — a época vira à meia-noite UTC do dia 1º. Como não há
calendário na EVM, o contrato converte timestamp em ano/mês pelo algoritmo
*days_from_civil* de Howard Hinnant: aritmética inteira, sem laço, com bissextos
e a regra dos séculos. As funções foram portadas para Python e conferidas contra
`datetime` dia a dia de 2024 a 2031 — zero divergências.

---

## Design responsável

| Recorte | Como é garantido |
|---|---|
| **Não existe banca** | O contrato não define cotação, não toma o outro lado e não retém percentual — em nenhuma das duas camadas |
| **Não existe empréstimo** | Só se aposta ficha que já se tem |
| **Juiz nunca é parte** | Garantido no construtor, não por verificação que alguém possa esquecer |
| **Ficha só para jogador** | `mintChips` recusa endereço fora da mesa |
| **Ambiente de teste** | Sepolia; nenhum valor real transita neste projeto |

### Limites assumidos

O **juiz é ponto de confiança**: se decidir errado, o contrato paga assim mesmo.
A mesa é de **dois jogadores fixos** — abrir para mais gente exige outro desenho
de compensação. E o acerto final acontece **fora da rede**: o contrato registra a
dívida e a extinção dela, não move dinheiro de verdade.

---

## Evidências on-chain

> Preencher após o deploy. Detalhe em [`docs/deploy.md`](docs/deploy.md).

| Item | Valor |
|---|---|
| Rede | Sepolia (chainId 11155111) |
| Ficha `InteliBet` | [`0x57DeD57F8ebA2db718c6426D36E7Ff37Bf675d1f`](https://sepolia.etherscan.io/address/0x57DeD57F8ebA2db718c6426D36E7Ff37Bf675d1f) |
| Crédito `InteliCredit` | [`0x9aA324854f9c671d1FaC128be9F35091599eB12A`](https://sepolia.etherscan.io/address/0x9aA324854f9c671d1FaC128be9F35091599eB12A) |
| Jogador A (Hugo) | `0xf6e3a81cf77979eeac3874fc8245573c92e8eaf0` |
| Jogador B (Leon) | `0xf4a3d4add2c15df016e66138ad96f30302b0134d` |
| Juiz (Rodrigo) | `0x6d240b001307b577500195846af94dbaf0061fe4` |
| **Tx de transferência entre carteiras** | `0x` |
| Tx de aposta resolvida | `0x` |
| Painel | https://hugofmontan.github.io/intelibet/ |
| Vídeo (≤ 10 min) | *link* |

---

## Status da entrega

- [x] Etapa 1 — ideação e modelagem documentadas
- [x] Etapa 2 — contratos escritos e comentados
- [x] Documentação técnica organizada no repositório
- [x] Painel com estado da mesa e explicação da dinâmica
- [ ] Deploy na Sepolia realizado
- [ ] Transferência entre duas carteiras visível no explorador
- [ ] Ciclo completo de aposta demonstrado
- [ ] Vídeo de até 10 minutos gravado
- [ ] Link entregue na AdaLove
