# Etapa 1 — Idealização e modelagem do token

> Responde, na ordem, aos cinco pontos exigidos no enunciado: problema/proposta
> de valor · tipo do token · parâmetros de modelagem · circulação e permissões ·
> relação com o ecossistema. As seções 6 e 7 tratam de design responsável e dos
> riscos assumidos.

---

## 1. Problema e proposta de valor

Aposta entre amigos é combinado corriqueiro no Inteli: quem entrega primeiro,
qual time ganha o interclasses, se a nota da ponderada passa de tanto. O
combinado é fácil. O que falha é **o depois**:

| Falha | O que acontece na prática |
|---|---|
| O pagamento fica no fiado | "Depois eu te pago" vira duas semanas, vira nunca |
| Não sobra registro | Ninguém lembra quem ficou devendo o quê |
| Ninguém tem histórico | Não existe como saber quem realmente ganha aposta e quem só fala |
| Nada premia quem paga | Honrar aposta não traz nenhuma vantagem sobre não honrar |

As três primeiras são a mesma coisa vista de perto e de longe: **não existe
memória**. A quarta é a que o desenho precisa resolver junto, e é a razão do
mecanismo de prêmio da seção 5.

Vale entender por que o caminho óbvio — "faz um contrato que obrigue a pagar" —
não existe. Pelo **art. 814 do Código Civil, dívida de jogo ou aposta é
obrigação natural**: não obriga a pagamento e não pode ser cobrada em juízo. Não
há execução forçada nem em tese. Diante disso restam dois desenhos possíveis:

1. **travar o valor antes** — custódia, árbitro, prazo, máquina de estados;
2. **trocar a garantia jurídica por garantia reputacional** — o pagamento
   continua voluntário, mas o histórico de quem paga fica público e permanente.

Este projeto escolhe o segundo. É mais simples, e é mais honesto sobre o que
consegue garantir.

**Proposta de valor do IBET:** dar à aposta entre amigos uma unidade de valor
estável, uma memória que ninguém controla e um motivo concreto para participar
registrando.

> A frase que resume o desenho: **o contrato não garante o pagamento — garante
> que todo mundo saiba quem pagou, e paga um prêmio a quem mais ganha.**

---

## 2. Tipo do token e justificativa

**Tipo escolhido: stablecoin** (colateralização 1:1 com o real).

O argumento decisivo é temporal. **A aposta é feita hoje e paga depois** — às
vezes semanas depois. Entre os dois momentos, o valor apostado precisa
significar a mesma coisa:

> Se o token oscilasse 20% para baixo no intervalo, quem *ganhou* receberia
> menos poder de compra do que arriscou. O resultado da aposta passaria a
> depender do mercado em vez do que foi combinado. Isso não é detalhe de
> implementação — destrói a coisa que a aposta é.

O prêmio mensal reforça o argumento em vez de enfraquecê-lo: um pote que se
acumula ao longo de trinta dias em token volátil valeria uma coisa quando as
apostas foram pagas e outra na hora de entregar. Estabilidade é requisito de
qualquer instrumento que **acumule** valor no tempo.

Por que os outros dois tipos não servem:

| Tipo | Por que não |
|---|---|
| *Utility* | Utility dá acesso a um produto ou serviço do emissor. O IBET não libera nada — ele **é** o valor em disputa. E utility não assume compromisso de preço, que é justamente o requisito. |
| *Governance* | Não há decisão coletiva sendo tomada. Nada aqui é votado. |

**O que separa uma stablecoin real de um ERC-20 com nome bonito:** dizer
"1 IBET = R$ 1,00" não vale nada sozinho. A pergunta que qualquer um faz é
*"o que impede a tesouraria de emitir o dobro amanhã?"*. A resposta está na
seção 3, em código.

---

## 3. Parâmetros de modelagem

