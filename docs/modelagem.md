# Etapa 1 — Idealização e modelagem

> Responde, na ordem, aos cinco pontos exigidos no enunciado: problema/proposta
> de valor · tipo do token · parâmetros de modelagem · circulação e permissões ·
> relação com o ecossistema. As seções 6 e 7 tratam de design responsável e dos
> riscos assumidos.

---

## 1. Problema e proposta de valor

Aposta entre amigos é combinado corriqueiro: quem entrega primeiro, qual time
ganha o interclasses, quem perde mais peso no mês. O combinado é fácil. O que
falha é **o depois**:

| Falha | O que acontece na prática |
|---|---|
| O pagamento fica no fiado | "depois eu te pago" vira duas semanas, vira nunca |
| Os termos são verbais | duas semanas depois cada um lembra de um combinado diferente |
| Não existe placar | ninguém sabe quem está devendo quanto a quem |
| Cada aposta é um evento solto | dez apostas viram dez cobranças em vez de uma conta |

### Por que não dá para "obrigar a pagar"

Pelo **art. 814 do Código Civil, dívida de jogo ou aposta é obrigação natural**:
não obriga a pagamento e não pode ser cobrada em juízo. Não existe execução
forçada nem em tese, então qualquer promessa de cobrança seria encenação.

O que dá para construir não é cobrança. É **uma conta única, pública, com termos
congelados antes do resultado, que o devedor não consegue manipular** — e um
mecanismo que faz as apostas se compensarem entre si, para que dinheiro de
verdade só precise mudar de mão quando o saldo acumulado justificar.

### A proposta

Uma mesa de três papéis fixos — dois jogadores e um juiz — em que a aposta é
travada antes do resultado e a dívida resultante é calculada, compensada e
registrada automaticamente.

> **A frase que resume:** o contrato não garante o pagamento — garante que a
> conta seja uma só, pública, e que quem deve não consiga mexer nela.

---

## 2. Os tipos de token, e por que são dois

Uma aposta entre amigos tem **duas coisas dentro dela que não são a mesma**: a
brincadeira (apostar, acompanhar, ganhar) e a dívida (dinheiro de verdade mudando
de mão). Um token só obriga a escolher entre as duas:

- se ele for fictício, a dívida não significa nada;
- se ele valer dinheiro, cada aposta boba vira uma transação financeira.

Por isso o projeto tem **dois contratos ERC-20**, publicados juntos, com
propriedades deliberadamente opostas.

### 2.1 Ficha — `IBET` — **utility token**

É a moeda da mesa. Serve para uma coisa só: existir dentro do sistema para que a
aposta possa ser travada e acompanhada on-chain sem mover dinheiro real.

**Por que utility:** ela dá acesso ao mecanismo — sem ficha não se cria aposta —
e não promete valor nenhum. Não é stablecoin porque não há paridade nem lastro, e
declarar paridade sem lastro seria exatamente a mentira que este projeto evita.
Não é governance porque nada é votado.

Ser explicitamente fictícia é o que a libera para **circular sem restrição**: se
não vale nada, não há risco em transferir.

### 2.2 Crédito — `IBRL` — **stablecoin de obrigação**

`1 IBRL = R$ 1,00 a receber`. Saldo de crédito é quanto aquela pessoa tem a
receber da outra, em reais.

**Por que stablecoin:** ela tem paridade fixa com o real e um lastro que sustenta
a paridade. A diferença para o modelo usual está em *qual* lastro:

| Modelo | Lastro |
|---|---|
| Stablecoin fiduciária (USDC) | reserva bancária atestada por auditor |
| Stablecoin cripto-colateralizada (DAI) | cripto em excesso, com liquidação |
| **IBRL** | **a obrigação reconhecida do perdedor de uma aposta resolvida** |

O crédito é, em essência, um **recebível tokenizado** — que aliás é o tema do
módulo. E a pergunta que qualquer um faz a uma stablecoin continua com resposta
em código:

> *O que impede alguém de criar dívida do nada?*
> Crédito só é emitido dentro da liquidação de uma aposta resolvida, no valor
> exato apostado, e o único endereço autorizado a emitir é o contrato da mesa.
> Nem os jogadores, nem o juiz, nem o dono conseguem criar crédito por fora.

Uma versão anterior deste projeto declarava reserva bancária atestada. Numa rede
de teste, aquilo era atestação de uma reserva que não existe — teatro. Lastrear
em obrigação é menos ambicioso e **verdadeiro**.

