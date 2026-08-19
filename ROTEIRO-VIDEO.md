# Roteiro do vídeo — máx. 10 minutos

**Alvo real: 9:00.** Estourar 10 min é o erro mais barato de evitar e o mais
caro de cometer.

**Truque de gravação:** faça o deploy com `epochDuration = 600` (dez minutos) e
comece a gravar **logo depois**. Os blocos de contexto — problema, tipo do token,
parâmetros, código — consomem os primeiros minutos enquanto a época corre
sozinha. Quando chegar no bloco do prêmio, ela já virou. O tempo trabalha a seu
favor em vez de contra.

Antes de gravar: executar [`docs/deploy.md §3`](docs/deploy.md) inteiro uma vez
num deploy de ensaio, e no deploy definitivo deixar **três ou quatro apostas já
registradas** para o pote não estar vazio.

Abas prontas: Remix · MetaMask (contas A e B) · Etherscan no contrato ·
`ranking/index.html`.

---

## Blocos

### 0:00 – 0:30 · Abertura

> "Hugo Montan, AD07, Questão de Computação 1. Vou apresentar o INTELIBET, uma
> stablecoin para pagar aposta entre pessoas do Inteli, com um prêmio mensal
> para quem mais ganha — tudo rodando na Sepolia."

### 0:30 – 1:40 · Problema

- Aposta entre amigos falha no **depois**: pagamento no fiado, sem registro, sem
  histórico — e honrar aposta não traz vantagem nenhuma sobre não honrar.
- O argumento que carrega a entrega inteira:

> "O caminho óbvio seria um contrato que obrigasse a pagar. Só que ele não
> existe: pelo artigo 814 do Código Civil, dívida de aposta é obrigação natural
> — não pode ser cobrada em juízo. Não há execução forçada nem em tese. Então ou
> eu travo o dinheiro antes, com custódia e árbitro, ou eu troco a garantia
> jurídica por garantia reputacional. Escolhi a segunda."

> "O contrato não garante o pagamento. Ele garante que todo mundo saiba quem
> pagou — e paga um prêmio para quem mais ganha."

### 1:40 – 2:30 · Por que stablecoin

> "A aposta é feita hoje e paga depois. Se o token oscilasse 20% no intervalo,
> quem *ganhou* receberia menos poder de compra do que arriscou. E o pote do
> prêmio acumula por trinta dias — valor que fica parado nesse tempo precisa ser
> estável, senão o prêmio vira loteria de mercado."

Descartar os outros dois em uma frase cada: não é utility (não libera produto nem
serviço — o token **é** o valor em disputa), não é governance (nada é votado).

### 2:30 – 3:20 · Parâmetros e a invariante

| | |
|---|---|
| Paridade | 1 IBET = R$ 1,00 |
| Decimals | **2** — pareia com o centavo |
| Supply | **sem teto fixo** |
| Lastro | reserva atestada on-chain |

> "A pergunta que qualquer um faz é: o que impede a tesouraria de emitir o dobro
> amanhã? A resposta está aqui — `totalSupply` nunca pode passar de
> `reservesAttested`, e esse é o único caminho de emissão do contrato."

> "E repare que não tem teto fixo de supply. Num token de governança o teto seria
> a garantia central. Numa stablecoin seria defeito: o supply precisa subir
> quando entra dinheiro na reserva e cair no resgate. O teto aqui é a reserva."

### 3:20 – 4:10 · A taxa, e as duas decisões por trás dela

Tela: o código do `settleBet`.

> "Cada aposta paga deixa 5% num pote. Duas coisas importam aqui."

**Primeira — a taxa não incide sobre `transfer`:**

> "Um ERC-20 que entrega menos do que foi mandado quebra carteira, exchange e
> qualquer contrato que faça conta antes de transferir. Então aposta paga tem
> rake; mandar dinheiro para um amigo não paga nada."

**Segunda — o ranking do prêmio é por bruto, não por líquido:**

> "Se o critério fosse saldo líquido, o número desceria quando alguém perde, e
> achar o novo líder exigiria varrer todos os participantes dentro de uma
> transação — não cabe no gás de um bloco. Bruto só sobe, então manter o líder é
> uma comparação de uma linha. A restrição técnica acabou dando uma métrica
> melhor: 'quem mais ganhou apostas neste mês'."

### 4:10 – 5:10 · O lastro funcionando (núcleo 1)

| Tempo | Ação | Fala |
|---|---|---|
| 4:15 | `mint(A, 30000)` | "contrato recém-publicado, ainda sem reserva" → **reverte `StaleAttestation`** |
| 4:35 | `attestReserves(50000, hash)` | "R$ 500 de reserva, com o hash do comprovante" |
| 4:50 | `mint(A, 30000)` | sucesso — 300,00 IBET |
| 5:00 | `collateralizationBps()` | `16666` → "166%, público" |
| 5:05 | `mint(A, 30000)` de novo | **reverte `ReserveInsufficient(60000, 50000)`** |