| Parâmetro | Valor | Justificativa |
|---|---|---|
| **Nome** | `InteliBet` | Nome próprio, sem sugerir promessa de rendimento. |
| **Símbolo** | `IBET` | Ticker curto; símbolo longo fica cortado em carteira e explorador. |
| **Paridade** | 1 IBET = R$ 1,00 | Aposta é combinada em reais; qualquer outra unidade obrigaria conversão mental na hora de apostar. |
| **Divisibilidade** | `decimals = 2` | Pareia com o centavo do real. As 18 casas do default existem para tokens sem correspondência com moeda fiduciária — aqui criariam saldos impossíveis de pagar no resgate. |
| **Supply total** | **Sem teto fixo** | Ver abaixo. |
| **Lastro** | `reservesAttested` — reserva sob custódia da tesouraria, publicada on-chain com valor, hash do comprovante e timestamp | É o teto real. |
| **Emissão** | `mint` restrito à tesouraria, rejeitado se `totalSupply + amount > reservesAttested` | A invariante do peg. |
| **Validade da atestação** | 30 dias (`ATTESTATION_MAX_AGE`) | Reserva atestada uma vez não autoriza emissão para sempre. |
| **Resgate** | `redeem(amount, payoutRef)` — queima e registra o pedido de pagamento em reais | A queima vem antes do pagamento, então a colateralização nunca piora durante um resgate. |
| **Pagamento de aposta** | `settleBet(winner, amount, description)` | Transfere, cobra a taxa e emite `BetSettled`. |
| **Taxa** | **5%** (`FEE_BPS = 500`), **só sobre aposta paga** | Ver seção 5. |
| **Época** | `epochDuration`, definido no deploy | 30 dias em produção; alguns minutos num deploy de demonstração. |
| **Elegibilidade ao prêmio** | `minDistinctOpponents`, definido no deploy | Mitigação de auto-aposta. Ver seção 7. |
| **Aposta mínima** | 20 unidades base (R$ 0,20) | Abaixo disso a taxa truncaria para zero e a aposta entraria no ranking sem alimentar o pote. |

### Por que uma stablecoin *não* pode ter teto fixo de supply

É a decisão de modelagem menos óbvia aqui, e vale registrar o contraste. Num
token de governança, teto imutável é a garantia central: sem ele, quem emite
dilui o voto de todo mundo. Numa stablecoin seria **defeito** — o supply tem que
subir quando entra dinheiro na reserva e cair quando alguém resgata.

O que substitui o teto é a invariante:

```
                totalSupply() <= reservesAttested
```

Verificada dentro do `mint`, que é o único caminho de emissão do contrato.

### O que a invariante garante — e o que não garante

Garante que **ninguém emite IBET sem antes publicar, com hash e timestamp, uma
reserva que cubra a emissão**. Não garante que o extrato por trás do hash seja
verdadeiro — isso é atestação, e depende de auditoria externa, como em qualquer
stablecoin lastreada em moeda fiduciária.

> **A taxa não afeta o peg.** Os 5% saem de uma conta e entram na do próprio
> contrato: o supply não muda, e a invariante continua valendo. O pote é IBET
> lastreado como qualquer outro — não é dinheiro criado do nada.

---

## 4. Circulação, transferência e permissões

### 4.1 Circulação livre — de propósito

O IBET **não** restringe transferência a uma lista de membros. É escolha, e o
inverso da que faria sentido num token de governança: uma stablecoin é meio de
pagamento, e meio de pagamento que precisa de autorização para circular deixa de
ser meio de pagamento.

O recorte "pessoas do Inteli" acontece na **porta de entrada** — quem obtém IBET
da tesouraria é a comunidade —, não no `transfer`.

### 4.2 Os dois caminhos de transferência

Aqui está a decisão estrutural do contrato:

| Função | O que faz | Taxa? | Entra no ranking? |
|---|---|---|---|
| `transfer` (herdado do ERC-20) | move IBET | **não** | **não** |
| `settleBet(winner, amount, description)` | move IBET, retém 5% e emite `BetSettled` | **sim** | **sim** |