---

## 3. Parâmetros de modelagem

| Parâmetro | Ficha `IBET` | Crédito `IBRL` |
|---|---|---|
| Nome | InteliBet Chip | InteliBet Credit |
| Paridade | nenhuma (fictícia) | 1 IBRL = R$ 1,00 a receber |
| Divisibilidade | `decimals = 2` | `decimals = 2` |
| Supply | sem teto — a tesouraria emite à vontade | igual à dívida líquida existente |
| Emissão | `mintChips`, só para jogador | só dentro da liquidação de aposta |
| Destruição | custódia move, não queima | `confirmPayment`, só pelo credor |
| Transferível | **sim** | **não** |

**Por que 2 casas nos dois.** O crédito pareia com o centavo do real, e a ficha
acompanha para que os valores sejam lidos na mesma escala — apostar "50" é R$ 50
nas duas camadas. As 18 casas do default existem para tokens sem correspondência
com moeda; aqui criariam saldos impossíveis de pagar.

**Por que a ficha não tem teto.** Ela é explicitamente fictícia. Teto de supply
serve para proteger valor, e não há valor a proteger — quem carrega significado é
o crédito, e esse tem um teto muito mais forte que um número: **só existe se
houver aposta resolvida por trás**.

### Papéis, fixos no deploy

| Papel | Quem |
|---|---|
| `playerA` | Hugo |
| `playerB` | Leon |
| `judge` | Rodrigo |
| owner / tesouraria | emite as fichas |

Gravados como `immutable`. O construtor recusa juiz igual a jogador e jogadores
iguais entre si — **o juiz fora da mesa é garantido por construção**, não por uma
verificação por aposta que alguém possa esquecer de fazer.

### Outros parâmetros de deploy

| Parâmetro | Papel |
|---|---|
| `settlementThreshold` | dívida líquida a partir da qual o contrato pede acerto real |
| `epochDuration` | `0` = mês de calendário; em segundos = janela fixa, para demonstração |

---

## 4. Circulação e permissões

### 4.1 A ficha circula, o crédito não

| | `IBET` | `IBRL` |
|---|---|---|
| `transfer` entre pessoas | permitido | **reverte** `NonTransferable` |
| mint / burn | tesouraria / custódia | só o contrato da mesa |

Bloquear a transferência do crédito é o que separa **registro de obrigação** de
**dinheiro**. Dívida entre duas pessoas específicas não circula: se ela pudesse
ser vendida a um terceiro, deixaria de ser o retrato da relação entre os dois.

> **Nota de conformidade.** Restringir transferência não descumpre o ERC-20: o
> padrão define assinaturas, retornos e eventos, e não obriga que toda
> transferência seja aceita. As funções continuam canônicas e os eventos são
> emitidos, então carteiras e exploradores reconhecem o token e mostram saldo
> normalmente.

### 4.2 Quem pode o quê

| Ação | Quem |
|---|---|
| `mintChips` | tesouraria, e só para endereço de jogador |
| `createBet` · `acceptBet` · `agreeOn` · `confirmPayment` | só os dois jogadores |
| `resolveBet` | só o juiz |
| `cancelBet` | só o proponente da aposta |
| `refundExpired` | **qualquer pessoa** |

A última linha é deliberada: se a devolução por prazo vencido dependesse do juiz,
a inércia dele prenderia as fichas dos dois para sempre. É a saída de emergência
do sistema, e ela não pode ter dono.

### 4.3 `approve` / `transferFrom`

Ficam como a OpenZeppelin entrega na ficha, sem uso especial — a custódia usa
`_transfer` interno, então não há passo de aprovação. No crédito eles existem por
conformidade, mas qualquer transferência reverte.

---

## 5. Relação com o ecossistema

```
   tesouraria emite fichas para os dois jogadores
        ↓
   createBet(valor, termos, prazo)      ← entrada do proponente travada
        ↓
   acceptBet(id)                        ← entrada do oponente travada
        ↓
   ... o resultado acontece na vida real ...
        ↓
   agreeOn(id, vencedor) pelos dois     ← liquida sem o juiz
      ou resolveBet(id, vencedor)       ← o juiz desempata
        ↓
   ┌────────────────────┬──────────────────────────────┐
   │ fichas → vencedor  │ crédito compensado           │
   │ (camada da mesa)   │ (camada do dinheiro real)    │
   └────────────────────┴──────────────────────────────┘
        ↓
   saldo cruza o limiar → evento SettlementDue
        ↓
   pagamento por Pix, fora da rede
        ↓
   confirmPayment(valor) pelo credor    ← o crédito é queimado
```

