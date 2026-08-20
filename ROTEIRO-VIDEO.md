# Roteiro do vídeo — máx. 10 minutos

**Alvo real: 9:00.**

Antes de gravar: rodar [`docs/deploy.md §3`](docs/deploy.md) inteiro num deploy
de ensaio. No deploy definitivo, deixe **a primeira aposta já resolvida** — a
gravação começa com a mesa tendo história, e você demonstra ao vivo a segunda,
que é a que mostra a compensação.

Abas prontas: Remix (com as três contas na MetaMask) · Etherscan no contrato ·
o painel publicado.

---

### 0:00 – 0:30 · Abertura

> "Hugo Montan, AD07, Questão de Computação 1. Vou apresentar o INTELIBET: uma
> mesa de apostas entre dois amigos com um juiz, e **dois tokens** — uma ficha
> para apostar e um crédito que diz quanto precisa ser pago de verdade."

### 0:30 – 1:30 · O problema, e o argumento que ninguém espera

- Aposta entre amigos falha no depois: fiado, termos verbais, sem placar.
- E aí o gancho:

> "O caminho óbvio seria um contrato que obrigue a pagar. Só que ele não existe:
> pelo artigo 814 do Código Civil, dívida de aposta é obrigação natural — não
> pode ser cobrada em juízo. Não há execução forçada nem em tese."

> "Então o que dá para construir não é cobrança. É uma conta única, pública, com
> os termos congelados antes do resultado, e que **quem deve não consegue
> manipular**."

### 1:30 – 2:45 · Por que dois tokens

O bloco que carrega a nota. Tela: a seção do painel com os dois cartões.

> "Uma aposta tem duas coisas dentro dela que não são a mesma: a brincadeira e a
> dívida. Um token só me obriga a escolher — ou ele é fictício e a dívida não
> significa nada, ou ele vale dinheiro e cada aposta boba vira transação
> financeira."

| | Ficha `IBET` | Crédito `IBRL` |
|---|---|---|
| Tipo | utility | stablecoin de obrigação |
| Transferível | sim | **não** |
| Nasce | tesouraria emite | só de aposta resolvida |

> "A ficha é **utility**: dá acesso ao mecanismo e não promete valor nenhum. E é
> justamente por ser fictícia que ela pode circular livre."

> "O crédito é **stablecoin**, mas o lastro não é reserva bancária — é a
> obrigação reconhecida do perdedor. Um recebível tokenizado. E a pergunta que
> se faz a qualquer stablecoin continua respondida: o que impede alguém de criar
> dívida do nada? Crédito só é emitido dentro da liquidação de uma aposta, e o
> único endereço autorizado a emitir é o contrato da mesa."

Se sobrar fôlego, a frase que mostra maturidade:

> "Uma versão anterior deste projeto atestava reserva bancária. Numa rede de
> teste, aquilo era atestar uma reserva que não existe. Lastrear em obrigação é
> menos ambicioso e verdadeiro."

### 2:45 – 3:45 · Tour no código

Quatro pontos, apontando — sem ler linha a linha:

1. **`new InteliCredit(address(this))` no construtor** — "um deploy publica os
   dois, e o crédito nunca existe sem controlador definido";
2. **`_update` do crédito** — "mint e burn passam, transferência reverte. É isso
   que separa registro de obrigação de dinheiro";
3. **o construtor recusando juiz igual a jogador** — "garantido por construção,
   não por uma verificação por aposta que eu possa esquecer";
4. **`_netCredit`** — "abate antes de emitir".

### 3:45 – 5:00 · A mesa funcionando (núcleo 1)

| Tempo | Ação | Fala |
|---|---|---|
| 3:50 | `mintChips` para o Rodrigo | **reverte `NotAPlayer`** — "ficha fora da mesa não existe" |
| 4:05 | `createBet(8000, "…", 0)` pelo Leon | "os 80 dele saem da carteira e ficam no contrato" |
| 4:25 | `balanceOf(<contrato>)` | mostra a custódia |
| 4:40 | `acceptBet(1)` pelo Hugo | "agora são 160 travados — a aposta existe" |