Duas razões para a taxa não incidir sobre `transfer`:

1. **Técnica.** Um ERC-20 que entrega menos do que foi mandado — *fee on
   transfer* — quebra carteira, exchange e qualquer contrato que faça conta
   antes de transferir. E o token deixaria de ser um ERC-20 previsível, que é
   exatamente o que se está entregando.
2. **Conceitual.** Aposta paga tem rake; mandar dinheiro para um amigo não é
   aposta e não deve pagar nada.

E um `Transfer` de 20 IBET pode ser aposta paga, rateio de lanche ou empréstimo
devolvido. Ranking montado em cima de `Transfer` puro seria lixo. `settleBet` é
a declaração explícita de que aquilo foi uma aposta.

### 4.3 `approve` / `transferFrom`

Ficam como a OpenZeppelin entrega, sem uso especial nesta modelagem. Existem
porque fazem parte do padrão ERC-20 e porque qualquer aplicação futura vai
precisar deles.

---

## 5. Relação com o ecossistema: taxa, época e prêmio

### 5.1 O problema que o prêmio resolve

Registrar a aposta on-chain custa gás e expõe a derrota. Sem contrapartida,
a tendência é o combinado continuar no Pix e o histórico nunca existir. **O
prêmio é o que paga o custo de participar.**

### 5.2 Como funciona

```
   cada settleBet  →  5% ficam no pote da época corrente
                      95% vão direto para quem ganhou

   fim da época    →  claimPrize(epoca)
                      o pote inteiro vai para quem mais ganhou em apostas
```

O ciclo completo:

```
   PIX para a tesouraria
        ↓
   attestReserves(valor, hash do extrato)      ← reserva publicada
        ↓
   mint(pessoa, valor)                         ← só passa se couber na reserva
        ↓
   ... a aposta acontece na vida real ...
        ↓
   settleBet(vencedor, valor, "sobre o quê")   ← 95% ao vencedor, 5% ao pote
        ↓
   ranking/index.html                          ← lê os eventos e mostra pote e líder
        ↓
   claimPrize(época encerrada)                 ← o líder leva o pote
        ↓
   redeem(valor, chave Pix)                    ← quem quiser sair queima e recebe
```

### 5.3 Por que o ranking do prêmio é por **ganho bruto**, não por saldo líquido

Esta é a decisão técnica mais interessante do contrato, porque a restrição
melhorou o produto.

Para pagar o prêmio, o contrato precisa saber quem é o primeiro. Se o critério
fosse saldo líquido (ganhou − perdeu), o número **desceria** quando alguém
perde — e descobrir o novo líder exigiria percorrer todos os participantes
dentro de uma transação, o que não escala e pode simplesmente não caber no
limite de gás de um bloco.

Ganho bruto só sobe. Isso torna a manutenção do líder uma comparação de uma
linha a cada aposta:

```solidity
if (total > epochLeaderAmount[epoch] && elegivel) { /* novo líder */ }
```

E, como critério de produto, "quem mais ganhou apostas neste mês" é mais direto
de entender do que saldo líquido. A página de ranking mostra **os dois**: o
bruto da época, que decide o prêmio, e o saldo líquido geral, que é o retrato
de longo prazo.

### 5.4 Regras de borda

| Situação | O que acontece |
|---|---|
| Ninguém elegível na época | O pote **passa para a época seguinte**, não é queimado |
| Empate no bruto | Quem chegou primeiro ao valor mantém a liderança (comparação estrita) |
| Ninguém chama `claimPrize` | O pote fica no contrato até alguém chamar; não vence |
| Quem chama `claimPrize` | **Qualquer pessoa** — o valor vai para o líder registrado, não para quem chamou |

A última linha é deliberada: se dependesse do ganhador, um ganhador desatento
deixaria o pote parado; se dependesse da tesouraria, ela teria poder de reter.

### 5.5 O ranking

