// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title  InteliBetNames — registro de nomes do painel do INTELIBET
 * @notice Traduz endereco em nome para o ranking. Cada pessoa registra o
 *         PROPRIO nome: `msg.sender` e a chave, entao ninguem consegue
 *         nomear outra pessoa.
 *
 * @dev    Contrato separado do token, de proposito. O InteliBet nao tem nada
 *         a ver com nomes — misturar as duas coisas amarraria o dinheiro da
 *         comunidade a uma funcionalidade cosmetica, e obrigaria a
 *         republicar o token para mudar qualquer coisa aqui.
 *
 *         O registro e auto-declarado: nada impede alguem de se chamar
 *         "Presidente". A garantia que existe e mais fraca e mais honesta:
 *         so voce assina pela sua carteira, entao o nome exibido e sempre o
 *         que aquele endereco escolheu para si.
 *
 *         Nao ha owner, nao ha moderacao, nao ha taxa. Quem publica o
 *         contrato nao ganha nenhum poder sobre ele.
 */
contract InteliBetNames {
    /// @notice Limite do nome, para o painel nao quebrar e o evento nao inchar.
    uint256 public constant MAX_NAME_LENGTH = 24;

    mapping(address => string) private _names;

    event NameSet(address indexed account, string name);
    event NameCleared(address indexed account);

    error InvalidName(uint256 length, uint256 max);

    /// @notice Registra ou troca o proprio nome.
    function setName(string calldata name) external {
        uint256 len = bytes(name).length;
        if (len == 0 || len > MAX_NAME_LENGTH) revert InvalidName(len, MAX_NAME_LENGTH);

        _names[msg.sender] = name;
        emit NameSet(msg.sender, name);
    }

    /// @notice Apaga o proprio nome. Volta a aparecer so o endereco.
    function clearName() external {
        delete _names[msg.sender];
        emit NameCleared(msg.sender);
    }

    /// @notice Nome de um endereco. String vazia quando nao ha registro.
    function nameOf(address account) external view returns (string memory) {
        return _names[account];
    }

    /**
     * @notice Nomes de varios enderecos de uma vez.
     * @dev    O painel precisa de todos os participantes do ranking; uma
     *         chamada em lote evita N idas ao no para N pessoas.
     */
    function namesOf(address[] calldata accounts) external view returns (string[] memory names) {
        names = new string[](accounts.length);

        for (uint256 i = 0; i < accounts.length; i++) {
            names[i] = _names[accounts[i]];
        }
    }
}
