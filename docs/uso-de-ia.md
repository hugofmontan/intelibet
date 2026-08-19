# Uso de IA generativa

O enunciado determina o uso de IA generativa para auxiliar na geração do código
do contrato. Este documento registra **como** foi usada, o que foi aceito e o que
foi rejeitado — a decisão de projeto continua sendo humana, e o registro é o que
prova isso.

Ferramenta: **Claude (Anthropic)**, via Claude Code.

---

## 1. Divisão de trabalho

| Etapa | Quem fez |
|---|---|
| Escolha da ideia (aposta entre pares) e do tipo de token | eu |
| Definição dos parâmetros e do mecanismo de lastro | eu, com a IA levantando trade-offs |
| **Corte de escopo** — decidir o que não construir | eu |
| Redação do contrato e da página de ranking | IA, a partir da modelagem fechada |
| Revisão linha a linha, aceitação e correção | eu |
| Deploy, testes na Sepolia e vídeo | eu |

A ordem importa: **a modelagem veio antes do código**. O prompt de geração
recebeu a modelagem pronta como especificação, em vez de pedir "faça uma
stablecoin" e depois inventar uma justificativa para o que saísse.

---

## 2. Prompts principais

**Prompt 1 — o mecanismo, antes de qualquer código**

> Quero uma stablecoin usada para pagar apostas entre colegas de faculdade.
> Antes de código: o que num contrato ERC-20 impede o emissor de emitir mais do
> que tem em reserva? Aponte também o que **não** fica garantido.

Daqui saiu a invariante `totalSupply <= reservesAttested` como coração do
contrato, a distinção entre *atestação* (promessa auditável) e *prova* (que não
existe on-chain para reserva fiduciária), e a validade de 30 dias da atestação.

**Prompt 2 — o enquadramento do problema**

> No Brasil, o que torna difícil cobrar uma aposta informal entre duas pessoas?
> É fundamento jurídico ou só questão social?

Daqui veio o **art. 814 do Código Civil** — dívida de jogo ou aposta é obrigação
natural e não é exigível em juízo. Isso reposicionou a modelagem inteira e virou
o argumento de abertura do vídeo.

**Prompt 3 — geração do contrato**

> Gere um ERC-20 em Solidity ^0.8.20 com OpenZeppelin v5: "InteliBet"/IBET,
> decimals 2, sem teto fixo de supply, prova de reserva (valor + hash +
> timestamp) com validade, mint restrito ao owner e validado contra a reserva,
> redeem que queima e registra o pedido, e uma função `settleBet` que transfere
> e emite um evento marcando a transferência como pagamento de aposta. Custom
> errors, superfície ERC-20 intacta.

**Prompt 4 — revisão adversarial**

> Revise procurando: caminhos para registrar uma derrota na conta de outra
> pessoa; e se o ranking consegue distinguir aposta paga de transferência
> comum.

Dois achados que mudaram o resultado:

1. **`settleBet` precisa debitar `msg.sender`.** Uma versão com parâmetro
   `loser` explícito permitiria plantar derrota na conta alheia. Com
   `_transfer(msg.sender, ...)`, quem paga é necessariamente quem chama.
2. **Descrição obrigatória e limitada.** Sem limite superior o evento vira
   depósito de lixo e a página fica ilegível; sem limite inferior, alguém
   registra aposta sem dizer sobre o quê. Ficou `0 < len <= 200`.

**Prompt 5 — o mecanismo de premio**

> Quero que cada aposta paga deixe 5% num pote e que o maior ganhador do mes
> leve o pote. Antes de implementar: quais problemas isso cria?

Foi o prompt mais util de todos, porque a resposta desmontou a versao literal da
ideia em tres pontos:

1. **Taxa em toda transferencia quebra o token.** Um ERC-20 *fee on transfer*
   entrega menos do que foi mandado e quebra carteira, exchange e qualquer
   contrato que faca conta antes de transferir. Movi a taxa para dentro do
   `settleBet` — aposta paga tem rake, transferencia comum nao.
2. **Ranking por saldo liquido nao e mantivel on-chain.** Liquido desce quando
   alguem perde, e achar o novo lider exigiria varrer todos os participantes
   dentro de uma transacao. Troquei para ganho bruto, que so sobe: manter o
   lider virou uma comparacao de uma linha.
