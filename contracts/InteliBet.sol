// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title  InteliCredit (IBRL) — o registro de divida
 * @notice 1 IBRL = R$ 1,00 a receber. NAO e dinheiro: e a anotacao de quanto
 *         uma pessoa tem a receber da outra, em reais, na vida real.
 *
 * @dev    Duas regras definem este token, e as duas sao restricoes:
 *
 *         1. NAO E TRANSFERIVEL. Divida entre duas pessoas especificas nao
 *            circula. Bloquear a transferencia e o que separa "registro de
 *            obrigacao" de "dinheiro". As funcoes ERC-20 continuam existindo
 *            com a assinatura padrao — o padrao define interface, nao obriga
 *            que toda transferencia seja aceita — entao carteiras e
 *            exploradores continuam reconhecendo o token e mostrando saldo.
 *
 *         2. SO O CONTROLLER EMITE E QUEIMA. O controller e o InteliBet, que
 *            cria este contrato no proprio construtor. Nem os jogadores nem o
 *            juiz nem o dono conseguem criar divida por fora.
 *
 *         Consequencia: credito so nasce de aposta resolvida, e so morre por
 *         confirmacao de quem tinha a receber. O devedor nao tem caminho
 *         nenhum para reduzir a propria divida.
 */
contract InteliCredit is ERC20 {
    /// @notice Contrato que criou este token e o unico que emite e queima.
    address public immutable controller;

    error OnlyController(address caller);
    error NonTransferable();

    modifier onlyController() {
        if (msg.sender != controller) revert OnlyController(msg.sender);
        _;
    }

    constructor(address controller_) ERC20("InteliBet Credit", "IBRL") {
        controller = controller_;
    }

    function decimals() public pure override returns (uint8) {
        return 2;
    }

    function mint(address to, uint256 amount) external onlyController {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyController {
        _burn(from, amount);
    }

    /// @dev Mint (from == 0) e burn (to == 0) passam; transferencia, nao.
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) revert NonTransferable();

        super._update(from, to, value);
    }
}

/**
 * @title  INTELIBET (IBET) — a ficha e a mesa de apostas
 * @notice Mesa de tres papeis fixos, gravados no deploy: dois jogadores e um
 *         juiz. Duas camadas de valor, propositalmente separadas:
 *
 *         FICHA (IBET, este contrato) — moeda ficticia da mesa. A tesouraria
 *         emite a vontade para os dois jogadores. Nao promete valer nada, e
 *         justamente por isso pode circular livremente: e o que torna a aposta
 *         visivel on-chain sem mover dinheiro de verdade.
 *
 *         CREDITO (IBRL, contrato irmao) — o que precisa ser pago na vida
 *         real. Nasce so de aposta resolvida, no valor exato apostado.
 *
 * @dev    O que sustenta o desenho:
 *
 *         1. CUSTODIA. As duas entradas em ficha ficam no contrato desde a
 *            criacao da aposta. Sem isso a sentenca do juiz nao valeria nada:
 *            ele declararia o vencedor e o perdedor simplesmente nao pagaria.
 *
 *            Como so existem dois jogadores e um juiz que nunca e parte, NAO
 *            EXISTE auto-aposta — ninguem fabrica vitoria contra si mesmo.
 *
 *         2. O JUIZ decide QUEM ganhou, nunca QUANTO. Nao altera valor, nao
 *            paga terceiro, nao retem nada. E se os dois jogadores
 *            concordarem, `agreeOn` liquida sem ele: o juiz e desempate, nao
 *            pedagio.
 *
 *         3. COMPENSACAO. Vitoria abate a divida contraria antes de criar
 *            divida nova. Consequencia: no maximo UM dos dois tem saldo de
 *            credito em qualquer momento, e esse saldo E a resposta para
 *            "quem deve quanto a quem", sem ninguem precisar calcular.
 *
 *         4. A DIVIDA SO MORRE POR CONFIRMACAO DE QUEM RECEBE. O devedor nao
 *            tem funcao nenhuma que reduza o que ele deve.
 *
 *         Nao ha taxa e nao ha banca: o contrato nao retem nada, em nenhuma
 *         das duas camadas. Toda situacao terminal devolve ficha para alguem
 *         — nao existe estado em que IBET fique preso aqui.
 *
 *         Ver docs/modelagem.md.
 */
