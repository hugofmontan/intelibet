// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title  INTELIBET — stablecoin de aposta entre pessoas do Inteli
 * @notice 1 IBET = R$ 1,00, lastreado em reserva sob custodia da tesouraria
 *         da comunidade. A aposta e feita hoje e paga depois, entao o valor
 *         apostado precisa significar a mesma coisa nos dois momentos.
 *
 * @dev    Quatro mecanismos, num contrato so:
 *
 *         1. O PEG, por uma invariante que o contrato recusa violar:
 *
 *                totalSupply() <= reservesAttested
 *
 *            `mint` e o unico caminho de emissao e checa isso sempre. A
 *            reserva e publicada on-chain com valor, hash do comprovante e
 *            timestamp, e vence em 30 dias.
 *
 *            Corolario: NAO existe teto fixo de supply. Num token de
 *            governanca o teto seria a garantia central; numa stablecoin
 *            seria defeito — o supply precisa subir quando entra dinheiro na
 *            reserva e cair no resgate. O teto e a reserva, e ela e publica.
 *
 *         2. O HISTORICO, por `settleBet`. Um `transfer` comum nao diz se
 *            aquilo foi aposta paga, rateio de lanche ou emprestimo devolvido.
 *            `settleBet` transfere e marca: quem pagou, quem recebeu, quanto,
 *            quanto de taxa e sobre o que.
 *
 *         3. O INCENTIVO, por epocas e premio. Cada aposta paga deixa 5% num
 *            pote da epoca corrente. No fim da epoca, quem mais ganhou em
 *            apostas leva o pote inteiro.
 *
 *            A taxa NAO incide sobre `transfer`: um ERC-20 que entrega menos
 *            do que foi mandado quebra carteira, exchange e qualquer contrato
 *            que faca conta antes de transferir. Aposta paga tem rake;
 *            mandar dinheiro para um amigo nao paga nada.
 *
 *            A taxa tambem NAO afeta o peg: o valor sai de uma conta e entra
 *            na do proprio contrato. O supply nao muda.
 *
 *         4. A IDENTIDADE, em duas camadas. A blockchain so conhece
 *            enderecos; o painel precisa de nomes.
 *
 *            `setName` e AUTO-DECLARACAO: `msg.sender` e a chave, entao so
 *            voce nomeia a si mesmo, e esse nome tem precedencia sobre
 *            qualquer outro.
 *
 *            `settleBet` aceita um nome para o vencedor, usado apenas quando
 *            ele ainda NAO TEM NOME NENHUM. Serve para quem recebe uma aposta
 *            sem nunca ter interagido com o contrato aparecer no painel com
 *            nome em vez de endereco. Nao sobrescreve nada: nome atribuido
 *            por terceiro cede assim que a pessoa se declara.
 *
 *         Nao ha custodia nem arbitro. Divida de aposta nao e exigivel em
 *         juizo (art. 814 do Codigo Civil), entao a garantia aqui e
 *         reputacional: quem nao paga nao aparece no ranking. Ver
 *         docs/modelagem.md.
 */