3. **O premio e farmavel.** Como `settleBet` e auto-declaratorio, duas carteiras
   minhas fabricam vitorias por 5% de custo. Implementei a mitigacao de
   adversarios distintos e registrei que ela encarece sem eliminar.

Nenhum dos tres apareceu na ideia original. Perguntar "quais problemas isso
cria?" **antes** de pedir codigo rendeu mais que qualquer revisao posterior.

---

## 3. O que foi rejeitado

### O corte grande: custódia e árbitro

Uma versão anterior deste projeto tinha um segundo contrato, `BetEscrow`, com
custódia prévia das duas entradas, árbitro neutro obrigatório, prazo, reembolso
automático e máquina de estados de cinco status. Funcionava, e a IA a produziu
inteira.

**Cortei.** Três motivos, nesta ordem:

1. **Complexidade desproporcional.** ~200 linhas, dois contratos, três contas com
   gás, dezessete passos de deploy — para uma aposta de R$ 20 entre colegas.
2. **A garantia que ela oferecia era menor do que parecia.** Custódia resolve o
   calote, mas cria dependência de um árbitro humano, que é um novo ponto de
   confiança e um novo jeito de o sistema falhar.
3. **O art. 814 já dizia que garantia jurídica não existiria.** Assumir isso e
   trocar por garantia reputacional é mais honesto do que simular uma execução
   que a lei não reconhece.

O que sobrou no lugar: `settleBet` e um ranking público. Dez linhas de contrato e
um arquivo HTML. **A decisão de não construir foi a decisão de projeto mais
importante desta entrega**, e ela é minha, não do modelo — a IA produz o que se
pede, e o que se pede a mais ela não recusa.

### Os cortes menores

| Sugestão | Por que recusei |
|---|---|
| `decimals = 18` por padrão | Uma stablecoin de real precisa parear com o centavo. 18 casas criariam saldos impossíveis de pagar no resgate. |
| Teto fixo de supply (`MAX_SUPPLY`) | Faz sentido em token de governança, é defeito em stablecoin: o supply precisa acompanhar a reserva nas duas direções. |
| `attestReserves` validando `amount >= totalSupply()` | Impediria registrar subcolateralização. Se a reserva cai abaixo do supply, isso tem que ser **visível**, não impossível de declarar. |
| `ERC20Pausable` + lista de contas congeladas | Compliance de stablecoin operada comercialmente. Aqui só aumentaria a superfície do contrato sem servir ao problema. |
| Ranking com backend e banco de dados | Mataria o argumento central: a página não pode ter poder nenhum. Ficou HTML estático lendo eventos. |
| Percentual para a tesouraria em cada aposta | Transformaria o projeto em casa de apostas, que é exatamente o que a modelagem recusa ser. |
| Taxa incidindo em `transfer` (a ideia literal) | Quebra o ERC-20. Ficou só no `settleBet`. |
| Ranking do prêmio por saldo líquido | Não é mantível on-chain sem varrer todos os participantes. Ficou ganho bruto. |
| Pote queimado quando ninguém é elegível | Desincentiva participar justamente nos meses fracos. Ficou rolagem para a época seguinte. |
| `epochDuration` como constante de 30 dias | Impediria demonstrar o prêmio num vídeo de 10 minutos. Virou parâmetro de deploy. |
| Owner podendo sacar o pote "em caso de problema" | Destruiria a única garantia forte do mecanismo. Não existe essa função. |

---

## 4. Verificação independente

Nada foi aceito por confiança na saída do modelo. Antes do deploy:

- leitura linha a linha contra a documentação da OpenZeppelin v5, em particular
  a substituição de `_beforeTokenTransfer` por `_update` e o construtor do
  `Ownable`, que mudou da v4 para a v5;
- conferência de cada parâmetro contra a tabela de modelagem;
- execução da matriz de cenários de
  [`implementacao.md §7`](implementacao.md#7-matriz-de-verificação-antes-do-deploy)
  na Sepolia, incluindo os casos que **devem reverter**.

Um contrato testado só no caminho feliz não está testado.