Se o vídeo tiver que encolher, estas duas reversões são as últimas a sair.

### 5:10 – 5:50 · Transferência entre carteiras (item exigido)

| Tempo | Ação | Fala |
|---|---|---|
| 5:15 | `transfer(B, 10000)` a partir de A | — |
| 5:30 | `balanceOf(B)` | **`10000` exatos** → "chegou o valor inteiro: a taxa não incide em transferência comum" |
| 5:40 | MetaMask da Conta B + Etherscan | 100,00 IBET na carteira, `Transfer` público |

Mostrar o número exato é o que prova a afirmação do bloco anterior.

### 5:50 – 6:50 · Pagando uma aposta (núcleo 2)

| Tempo | Ação | Fala |
|---|---|---|
| 5:55 | `settleBet(A, 2000, "Inteli vence o interclasses")` pela Conta **B** | "a B perdeu, então a B paga" |
| 6:10 | `balanceOf(A)` e `balanceOf(<contrato>)` | "1900 para a A, 100 para o pote — os 5%" |
| 6:25 | Etherscan → **Logs** | "dois `Transfer` e o `BetSettled`, que carrega o valor, a taxa e a época" |
| 6:40 | `settleBet(B, 1000, "…")` pela B | **reverte `InvalidCounterparty`** |

### 6:50 – 7:40 · O prêmio (núcleo 3)

| Tempo | Ação | Fala |
|---|---|---|
| 6:55 | `prizePool(0)` e `epochLeader(0)` | "o pote da época e quem está liderando" |
| 7:05 | `claimPrize(0)` | **reverte `EpochNotFinished`** — "a época ainda não acabou" |
| 7:15 | `currentEpoch()` | agora `1` — "virou enquanto eu falava" |
| 7:25 | `claimPrize(0)` | **`PrizeClaimed`** — o líder recebe o pote inteiro |
| 7:35 | `balanceOf(líder)` | subiu no valor do pote |

Se a época ainda não virou quando você chegar aqui, estenda o bloco anterior
mostrando mais uma aposta. Não corte para editar depois — a demonstração vale
mais contínua.

### 7:40 – 8:20 · O ranking (o fecho)

Tela: `ranking/index.html`, recarregar ao vivo.

> "Isso é um arquivo HTML. Sem banco de dados, sem servidor, sem chave de API.
> Ele lê do contrato o que é autoritativo — época, pote, líder — e dos eventos o
> histórico de apostas."

Apontar: pote, líder, tempo restante, coluna de adversários distintos.

> "E se essa página sair do ar, o histórico continua na blockchain e qualquer um
> monta outra igual. Numa plataforma de apostas tradicional, o servidor cair
> significa o saldo sumir junto."

### 8:20 – 8:55 · Limites

Rápido, sem pedir desculpa:

- **não há garantia de pagamento** — é o desenho, não um bug;
- **auto-aposta pode farmar o prêmio**: `settleBet` é auto-declaratório, então
  duas carteiras minhas conseguem fabricar vitórias. A mitigação é exigir N
  adversários distintos — encarece e expõe, mas não elimina. Fechar de vez
  exigiria contra-assinatura das duas partes;
- a atestação de reserva depende de auditoria externa;
- o owner deveria ser multisig.

Falar do ataque **antes** de perguntarem vale mais que responder depois.

### 8:55 · Fecho

> "Repositório com a modelagem, o contrato e o ranking no link da entrega.
> Obrigado."

---

## Checklist de gravação

- [ ] Deploy feito com `epochDuration = 600` e `minDistinctOpponents = 1`
- [ ] Gravação começada logo após o deploy, para a época virar durante o vídeo
- [ ] Três ou quatro apostas já registradas (pote e ranking não podem estar vazios)
- [ ] `CONTRATO` e `BLOCO_INICIAL` preenchidos no `ranking/index.html`, página testada
- [ ] Apelidos configurados — "Hugo" e "Ana" leem melhor que `0x5f2a…`
- [ ] Token importado na MetaMask das contas A e B **antes** de gravar
- [ ] Valores anotados à mão: `50000`, `30000`, `10000`, `2000`
- [ ] Notificações do sistema silenciadas
- [ ] Endereço do contrato à vista em algum momento
- [ ] Áudio testado com 20 segundos antes da tomada real
- [ ] **Seed phrase nunca na tela** — nem por um frame
- [ ] Duração final ≤ 10:00
- [ ] Link do vídeo testado em janela anônima