contract InteliBet is ERC20, ERC20Burnable, Ownable {
    // --- Parametros do token ---------------------------------------------

    /// @dev 2 casas: IBET pareia com o centavo do real.
    uint8 private constant DECIMALS = 2;

    /// @notice Prazo de validade de uma atestacao de reserva.
    uint64 public constant ATTESTATION_MAX_AGE = 30 days;

    /// @notice Limite do texto da aposta, para o evento nao virar deposito de lixo.
    uint256 public constant MAX_DESCRIPTION_LENGTH = 200;

    /// @notice Limite do nome, para o painel nao quebrar.
    uint256 public constant MAX_NAME_LENGTH = 24;

    // --- Parametros do premio --------------------------------------------

    /// @notice Taxa sobre aposta paga, em basis points. 500 = 5,00%.
    uint16 public constant FEE_BPS = 500;

    /**
     * @notice Duracao de uma epoca, em segundos.
     * @dev    Parametro de deploy porque producao e demonstracao querem coisas
     *         diferentes: 30 dias (2592000) num uso real, algo como 600 (dez
     *         minutos) num deploy de teste, para dar para mostrar o ciclo
     *         inteiro — apostas, virada de epoca e premio — dentro de um video.
     */
    uint64 public immutable epochDuration;

    /**
     * @notice Quantos adversarios distintos e preciso vencer na epoca para
     *         concorrer ao premio.
     * @dev    Mitigacao (parcial) de auto-aposta: sem isso, duas carteiras
     *         suas fabricam vitorias e farmam o pote. Producao: 3 ou mais.
     *         Demonstracao com duas contas: 1.
     */
    uint32 public immutable minDistinctOpponents;

    /// @notice Momento do deploy. Marco zero da contagem de epocas.
    uint64 public immutable startTime;

    // --- Prova de reserva ------------------------------------------------

    /// @notice Reserva atestada, em unidades base (centavos de real).
    uint256 public reservesAttested;

    /// @notice Hash do comprovante de reserva publicado off-chain.
    bytes32 public reserveProofHash;

    /// @notice Momento da ultima atestacao.
    uint64 public reserveAttestedAt;

    // --- Estado do premio ------------------------------------------------

    /// @notice Pote acumulado por epoca, em unidades base.
    mapping(uint256 => uint256) public prizePool;

    /// @notice Valor bruto ganho em apostas, por epoca e por endereco.
    mapping(uint256 => mapping(address => uint256)) public grossWon;

    /// @notice Adversarios distintos vencidos, por epoca e por endereco.
    mapping(uint256 => mapping(address => uint32)) public distinctOpponents;

    /// @notice Lider da epoca — quem mais ganhou, entre os elegiveis.
    mapping(uint256 => address) public epochLeader;

    /// @notice Valor bruto do lider, usado para a comparacao corrente.
    mapping(uint256 => uint256) public epochLeaderAmount;

    /// @notice Epocas cujo pote ja foi distribuido ou transferido adiante.
    mapping(uint256 => bool) public prizeSettled;

    /// @dev Marca se `winner` ja venceu `loser` naquela epoca.
    mapping(uint256 => mapping(address => mapping(address => bool))) private _alreadyBeat;

    // --- Identidade ------------------------------------------------------

    /// @dev Nome de cada endereco. Vazio quando nao ha nome.
    mapping(address => string) private _names;

    /// @dev Se o nome foi declarado pela propria carteira ou atribuido por terceiro.
    mapping(address => bool) private _selfDeclared;

    // --- Eventos ---------------------------------------------------------

    event ReserveAttested(uint256 amount, bytes32 proofHash, uint64 at);
    event RedemptionRequested(address indexed from, uint256 amount, string payoutRef);

    /**
     * @notice Uma aposta foi paga. E a unica fonte do ranking publico.
     * @param loser       quem perdeu e pagou (quem chamou a funcao)
     * @param winner      quem ganhou
     * @param amount      valor da aposta em unidades base
     * @param fee         parte que ficou no pote da epoca
     * @param epoch       epoca em que foi registrada
     * @param description sobre o que era a aposta
     */
    event BetSettled(
        address indexed loser,
        address indexed winner,
        uint256 amount,
        uint256 fee,
        uint256 indexed epoch,
        string description
    );

    event LeaderChanged(uint256 indexed epoch, address indexed leader, uint256 grossWon);
    event PrizeClaimed(uint256 indexed epoch, address indexed winner, uint256 amount);
    event PrizeRolledOver(uint256 indexed epoch, uint256 amount, uint256 toEpoch);

    event NameSet(address indexed account, string name);
    event NameAttributed(address indexed account, string name, address indexed by);
    event NameCleared(address indexed account);

    // --- Erros -----------------------------------------------------------

    error ReserveInsufficient(uint256 supplyAfter, uint256 reserves);
    error StaleAttestation(uint64 attestedAt, uint64 maxAge);
    error InvalidCounterparty();
    error InvalidDescription(uint256 length, uint256 max);
    error InvalidName(uint256 length, uint256 max);
    error AmountTooSmall(uint256 amount, uint256 minimum);
    error EpochNotFinished(uint256 epoch, uint256 current);
    error PrizeAlreadySettled(uint256 epoch);
    error InvalidEpochDuration();
    error ZeroAddress();
    error ZeroAmount();

    // --- Construtor ------------------------------------------------------

    /**
     * @param treasury              Tesouraria: custodia a reserva, atesta e emite.
     * @param epochDuration_        Segundos por epoca. 2592000 = 30 dias.
     * @param minDistinctOpponents_ Adversarios distintos exigidos para concorrer.
     *
     * @dev Nenhum IBET e emitido no deploy. Como `reserveAttestedAt` comeca em
     *      zero, o primeiro `mint` ja reverte por atestacao vencida: o contrato
     *      nasce impedido de emitir sem lastro, sem depender de o operador
     *      seguir a ordem certa.
     */
    constructor(address treasury, uint64 epochDuration_, uint32 minDistinctOpponents_)
        ERC20("InteliBet", "IBET")
        Ownable(treasury)
    {
        if (treasury == address(0)) revert ZeroAddress();
        if (epochDuration_ == 0) revert InvalidEpochDuration();

        epochDuration = epochDuration_;
        minDistinctOpponents = minDistinctOpponents_;
        startTime = uint64(block.timestamp);
    }

    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }

    // --- Reserva ---------------------------------------------------------

    /**
     * @notice Publica o saldo da reserva sob custodia e o hash do comprovante.
     * @dev   Nao valida contra o supply de proposito: atestar reserva ABAIXO
     *        do supply e um evento legitimo e importante — significa que o
     *        token esta subcolateralizado, e isso precisa ser visivel em vez
     *        de impossivel de declarar. O efeito e automatico:
     *        `collateralizationBps()` cai abaixo de 10000 e `mint` para de
     *        funcionar sozinho.
     */
    function attestReserves(uint256 amount, bytes32 proofHash) external onlyOwner {
        reservesAttested = amount;
        reserveProofHash = proofHash;
        reserveAttestedAt = uint64(block.timestamp);

        emit ReserveAttested(amount, proofHash, reserveAttestedAt);
    }

    /// @notice Razao de colateralizacao em basis points. 10000 = 100%.
    /// @dev    Devolve 0 quando nao ha supply — razao indefinida, nao zero.
    function collateralizationBps() external view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 0;

        return (reservesAttested * 10_000) / supply;
    }

    /// @notice Reserva excedente ainda disponivel para emissao.
    function mintableAmount() public view returns (uint256) {
        uint256 supply = totalSupply();
        return reservesAttested > supply ? reservesAttested - supply : 0;
    }

    // --- Emissao e resgate -----------------------------------------------

    /// @notice Emite IBET contra reserva ja atestada. Aqui mora a invariante.
    function mint(address to, uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        if (block.timestamp > reserveAttestedAt + ATTESTATION_MAX_AGE) {
            revert StaleAttestation(reserveAttestedAt, ATTESTATION_MAX_AGE);
        }

        uint256 supplyAfter = totalSupply() + amount;
        if (supplyAfter > reservesAttested) revert ReserveInsufficient(supplyAfter, reservesAttested);

        _mint(to, amount);
    }

    /**
     * @notice Queima IBET e registra o pedido de resgate em reais.
     * @dev    A queima acontece antes de a tesouraria pagar, entao a
     *         colateralizacao nunca piora durante um resgate em andamento.
     */
    function redeem(uint256 amount, string calldata payoutRef) external {
        if (amount == 0) revert ZeroAmount();

        _burn(msg.sender, amount);
        emit RedemptionRequested(msg.sender, amount, payoutRef);
    }

    // --- Identidade ------------------------------------------------------

    /**
     * @notice Registra ou troca o proprio nome no painel.
     * @dev    `msg.sender` e a chave: ninguem consegue nomear outra pessoa.
     *         O registro e auto-declarado — nada impede alguem de se chamar
     *         "Presidente" —, mas a garantia que existe e clara: o nome
     *         exibido e sempre o que aquele endereco escolheu para si.
     *
     *         Nao ha owner nem moderacao aqui. A tesouraria nao pode alterar
     *         nem apagar o nome de ninguem.
     */
    function setName(string calldata name) external {
        _validateName(name);

        _names[msg.sender] = name;
        _selfDeclared[msg.sender] = true;

        emit NameSet(msg.sender, name);
    }

    /// @notice Apaga o proprio nome. Volta a aparecer so o endereco.
    function clearName() external {
        delete _names[msg.sender];
        delete _selfDeclared[msg.sender];

        emit NameCleared(msg.sender);
    }

    /// @notice Nome de um endereco. String vazia quando nao ha nome.
    function nameOf(address account) external view returns (string memory) {
        return _names[account];
    }

    /// @notice Se aquele nome foi declarado pela propria carteira.
    function isSelfDeclared(address account) external view returns (bool) {
        return _selfDeclared[account];
    }

    /**
     * @notice Nomes de varios enderecos de uma vez, com a origem de cada um.
     * @dev    O painel precisa dos nomes de todos os participantes do ranking;
     *         uma chamada em lote evita N idas ao no para N pessoas. O segundo
     *         retorno permite marcar na tela o que ainda nao foi confirmado
     *         pela propria carteira.
     */
    function namesOf(address[] calldata accounts)
        external
        view
        returns (string[] memory names, bool[] memory selfDeclared)
    {
        names = new string[](accounts.length);
        selfDeclared = new bool[](accounts.length);

        for (uint256 i = 0; i < accounts.length; i++) {
            names[i] = _names[accounts[i]];
            selfDeclared[i] = _selfDeclared[accounts[i]];
        }
    }

    function _validateName(string calldata name) private pure {
        uint256 len = bytes(name).length;
        if (len == 0 || len > MAX_NAME_LENGTH) revert InvalidName(len, MAX_NAME_LENGTH);
    }

    // --- Epocas ----------------------------------------------------------

    /// @notice Epoca corrente. Comeca em 0 no deploy.
    function currentEpoch() public view returns (uint256) {
        return (block.timestamp - startTime) / epochDuration;
    }

    /// @notice Momento em que a epoca informada termina.
    function epochEndsAt(uint256 epoch) public view returns (uint256) {
        return startTime + (epoch + 1) * epochDuration;
    }

    /// @notice Se o endereco ja cumpre o minimo de adversarios distintos.
    function isEligible(uint256 epoch, address account) public view returns (bool) {
        return distinctOpponents[epoch][account] >= minDistinctOpponents;
    }

    // --- Pagamento de aposta ---------------------------------------------

    /**
     * @notice Paga uma aposta perdida, cobra a taxa e registra o resultado.
     * @dev    Chamada por QUEM PERDEU. O pagador e sempre `msg.sender`, nunca
     *         um parametro: ninguem consegue plantar uma derrota na conta de
     *         outra pessoa, porque o valor sai do saldo de quem chama.
     *
     *         Do valor apostado, 5% ficam no pote da epoca e o resto vai
     *         direto para quem ganhou. O contrato nunca custodia o valor da
     *         aposta — so o pote.
     *
     *         O RANKING E POR VALOR BRUTO GANHO, nao por saldo liquido. E
     *         decisao tecnica com efeito de produto: bruto so sobe, entao
     *         manter o lider e uma comparacao de uma linha. Saldo liquido
     *         desceria quando alguem perde, e achar o novo lider exigiria
     *         varrer todos os participantes — impossivel numa transacao.
     *
     * @param winnerName Nome para o vencedor, ou string vazia para nao mexer.
     *        So e aplicado se ele ainda nao tiver NENHUM nome: nao sobrescreve
     *        auto-declaracao nem atribuicao anterior. Serve para quem recebe
     *        uma aposta sem nunca ter usado o contrato aparecer no painel com
     *        nome — e ele pode trocar depois, chamando `setName`.
     */
    function settleBet(address winner, uint256 amount, string calldata description, string calldata winnerName)
        external
    {
        if (winner == address(0)) revert ZeroAddress();
        if (winner == msg.sender || winner == address(this)) revert InvalidCounterparty();

        // Abaixo disso a taxa truncaria para zero e a aposta nao alimentaria
        // o pote — o que abriria um caminho de registro gratuito no ranking.
        uint256 minimum = 10_000 / FEE_BPS; // 20 unidades base = R$ 0,20
        if (amount < minimum) revert AmountTooSmall(amount, minimum);

        uint256 len = bytes(description).length;
        if (len == 0 || len > MAX_DESCRIPTION_LENGTH) revert InvalidDescription(len, MAX_DESCRIPTION_LENGTH);

        uint256 fee = (amount * FEE_BPS) / 10_000;
        uint256 epoch = currentEpoch();

        _transfer(msg.sender, winner, amount - fee);
        _transfer(msg.sender, address(this), fee);

        prizePool[epoch] += fee;
        _registerWin(epoch, winner, msg.sender, amount);

        if (bytes(winnerName).length > 0 && bytes(_names[winner]).length == 0) {
            _validateName(winnerName);
            _names[winner] = winnerName;

            emit NameAttributed(winner, winnerName, msg.sender);
        }

        emit BetSettled(msg.sender, winner, amount, fee, epoch, description);
    }

    /// @dev Atualiza placar, contagem de adversarios distintos e lider.
    function _registerWin(uint256 epoch, address winner, address loser, uint256 amount) private {
        if (!_alreadyBeat[epoch][winner][loser]) {
            _alreadyBeat[epoch][winner][loser] = true;
            distinctOpponents[epoch][winner] += 1;
        }

        uint256 total = grossWon[epoch][winner] + amount;
        grossWon[epoch][winner] = total;

        // A elegibilidade e reavaliada a cada aposta. Como o bruto so sobe,
        // quem vira elegivel nesta chamada ja e comparado com o lider aqui.
        if (total > epochLeaderAmount[epoch] && distinctOpponents[epoch][winner] >= minDistinctOpponents) {
            epochLeaderAmount[epoch] = total;
            epochLeader[epoch] = winner;

            emit LeaderChanged(epoch, winner, total);
        }
    }

    // --- Premio ----------------------------------------------------------

    /**
     * @notice Entrega o pote da epoca ao lider dela.
     * @dev    Sem restricao de quem chama, de proposito: se dependesse do
     *         ganhador, um ganhador desatento deixaria o pote parado, e se
     *         dependesse da tesouraria ela teria poder de reter. Qualquer um
     *         aciona; o valor vai para quem o contrato registrou como lider.
     *
     *         Epoca sem lider elegivel — porque ninguem venceu adversarios
     *         distintos suficientes — nao queima o pote: ele passa para a
     *         epoca corrente.
     *
     *         Nao existe funcao que permita a tesouraria sacar o pote. O
     *         unico caminho de saida do saldo do contrato e este.
     */
    function claimPrize(uint256 epoch) external {
        uint256 current = currentEpoch();
        if (epoch >= current) revert EpochNotFinished(epoch, current);
        if (prizeSettled[epoch]) revert PrizeAlreadySettled(epoch);

        prizeSettled[epoch] = true;

        uint256 pot = prizePool[epoch];
        address winner = epochLeader[epoch];

        if (pot == 0) return;

        prizePool[epoch] = 0;

        if (winner == address(0)) {
            prizePool[current] += pot;
            emit PrizeRolledOver(epoch, pot, current);
            return;
        }

        _transfer(address(this), winner, pot);
        emit PrizeClaimed(epoch, winner, pot);
    }
}
