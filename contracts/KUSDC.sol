// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IKUSDC.sol";

/**
 * @title KUSDC
 * @notice GIWA 체인용 K-USDC 스테이블코인
 * @dev USDC FiatTokenV2_2 구조 기반
 *      ERC-20 + EIP-2612 permit + ERC-3009 + Minter + Blacklist + Pause
 */
contract KUSDC is ERC20, ERC20Permit, Pausable, Ownable {
    // ========== ERC-3009 Type Hashes ==========

    bytes32 public constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH =
        keccak256(
            "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
        );

    bytes32 public constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH =
        keccak256(
            "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
        );

    bytes32 public constant CANCEL_AUTHORIZATION_TYPEHASH =
        keccak256("CancelAuthorization(address authorizer,bytes32 nonce)");

    bytes32 public constant PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    // ========== 역할 ==========

    address private _pauser;
    address private _rescuer;

    // ========== Minter ==========

    mapping(address => bool) private _minters;
    mapping(address => uint256) private _minterAllowances;

    // ========== 블랙리스트 ==========

    mapping(address => bool) private _blacklisted;

    // ========== ERC-3009 Authorization States ==========

    mapping(address => mapping(bytes32 => bool)) private _authorizationStates;

    // ========== Events ==========

    event MinterConfigured(address indexed minter, uint256 minterAllowedAmount);
    event MinterRemoved(address indexed oldMinter);
    event Mint(address indexed minter, address indexed to, uint256 amount);
    event Burn(address indexed burner, uint256 amount);
    event Blacklisted(address indexed account);
    event UnBlacklisted(address indexed account);
    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);
    event AuthorizationCanceled(address indexed authorizer, bytes32 indexed nonce);
    event PauserChanged(address indexed newAddress);
    event RescuerChanged(address indexed newAddress);

    // ========== Modifiers ==========

    modifier onlyPauser() {
        require(msg.sender == _pauser, "KUSDC: caller is not the pauser");
        _;
    }

    modifier onlyRescuer() {
        require(msg.sender == _rescuer, "KUSDC: caller is not the rescuer");
        _;
    }

    modifier onlyMinter() {
        require(_minters[msg.sender], "KUSDC: caller is not a minter");
        _;
    }

    modifier notBlacklisted(address account) {
        require(!_blacklisted[account], "KUSDC: account is blacklisted");
        _;
    }

    // ========== Constructor ==========

    constructor(
        address initialOwner,
        address initialPauser,
        address initialRescuer
    ) ERC20("K-USDC", "KUSDC") ERC20Permit("K-USDC") Ownable(initialOwner) {
        _pauser = initialPauser;
        _rescuer = initialRescuer;
        emit PauserChanged(initialPauser);
        emit RescuerChanged(initialRescuer);
    }

    // ========== ERC-20 기본 (pause & blacklist 적용) ==========

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function transfer(
        address to,
        uint256 value
    )
        public
        override
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(to)
        returns (bool)
    {
        return super.transfer(to, value);
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    )
        public
        override
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(from)
        notBlacklisted(to)
        returns (bool)
    {
        return super.transferFrom(from, to, value);
    }

    function approve(
        address spender,
        uint256 value
    )
        public
        override
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(spender)
        returns (bool)
    {
        return super.approve(spender, value);
    }

    function increaseAllowance(
        address spender,
        uint256 addedValue
    )
        public
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(spender)
        returns (bool)
    {
        address owner = msg.sender;
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    )
        public
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(spender)
        returns (bool)
    {
        address owner = msg.sender;
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= subtractedValue, "KUSDC: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }
        return true;
    }

    // ========== Minter 관리 ==========

    function configureMinter(
        address minter,
        uint256 minterAllowedAmount
    ) external onlyOwner {
        _minters[minter] = true;
        _minterAllowances[minter] = minterAllowedAmount;
        emit MinterConfigured(minter, minterAllowedAmount);
    }

    function removeMinter(address minter) external onlyOwner {
        _minters[minter] = false;
        _minterAllowances[minter] = 0;
        emit MinterRemoved(minter);
    }

    function isMinter(address account) external view returns (bool) {
        return _minters[account];
    }

    function minterAllowance(address minter) external view returns (uint256) {
        return _minterAllowances[minter];
    }

    // ========== 민팅 / 소각 ==========

    function mint(
        address to,
        uint256 amount
    )
        external
        whenNotPaused
        onlyMinter
        notBlacklisted(msg.sender)
        notBlacklisted(to)
    {
        require(amount > 0, "KUSDC: mint amount not greater than 0");
        require(
            _minterAllowances[msg.sender] >= amount,
            "KUSDC: mint amount exceeds minterAllowance"
        );
        unchecked {
            _minterAllowances[msg.sender] -= amount;
        }
        _mint(to, amount);
        emit Mint(msg.sender, to, amount);
    }

    function burn(uint256 amount) external whenNotPaused onlyMinter notBlacklisted(msg.sender) {
        require(amount > 0, "KUSDC: burn amount not greater than 0");
        _burn(msg.sender, amount);
        emit Burn(msg.sender, amount);
    }

    // ========== 블랙리스트 ==========

    function blacklist(address account) external onlyOwner {
        _blacklisted[account] = true;
        emit Blacklisted(account);
    }

    function unBlacklist(address account) external onlyOwner {
        _blacklisted[account] = false;
        emit UnBlacklisted(account);
    }

    function isBlacklisted(address account) external view returns (bool) {
        return _blacklisted[account];
    }

    // ========== Pause ==========

    function pause() external onlyPauser {
        _pause();
    }

    function unpause() external onlyPauser {
        _unpause();
    }

    // ========== 역할 관리 ==========

    function updatePauser(address newPauser) external onlyOwner {
        require(newPauser != address(0), "KUSDC: new pauser is the zero address");
        _pauser = newPauser;
        emit PauserChanged(newPauser);
    }

    function updateRescuer(address newRescuer) external onlyOwner {
        require(newRescuer != address(0), "KUSDC: new rescuer is the zero address");
        _rescuer = newRescuer;
        emit RescuerChanged(newRescuer);
    }

    function pauser() external view returns (address) {
        return _pauser;
    }

    function rescuer() external view returns (address) {
        return _rescuer;
    }

    // ========== Rescue ==========

    function rescueERC20(
        IERC20 token,
        address to,
        uint256 amount
    ) external onlyRescuer {
        token.transfer(to, amount);
    }

    // ========== EIP-2612: permit ==========
    // ERC20Permit에서 상속 — nonces(), permit(), DOMAIN_SEPARATOR() 자동 제공

    // ========== ERC-3009 ==========

    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        whenNotPaused
        notBlacklisted(from)
        notBlacklisted(to)
    {
        _requireValidAuthorization(from, nonce, validAfter, validBefore);
        _verifySignature(
            from,
            keccak256(
                abi.encode(
                    TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
                    from,
                    to,
                    value,
                    validAfter,
                    validBefore,
                    nonce
                )
            ),
            v,
            r,
            s
        );
        _markAuthorizationAsUsed(from, nonce);
        _transfer(from, to, value);
    }

    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        whenNotPaused
        notBlacklisted(from)
        notBlacklisted(to)
    {
        require(to == msg.sender, "KUSDC: caller must be the payee");
        _requireValidAuthorization(from, nonce, validAfter, validBefore);
        _verifySignature(
            from,
            keccak256(
                abi.encode(
                    RECEIVE_WITH_AUTHORIZATION_TYPEHASH,
                    from,
                    to,
                    value,
                    validAfter,
                    validBefore,
                    nonce
                )
            ),
            v,
            r,
            s
        );
        _markAuthorizationAsUsed(from, nonce);
        _transfer(from, to, value);
    }

    function cancelAuthorization(
        address authorizer,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(
            !_authorizationStates[authorizer][nonce],
            "KUSDC: authorization is used or canceled"
        );
        _verifySignature(
            authorizer,
            keccak256(
                abi.encode(CANCEL_AUTHORIZATION_TYPEHASH, authorizer, nonce)
            ),
            v,
            r,
            s
        );
        _authorizationStates[authorizer][nonce] = true;
        emit AuthorizationCanceled(authorizer, nonce);
    }

    function authorizationState(
        address authorizer,
        bytes32 nonce
    ) external view returns (bool) {
        return _authorizationStates[authorizer][nonce];
    }

    // ========== 내부 유틸 ==========

    function _requireValidAuthorization(
        address authorizer,
        bytes32 nonce,
        uint256 validAfter,
        uint256 validBefore
    ) internal view {
        require(
            block.timestamp > validAfter,
            "KUSDC: authorization is not yet valid"
        );
        require(block.timestamp < validBefore, "KUSDC: authorization is expired");
        require(
            !_authorizationStates[authorizer][nonce],
            "KUSDC: authorization is used or canceled"
        );
    }

    function _markAuthorizationAsUsed(
        address authorizer,
        bytes32 nonce
    ) internal {
        _authorizationStates[authorizer][nonce] = true;
        emit AuthorizationUsed(authorizer, nonce);
    }

    function _verifySignature(
        address signer,
        bytes32 structHash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal view {
        bytes32 digest = _hashTypedDataV4(structHash);
        address recovered = ecrecover(digest, v, r, s);
        require(recovered == signer, "KUSDC: invalid signature");
    }
}