contract InteliBet is ERC20, Ownable {
    // --- Parametros ------------------------------------------------------

    /// @dev 2 casas: a ficha pareia com o centavo, igual ao credito.
    uint8 private constant DECIMALS = 2;

    /// @notice Prazo usado quando a aposta e criada com `deadline = 0`.
    uint64 public constant DEFAULT_DEADLINE = 7 days;

    uint256 public constant MAX_TERMS_LENGTH = 200;
    uint256 public constant MAX_NAME_LENGTH = 24;

    // --- Papeis e token irmao, fixos no deploy ---------------------------

    address public immutable playerA;
    address public immutable playerB;
    address public immutable judge;

    /// @notice Token de credito, criado por este contrato no construtor.
    InteliCredit public immutable credit;

    /// @notice Divida liquida a partir da qual o contrato pede acerto real.
    uint256 public immutable settlementThreshold;

    // --- Epocas ----------------------------------------------------------

    /// @notice Duracao de uma epoca, em segundos. ZERO = mes de calendario.
    uint64 public immutable epochDuration;

    /// @notice True quando a epoca acompanha o mes de calendario.
    bool public immutable calendarMonths;

    /// @notice Momento do deploy. Marco zero da contagem de epocas.
    uint64 public immutable startTime;

    uint256 private immutable _startMonthIndex;

    // --- Apostas ---------------------------------------------------------

    enum Status {
        Open, // proposta feita, aguardando o outro jogador
        Active, // as duas entradas em custodia
        Resolved, // decidida, vencedor pago
        Cancelled, // proposta retirada antes do aceite
        Refunded // prazo vencido sem decisao, entradas devolvidas
    }

    struct Bet {
        address proposer;
        uint128 stake; // valor de CADA lado, em unidades base
        uint64 deadline;
        Status status;
        address winner; // zero ate ser resolvida
        uint64 resolvedEpoch;
        bool byAgreement; // true quando os jogadores dispensaram o juiz
        string terms;
    }

    Bet[] private _bets;

    /// @notice Voto de cada jogador numa aposta, para o acordo mutuo.
    mapping(uint256 => mapping(address => address)) public agreementVote;

    // --- Placar ----------------------------------------------------------

    /// @notice Valor ganho por epoca e por jogador. Base do ranking mensal.
    mapping(uint256 => mapping(address => uint256)) public grossWon;

    /// @notice Apostas resolvidas por epoca.
    mapping(uint256 => uint256) public betsResolved;

    // --- Identidade ------------------------------------------------------

    mapping(address => string) private _names;

    // --- Eventos ---------------------------------------------------------

    event ChipsMinted(address indexed to, uint256 amount);
    event NameSet(address indexed account, string name);

    event BetCreated(uint256 indexed id, address indexed proposer, uint128 stake, uint64 deadline, string terms);
    event BetAccepted(uint256 indexed id, address indexed opponent);
    event AgreementVoted(uint256 indexed id, address indexed voter, address winner);
    event BetResolved(
        uint256 indexed id, address indexed winner, address indexed loser, uint256 stake, uint256 epoch, bool byAgreement
    );
    event BetCancelled(uint256 indexed id);
    event BetRefunded(uint256 indexed id);

    event CreditNetted(address indexed winner, address indexed loser, uint256 offset, uint256 minted);
    event SettlementDue(address indexed creditor, address indexed debtor, uint256 amount);
    event PaymentConfirmed(address indexed creditor, address indexed debtor, uint256 amount);

    // --- Erros -----------------------------------------------------------

    error NotAPlayer(address caller);
    error NotTheJudge(address caller);
    error NotAuthorized(address caller);
    error WrongStatus(Status current, Status expected);
    error DeadlinePassed(uint64 deadline);
    error DeadlineNotReached(uint64 deadline);
    error InvalidDeadline();
    error WinnerNotInBet(address winner);
    error InvalidText(uint256 length, uint256 max);
    error DuplicateRole();
    error ZeroAddress();
    error ZeroAmount();

    // --- Modificadores ---------------------------------------------------

    modifier onlyPlayer() {
        if (msg.sender != playerA && msg.sender != playerB) revert NotAPlayer(msg.sender);
        _;
    }

    // --- Construtor ------------------------------------------------------

    /**
     * @param treasury_             Emite as fichas. Vira owner.
     * @param playerA_              Primeiro jogador da mesa.
     * @param playerB_              Segundo jogador da mesa.
     * @param judge_                Quem decide o vencedor. Nunca e jogador.
     * @param settlementThreshold_  Divida liquida que dispara o pedido de acerto.
     * @param epochDuration_        Segundos por epoca, ou 0 para mes de calendario.
     *
     * @dev O token de credito nasce aqui dentro, com `new`, ja apontando para
     *      este contrato como controller. Um unico deploy publica os dois, e
     *      nao existe janela em que o credito esteja sem dono definido.
     */
    constructor(
        address treasury_,
        address playerA_,
        address playerB_,
        address judge_,
        uint256 settlementThreshold_,
        uint64 epochDuration_
    ) ERC20("InteliBet Chip", "IBET") Ownable(treasury_) {
        if (treasury_ == address(0) || playerA_ == address(0) || playerB_ == address(0) || judge_ == address(0)) {
            revert ZeroAddress();
        }
        // Juiz fora da mesa garantido por construcao — nao ha verificacao por
        // aposta que alguem possa esquecer de fazer depois.
        if (playerA_ == playerB_ || judge_ == playerA_ || judge_ == playerB_) revert DuplicateRole();

        playerA = playerA_;
        playerB = playerB_;
        judge = judge_;
        settlementThreshold = settlementThreshold_;

        epochDuration = epochDuration_;
        calendarMonths = epochDuration_ == 0;
        startTime = uint64(block.timestamp);
        _startMonthIndex = _monthIndexOf(block.timestamp);

        credit = new InteliCredit(address(this));
    }

    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }

    /// @notice O outro jogador da mesa.
    function opponentOf(address player) public view returns (address) {
        if (player == playerA) return playerB;
        if (player == playerB) return playerA;

        revert NotAPlayer(player);
    }

    // --- Fichas ----------------------------------------------------------

    /**
     * @notice Emite fichas para um jogador.
     * @dev    Sem lastro e sem teto, de proposito: a ficha e explicitamente
     *         ficticia. O que representa dinheiro real e o credito, e aquele
     *         so nasce de aposta resolvida.
     *
     *         So jogador recebe: ficha fora da mesa nao significa nada.
     */
    function mintChips(address to, uint256 amount) external onlyOwner {
        if (to != playerA && to != playerB) revert NotAPlayer(to);
        if (amount == 0) revert ZeroAmount();

        _mint(to, amount);
        emit ChipsMinted(to, amount);
    }

    // --- Identidade ------------------------------------------------------

    /// @notice Registra o proprio nome. `msg.sender` e a chave: ninguem
    ///         consegue nomear outra pessoa.
    function setName(string calldata name) external {
        uint256 len = bytes(name).length;
        if (len == 0 || len > MAX_NAME_LENGTH) revert InvalidText(len, MAX_NAME_LENGTH);

        _names[msg.sender] = name;
        emit NameSet(msg.sender, name);
    }

    function nameOf(address account) external view returns (string memory) {
        return _names[account];
    }

    /// @notice Nomes dos tres papeis de uma vez, para o painel.
    function tableNames() external view returns (string memory a, string memory b, string memory j) {
        return (_names[playerA], _names[playerB], _names[judge]);
    }

    // --- Ciclo de vida da aposta -----------------------------------------

    /**
     * @notice Propoe uma aposta e ja deposita a propria entrada em fichas.
     * @param stake    Valor de CADA lado, em unidades base (centavos).
     * @param terms    O que esta sendo apostado.
     * @param deadline Timestamp limite, ou 0 para usar `DEFAULT_DEADLINE`.
     *
     * @dev O oponente nao e parametro: so existem dois jogadores, entao o
     *      contrato sabe quem e o outro. Menos um campo para errar.
     */
    function createBet(uint128 stake, string calldata terms, uint64 deadline)
        external
        onlyPlayer
        returns (uint256 id)
    {
        if (stake == 0) revert ZeroAmount();

        uint256 len = bytes(terms).length;
        if (len == 0 || len > MAX_TERMS_LENGTH) revert InvalidText(len, MAX_TERMS_LENGTH);

        uint64 limite = deadline == 0 ? uint64(block.timestamp) + DEFAULT_DEADLINE : deadline;
        if (limite <= block.timestamp) revert InvalidDeadline();

        _bets.push(
            Bet({
                proposer: msg.sender,
                stake: stake,
                deadline: limite,
                status: Status.Open,
                winner: address(0),
                resolvedEpoch: 0,
                byAgreement: false,
                terms: terms
            })
        );
        id = _bets.length - 1;

        _transfer(msg.sender, address(this), stake);

        emit BetCreated(id, msg.sender, stake, limite, terms);
    }

    /// @notice O outro jogador aceita e deposita entrada de valor igual.
    function acceptBet(uint256 id) external onlyPlayer {
        Bet storage bet = _bets[id];

        if (bet.status != Status.Open) revert WrongStatus(bet.status, Status.Open);
        if (msg.sender != opponentOf(bet.proposer)) revert NotAuthorized(msg.sender);
        if (block.timestamp >= bet.deadline) revert DeadlinePassed(bet.deadline);

        bet.status = Status.Active;

        _transfer(msg.sender, address(this), bet.stake);

        emit BetAccepted(id, msg.sender);
    }

    /// @notice O juiz declara o vencedor.
    function resolveBet(uint256 id, address winner) external {
        if (msg.sender != judge) revert NotTheJudge(msg.sender);

        _settle(id, winner, false);
    }

    /**
     * @notice Voto do jogador sobre quem ganhou. Quando os dois apontam a
     *         mesma pessoa, a aposta liquida na hora, sem o juiz.
     * @dev    Na maioria das apostas o resultado e obvio para os dois, e
     *         obrigar a passar pelo juiz seria burocracia. Se discordarem,
     *         nada acontece e o juiz decide.
     */
    function agreeOn(uint256 id, address winner) external onlyPlayer {
        Bet storage bet = _bets[id];

        if (bet.status != Status.Active) revert WrongStatus(bet.status, Status.Active);
        if (winner != playerA && winner != playerB) revert WinnerNotInBet(winner);

        agreementVote[id][msg.sender] = winner;
        emit AgreementVoted(id, msg.sender, winner);

        if (agreementVote[id][opponentOf(msg.sender)] == winner) {
            _settle(id, winner, true);
        }
    }

    /// @notice O proponente retira a proposta enquanto ninguem aceitou.
    function cancelBet(uint256 id) external {
        Bet storage bet = _bets[id];

        if (bet.status != Status.Open) revert WrongStatus(bet.status, Status.Open);
        if (msg.sender != bet.proposer) revert NotAuthorized(msg.sender);

        bet.status = Status.Cancelled;

        _transfer(address(this), bet.proposer, bet.stake);

        emit BetCancelled(id);
    }

    /**
     * @notice Devolve as entradas quando o prazo venceu sem decisao.
     * @dev    Chamavel por QUALQUER PESSOA, de proposito: se dependesse do
     *         juiz, um juiz sumido prenderia as fichas dos dois para sempre.
     *         Vale para proposta nao aceita (devolve so o proponente) e para
     *         aposta ativa (devolve os dois).
     */
    function refundExpired(uint256 id) external {
        Bet storage bet = _bets[id];

        if (bet.status != Status.Open && bet.status != Status.Active) {
            revert WrongStatus(bet.status, Status.Active);
        }
        if (block.timestamp < bet.deadline) revert DeadlineNotReached(bet.deadline);

        bool aceita = bet.status == Status.Active;
        bet.status = Status.Refunded;

        uint256 stake = bet.stake;
        _transfer(address(this), bet.proposer, stake);
        if (aceita) _transfer(address(this), opponentOf(bet.proposer), stake);

        emit BetRefunded(id);
    }

    /**
     * @dev Liquida a aposta nas duas camadas: fichas para o vencedor,
     *      credito compensado. Estado muda antes de qualquer transferencia.
     */
    function _settle(uint256 id, address winner, bool byAgreement) private {
        Bet storage bet = _bets[id];

        if (bet.status != Status.Active) revert WrongStatus(bet.status, Status.Active);
        if (winner != playerA && winner != playerB) revert WinnerNotInBet(winner);

        address loser = opponentOf(winner);
        uint256 stake = bet.stake;
        uint256 epoch = currentEpoch();

        bet.status = Status.Resolved;
        bet.winner = winner;
        bet.resolvedEpoch = uint64(epoch);
        bet.byAgreement = byAgreement;

        grossWon[epoch][winner] += stake;
        betsResolved[epoch] += 1;

        // Camada 1: as duas entradas em ficha vao para o vencedor.
        _transfer(address(this), winner, stake * 2);

        // Camada 2: a divida real, compensada.
        _netCredit(winner, loser, stake);

        emit BetResolved(id, winner, loser, stake, epoch, byAgreement);
    }

    // --- Credito ---------------------------------------------------------

    /**
     * @dev Compensacao: a vitoria abate primeiro a divida contraria e so
     *      depois cria divida nova.
     *
     *      Exemplo — voce ganha 50 e o oponente ja tinha 30 a receber:
     *      queima 30 dele, emite 20 para voce. Sobra o liquido.
     *
     *      Invariante que isso garante: NO MAXIMO UM dos dois tem saldo de
     *      credito em qualquer momento. O saldo E a resposta para "quem deve
     *      quanto a quem" — ninguem precisa calcular nada.
     */
    function _netCredit(address winner, address loser, uint256 amount) private {
        uint256 anterior = credit.balanceOf(winner);
        uint256 contraria = credit.balanceOf(loser);
        uint256 abatido = contraria >= amount ? amount : contraria;

        if (abatido > 0) credit.burn(loser, abatido);

        uint256 emitido = amount - abatido;
        if (emitido > 0) credit.mint(winner, emitido);

        emit CreditNetted(winner, loser, abatido, emitido);

        uint256 agora = anterior + emitido;
        if (agora >= settlementThreshold && anterior < settlementThreshold) {
            emit SettlementDue(winner, loser, agora);
        }
    }

    /**
     * @notice Quem tinha a receber declara que recebeu, e o credito e queimado.
     * @dev    So o credor pode chamar, porque so ele sabe se o dinheiro
     *         chegou. O devedor nao tem funcao nenhuma que reduza a propria
     *         divida — se tivesse, o registro nao valeria nada.
     */
    function confirmPayment(uint256 amount) external onlyPlayer {
        if (amount == 0) revert ZeroAmount();

        credit.burn(msg.sender, amount);
        emit PaymentConfirmed(msg.sender, opponentOf(msg.sender), amount);
    }

    /**
     * @notice Quem deve quanto a quem, agora.
     * @return creditor Quem tem a receber (zero se ninguem deve nada)
     * @return debtor   Quem tem a pagar
     * @return amount   Valor liquido em unidades base
     */
    function netPosition() external view returns (address creditor, address debtor, uint256 amount) {
        uint256 a = credit.balanceOf(playerA);
        if (a > 0) return (playerA, playerB, a);

        uint256 b = credit.balanceOf(playerB);
        if (b > 0) return (playerB, playerA, b);

        return (address(0), address(0), 0);
    }

    // --- Leitura das apostas ---------------------------------------------

    function getBet(uint256 id) external view returns (Bet memory) {
        return _bets[id];
    }

    function betCount() external view returns (uint256) {
        return _bets.length;
    }

    /// @notice Fichas em custodia agora: entradas de apostas nao liquidadas.
    function chipsInEscrow() external view returns (uint256 total) {
        for (uint256 i = 0; i < _bets.length; i++) {
            Status s = _bets[i].status;
            if (s == Status.Open) total += _bets[i].stake;
            else if (s == Status.Active) total += uint256(_bets[i].stake) * 2;
        }
    }

    /// @notice Resumo da mesa, numa chamada so, para o painel.
    function tableSummary()
        external
        view
        returns (
            uint256 epoch,
            uint256 epochEnds,
            uint256 wonA,
            uint256 wonB,
            uint256 chipsA,
            uint256 chipsB,
            address creditor,
            uint256 owed,
            uint256 totalBets
        )
    {
        epoch = currentEpoch();
        epochEnds = epochEndsAt(epoch);
        wonA = grossWon[epoch][playerA];
        wonB = grossWon[epoch][playerB];
        chipsA = balanceOf(playerA);
        chipsB = balanceOf(playerB);

        uint256 a = credit.balanceOf(playerA);
        uint256 b = credit.balanceOf(playerB);
        if (a > 0) (creditor, owed) = (playerA, a);
        else if (b > 0) (creditor, owed) = (playerB, b);

        totalBets = _bets.length;
    }

    // --- Epocas ----------------------------------------------------------

    /// @notice Epoca corrente. Comeca em 0 no deploy, nos dois modos.
    function currentEpoch() public view returns (uint256) {
        if (calendarMonths) return _monthIndexOf(block.timestamp) - _startMonthIndex;

        return (block.timestamp - startTime) / epochDuration;
    }

    /**
     * @notice Momento em que a epoca informada termina.
     * @dev    No modo calendario, e a meia-noite UTC do dia 1 do mes seguinte.
     *         A epoca 0 quase nunca e um mes inteiro: vai do deploy ate a
     *         virada. E proposital — alinhar ao calendario importa mais do que
     *         a primeira epoca ter duracao cheia.
     */
    function epochEndsAt(uint256 epoch) public view returns (uint256) {
        if (calendarMonths) return _monthStart(_startMonthIndex + epoch + 1);

        return startTime + (epoch + 1) * epochDuration;
    }

    // --- Aritmetica de calendario ----------------------------------------
    //
    // Algoritmo days_from_civil / civil_from_days de Howard Hinnant, em
    // aritmetica inteira e sem laco. Trabalha em UTC, calendario gregoriano
    // proleptico, com 1970-01-01 como dia zero. Anos bissextos inclusos.

    /// @dev Meses decorridos desde janeiro de 1970 ate o timestamp dado.
    function _monthIndexOf(uint256 timestamp) private pure returns (uint256) {
        uint256 z = timestamp / 86400 + 719_468;
        uint256 era = z / 146_097;
        uint256 doe = z - era * 146_097;
        uint256 yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
        uint256 y = yoe + era * 400;
        uint256 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        uint256 mp = (5 * doy + 2) / 153;
        uint256 m = mp < 10 ? mp + 3 : mp - 9;
        if (m <= 2) y += 1;

        return y * 12 + (m - 1);
    }

    /// @dev Timestamp da meia-noite UTC do dia 1 do mes de indice dado.
    function _monthStart(uint256 monthIndex) private pure returns (uint256) {
        uint256 y = monthIndex / 12;
        uint256 m = (monthIndex % 12) + 1;
        if (m <= 2) y -= 1;

        uint256 era = y / 400;
        uint256 yoe = y - era * 400;
        uint256 mp = m > 2 ? m - 3 : m + 9;
        uint256 doy = (153 * mp + 2) / 5;
        uint256 doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;

        return (era * 146_097 + doe - 719_468) * 86400;
    }
}
