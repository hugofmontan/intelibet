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
| Escolha da ideia e dos papéis da mesa | eu |
| **Corte de escopo** — decidir o que não construir | eu |
| Levantamento de trade-offs antes de cada decisão | IA, provocada por perguntas minhas |
| Redação dos contratos e do painel | IA, a partir da modelagem fechada |
| Revisão linha a linha, aceitação e correção | eu |
| Deploy, testes na Sepolia e vídeo | eu |

A ordem importa: **a modelagem veio antes do código**, e o prompt de geração
recebeu a modelagem pronta como especificação.

---

## 2. O projeto mudou de forma quatro vezes

Esse é o registro mais honesto que posso dar do processo. As versões
intermediárias existiram, funcionaram e foram descartadas:

| Versão | O que era | Por que caiu |
|---|---|---|
| 1 | Governance token de assembleia estudantil | Troquei de ideia: queria algo que eu fosse usar de verdade. |
| 2 | Stablecoin com reserva atestada + escrow com árbitro | O escrow era complexidade desproporcional para aposta de R$ 20 entre colegas. |
| 3 | Stablecoin + `settleBet` auto-declaratório + prêmio mensal de 5% | O prêmio era **farmável**: duas carteiras minhas fabricariam vitórias por 5% de custo. Mitiguei exigindo adversários distintos, mas a mitigação encarecia sem eliminar. |
| **4** | **Dois tokens, mesa de dois com juiz e custódia** | Com jogadores fixos e um juiz que nunca é parte, a auto-aposta **deixa de existir** — não é mitigada, é impossível. |

A pergunta que fechou o desenho foi perceber que a versão 3 declarava reserva
bancária numa rede de teste: eu estava atestando uma reserva que não existe. O
lastro em **obrigação reconhecida** é menos ambicioso e verdadeiro.

---

## 3. Prompts principais

**Prompt 1 — o enquadramento, antes de qualquer código**

> No Brasil, o que torna difícil cobrar uma aposta informal entre duas pessoas?
> É fundamento jurídico ou só questão social?

Daqui veio o **art. 814 do Código Civil**. Isso reposicionou o projeto inteiro:
se não existe execução forçada nem em tese, o objetivo deixa de ser cobrança e
passa a ser *registro que o devedor não consegue manipular*. Virou o argumento de
abertura do vídeo.

**Prompt 2 — antes de aceitar a ideia do prêmio**

> Quero que cada aposta deixe 5% num pote e o maior ganhador do mês leve. Antes
> de implementar: quais problemas isso cria?

Três respostas que desmontaram a versão literal: taxa em toda transferência
quebra o ERC-20; ranking por saldo líquido não é mantível on-chain (líquido
desce, e achar o novo líder exigiria varrer todos os participantes); e o prêmio é
farmável. Perguntar "quais problemas isso cria?" **antes** de pedir código rendeu
mais que qualquer revisão depois.

**Prompt 3 — a arquitetura dos dois tokens**

> Ficha fictícia para apostar e um segundo token que representa o que precisa ser
> pago de verdade. Como modelar isso sem que os dois acumulem saldo e ninguém
> saiba quem deve a quem?

Daqui saiu a **compensação**: abater a dívida contrária antes de emitir, e a
invariante de que no máximo um dos dois tem saldo.

**Prompt 4 — geração**

> Gere dois contratos ERC-20 em Solidity ^0.8.20 com OpenZeppelin v5, num
> arquivo: a ficha com custódia de apostas, papéis fixos (dois jogadores e um
> juiz), acordo mútuo dispensando o juiz, e época de mês de calendário; e o
> crédito não transferível, emitido só pelo contrato da ficha. Custom errors.

**Prompt 5 — revisão adversarial**

> Procure: caminhos em que ficha fique presa no contrato; formas de criar crédito
> sem aposta; e se o devedor consegue reduzir a própria dívida.

Achados que mudaram o código:

1. **`refundExpired` precisa ser pública.** Na primeira versão só o juiz podia
   acionar — o que reintroduzia exatamente a dependência que a função existe para
   eliminar: juiz sumido prenderia o dinheiro dos dois para sempre.
2. **O crédito precisa nascer dentro do contrato da ficha**, não ser publicado
   separado e autorizado depois. `new InteliCredit(address(this))` no construtor
   elimina a janela em que o token existiria sem controlador correto.
3. **`confirmPayment` só pelo credor.** A versão inicial deixava qualquer um dos
   dois chamar, o que permitiria ao devedor apagar a própria dívida.

---

## 4. O que foi rejeitado

| Sugestão | Por que recusei |
|---|---|
| `decimals = 18` por padrão | O crédito pareia com o centavo do real; 18 casas criariam saldos impossíveis de pagar. |
| Taxa incidindo em `transfer` | Quebra o ERC-20: token que entrega menos do que foi mandado quebra carteira, exchange e qualquer contrato que faça conta antes de transferir. |
| Manter o prêmio mensal de 5% | Numa mesa de dois, o pote é dinheiro andando em círculo — e obrigaria a explicar por que existe rake com dois jogadores. |
| Crédito transferível | Deixaria de ser registro de obrigação e viraria dinheiro. A restrição é o que define o token. |
| Escrow embutido com árbitro escolhido por aposta | Complexidade desproporcional. Com papéis fixos, o mesmo resultado sai muito mais simples. |
| Owner podendo ajustar dívida "em caso de erro" | Destruiria a única garantia forte do sistema. |
| Reserva atestada para a ficha | Atestar reserva inexistente em rede de teste é teatro. A ficha assume ser fictícia. |

---

## 5. Verificação independente

Nada foi aceito por confiança na saída do modelo. Antes do deploy:

- leitura linha a linha contra a documentação da OpenZeppelin v5, em particular
  `_update` como ponto único de movimentação e o construtor do `Ownable`, que
  mudou da v4 para a v5;
- **a aritmética de calendário foi portada para Python e comparada com
  `datetime` dia a dia de 2024 a 2031**, mais bordas de bissexto e virada de
  século: zero divergências. Era o trecho com maior risco de erro silencioso —
  um bug ali daria mês errado sem reverter nada;
- execução da matriz de cenários de
  [`implementacao.md §12`](implementacao.md#12-matriz-de-verificação-antes-do-deploy)
  na Sepolia, incluindo os casos que **devem** reverter.

Um contrato testado só no caminho feliz não está testado.