`ranking/index.html` é uma página estática que lê os eventos `BetSettled` direto
de um nó público da Sepolia e mostra o pote da época, o líder, o tempo restante,
a classificação da época e o placar geral.

Três consequências para a modelagem:

1. **A página não tem poder nenhum.** Não guarda dinheiro, não decide nada. Se
   sair do ar, o histórico continua na blockchain e qualquer um monta outra.
2. **O ranking é o mecanismo, não o enfeite.** Como a garantia é reputacional, a
   página *é* onde a garantia mora.
3. **O prêmio é apurado on-chain, não pela página.** A página mostra; quem decide
   é o contrato. Se as duas discordarem, o contrato está certo.

---

## 6. Design responsável

| Recorte | Como é garantido |
|---|---|
| **A tesouraria não fica com nada da taxa** | Não existe função que permita ao owner sacar o pote. O único caminho de saída do saldo do contrato é `claimPrize`, e ela paga o líder registrado. |
| **Não existe banca** | O contrato não define cotação, não toma o outro lado de aposta nenhuma e não lucra. Os 5% são redistribuídos integralmente entre os próprios participantes. |
| **Não existe crédito** | Só se paga aposta com IBET que já se tem; saldo insuficiente reverte. |
| **O valor da aposta nunca fica em custódia** | Vai direto de quem perdeu para quem ganhou. O contrato só segura o pote. |
| **Comunidade fechada** | A distribuição parte da tesouraria da comunidade, não de mercado aberto. |
| **Ambiente de teste** | Sepolia. Nenhum valor real transita neste projeto. |

> **Registro honesto de mudança de posicionamento.** Uma versão anterior deste
> projeto afirmava "o contrato não retém percentual". Com a taxa, isso deixou de
> ser verdade e a afirmação foi trocada por uma mais precisa: *o contrato retém
> 5%, e devolve 100% disso aos participantes*. A diferença entre rake que
> remunera o emissor e rake que volta para o jogo é exatamente o que separa
> uma banca de um torneio.

## 7. Riscos assumidos e limitações

1. **Não há garantia de pagamento.** Quem perde e some não é obrigado a nada — e
   nunca seria, dado o art. 814. A garantia é reputacional.

2. **Auto-aposta para farmar o prêmio — o risco central do mecanismo.**
   Como `settleBet` é auto-declaratório, alguém pode criar uma segunda carteira,
   transferir IBET para ela e registrar vitórias fabricadas para si mesmo. O
   custo é 5% por rodada; se o pote for maior que o custo de lavar, **fabricar
   vitórias é lucrativo**.

   *Mitigação implementada:* só concorre ao prêmio quem venceu
   `minDistinctOpponents` adversários **distintos** na época. Isso obriga o
   farmador a manter várias carteiras com gás, e a exposição fica pública — o
   ranking mostra quantos adversários distintos cada um tem.

   *Mitigação, não conserto.* Um grupo coordenado de carteiras ainda consegue.
   Caminhos conhecidos para fechar mais: exigir contra-assinatura das duas
   partes, limitar quanto uma mesma dupla contribui para o ranking, ou restringir
   a emissão a endereços verificados pela tesouraria. Ficaram fora do escopo da
   Semana 03, e a escolha está registrada aqui em vez de escondida.

3. **A atestação de reserva é promessa auditável, não prova criptográfica.**

4. **A tesouraria é um endereço único.** Deveria ser multisig, ou
   `AccessControl` com papéis separados.

5. **Endereço não é identidade.** Os apelidos do ranking são um mapa configurado
   na página, não algo verificado on-chain.

6. **`epochDuration` é imutável.** Mudar a duração exige novo deploy. É proposital
   — regra de prêmio que muda no meio do jogo não é regra.

Nenhuma dessas limitações é acidental; todas são recortes conscientes.

---

← [README](../README.md) · [Implementação](implementacao.md) · [Deploy](deploy.md)