> "Trava antes porque, sem isso, a sentença do juiz não valeria nada: ele
> declararia o vencedor e o perdedor simplesmente não pagaria."

### 5:00 – 6:15 · A liquidação e a compensação (núcleo 2)

| Tempo | Ação | Fala |
|---|---|---|
| 5:05 | `netPosition()` **antes** | "Hugo deve R$ 50 ao Leon, da aposta anterior" |
| 5:20 | `agreeOn(1, <Hugo>)` pelo Hugo | "registro meu voto — nada acontece ainda" |
| 5:35 | `agreeOn(1, <Hugo>)` pelo Leon | "os dois concordaram: liquida sem o juiz" |
| 5:55 | `netPosition()` **depois** | **`(Hugo, Leon, 3000)`** |

Este é o momento mais forte do vídeo. Diga em voz alta o que aconteceu:

> "Eu devia 50 e ganhei 80. Repare que eu **não** passei a ter 80 a receber com
> uma dívida de 50 pendurada. A vitória abateu a dívida antiga e sobrou 30. Isso
> é compensação de posições — o mesmo princípio de uma câmara de liquidação — e
> é o que garante que no máximo **um** dos dois tenha saldo em qualquer momento.
> O saldo *é* a resposta para quem deve quanto a quem."

### 6:15 – 6:50 · O crédito não circula

| Tempo | Ação |
|---|---|
| 6:20 | No contrato do crédito: `transfer(...)` → **reverte `NonTransferable`** |
| 6:35 | `mint(...)` chamado por você → **reverte `OnlyController`** |

> "Dívida entre duas pessoas específicas não circula. E nem eu, que sou o dono da
> tesouraria, consigo criar crédito por fora."

### 6:50 – 7:30 · Quitar

| Tempo | Ação |
|---|---|
| 6:55 | `confirmPayment(3000)` pelo **Leon** → **reverte** |
| 7:10 | `confirmPayment(3000)` pelo **Hugo** → crédito queimado, `netPosition` zera |

> "Quem deve não apaga a própria dívida. Só quem recebeu o Pix pode declarar que
> recebeu — se fosse diferente, o registro não valeria nada."

### 7:30 – 8:20 · O painel

Tela: o site publicado, recarregando ao vivo.

> "Um arquivo HTML. Sem banco de dados, sem servidor, sem chave de API. Ele lê o
> contrato e mostra a posição líquida, o placar do mês e cada aposta com seu
> estado."

Apontar: o destaque de quem deve a quem, o histórico de apostas, o diagrama da
máquina de estados.

> "E se essa página sair do ar, o estado continua na blockchain e qualquer um
> monta outra igual."

### 8:20 – 8:55 · Limites

Rápido, sem pedir desculpa:

- **o juiz é ponto de confiança** — se decidir errado, o contrato paga assim
  mesmo; o acordo mútuo reduz a exposição, não elimina;
- **a mesa é de dois** — a compensação depende disso; abrir para mais gente é
  netting multilateral, outro problema;
- **o acerto acontece fora da rede** — o contrato registra a dívida, não move
  dinheiro real;
- **`confirmPayment` depende da honestidade do credor.**

Falar disso antes de perguntarem vale mais que responder depois.

### 8:55 · Fecho

> "Repositório com a modelagem, o contrato e o painel no link da entrega.
> Obrigado."

---

## Checklist de gravação

- [ ] Deploy feito com `epochDuration = 0` e limiar de `10000`
- [ ] Fichas emitidas para Hugo e Leon, nomes registrados pelos três
- [ ] **Primeira aposta já resolvida** antes de gravar (para haver dívida a compensar)
- [ ] `CONTRATO` preenchido no `index.html` e página testada
- [ ] Contrato do crédito carregado no Remix via *At Address*, pronto para a demonstração de reversão
- [ ] Tokens importados na MetaMask
- [ ] Valores anotados: `100000`, `5000`, `8000`, `3000`
- [ ] Notificações silenciadas
- [ ] Áudio testado com 20 segundos antes da tomada real
- [ ] **Seed phrase nunca na tela** — nem por um frame
- [ ] Duração final ≤ 10:00
- [ ] Link do vídeo testado em janela anônima