### A compensação, que é o coração do desenho

Se cada vitória apenas emitisse crédito, os dois acumulariam saldo e o sistema
diria "Hugo tem 300 a receber e Leon tem 250 a receber", que não é resposta
nenhuma. A regra é **abater antes de emitir**:

```
Leon tem R$ 30 a receber.  Hugo ganha R$ 50.
   queima 30 do Leon   →  a dívida antiga se anula
   emite  20 ao Hugo   →  sobra o líquido
```

**Invariante:** no máximo **um** dos dois tem saldo de crédito em qualquer
momento. O saldo *é* a resposta para "quem deve quanto a quem" — ninguém calcula
nada, e não existe versão divergente da conta.

Consequência que muda o uso: perder uma aposta nem sempre cria dívida — na maior
parte das vezes apenas abate a que existia. As apostas se compensam sozinhas, e
dinheiro real só precisa mudar de mão quando o líquido cresce o bastante. É
compensação de posições, o mesmo princípio de uma câmara de liquidação.

### O painel

[`index.html`](../index.html) é uma página estática que lê o contrato e mostra a
posição líquida, o placar do mês, as apostas em cada estado e a explicação da
dinâmica. Não guarda dado, não tem servidor, não decide nada — se sair do ar, o
estado continua na blockchain e qualquer pessoa monta outra igual.

### O mês

O placar é mensal, e o mês é de calendário: a época vira à meia-noite UTC do dia
1º. "Quem ganhou mais em agosto" só faz sentido alinhado ao mês real, não a uma
janela de trinta dias contada do deploy.

---

## 6. Design responsável

| Recorte | Como é garantido |
|---|---|
| **Não existe banca** | O contrato não define cotação, não toma o outro lado de nenhuma aposta e não retém percentual — em nenhuma das duas camadas. O vencedor recebe exatamente as duas entradas. |
| **Não existe empréstimo** | Só se aposta ficha que já se tem; saldo insuficiente reverte. |
| **Não existe auto-aposta** | Dois jogadores fixos, custódia e um juiz que nunca é parte. Não há como fabricar vitória contra si mesmo. |
| **Juiz limitado** | Decide *quem*, nunca *quanto*. Não altera valor, não paga terceiro, não retém nada. |
| **Toda saída devolve dinheiro** | Não existe estado em que ficha fique presa no contrato. |
| **Ficha fora da mesa não existe** | `mintChips` recusa endereço que não seja jogador. |
| **Ambiente de teste** | Sepolia. Nenhum valor real transita neste projeto. |

---

## 7. Riscos assumidos e limitações

1. **O juiz é um ponto de confiança.** Se o Rodrigo decidir errado, o contrato
   paga assim mesmo. O `agreeOn` reduz a exposição — quando os dois concordam,
   ele nem é acionado —, mas não elimina. Mitigações conhecidas: painel de três
   juízes com maioria, ou depósito de garantia que o juiz perde se for
   contestado. Fora do escopo da Semana 03.

2. **A mesa é de dois.** Toda a compensação depende de existirem exatamente dois
   lados. Abrir para mais gente exige um desenho de netting multilateral, que é
   um problema qualitativamente diferente.

3. **O acerto acontece fora da rede.** O contrato registra a dívida e a extinção
   dela, não move dinheiro de verdade. É escolha, não limitação técnica: o que
   ele garante é que a conta seja única, pública e não manipulável por quem deve.

4. **`confirmPayment` depende da honestidade do credor.** Se ele receber e não
   confirmar, a dívida continua registrada. O incentivo joga a favor — o devedor
   tem comprovante de Pix e pressão social —, mas o contrato não resolve isso.

5. **A tesouraria é um endereço único** e também é jogador. Ela pode emitir
   fichas para si mesma sem limite. Como a ficha é fictícia, o dano é nulo; num
   desenho com valor real, tesouraria e jogador teriam que ser separados.

6. **Termos são texto livre.** "Quem perde mais peso" pode gerar discussão sobre
   critério — o contrato congela a frase, não a interpreta. É exatamente para
   isso que existe o juiz.

Nenhuma dessas limitações é acidental; todas são recortes conscientes.

---

← [README](../README.md) · [Implementação](implementacao.md) · [Deploy](deploy.md)
