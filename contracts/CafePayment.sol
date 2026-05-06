// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IKUSDC.sol";
import "./interfaces/ICafePayment.sol";

/**
 * @title CafePayment
 * @notice 카페 결제 컨트랙트 — GIWA 체인 배포용
 * @dev 방식 A: approve + pay (일반 ERC-20 방식)
 *      방식 B: payWithAuthorization (ERC-3009, approve 불필요)
 *
 *      역할 구조:
 *      - Owner (Franchise): 화이트리스트/수수료/가맹점 관리, 수수료 인출
 *      - Merchant (Cafe Owner): 결제금액(수수료 제외) 수취
 *      - Customer: 결제자
 */
contract CafePayment is Ownable {
    using SafeERC20 for IERC20;

    // ========== 상수 ==========

    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public constant MAX_FEE_RATE = 1000; // 10%

    // ========== 상태 변수 ==========

    address private _merchant;
    uint256 private _feeRate; // basis points (예: 250 = 2.5%)

    mapping(address => bool) private _whitelistedTokens;

    // ========== Events ==========

    event Paid(
        address indexed payer,
        address indexed token,
        uint256 amount,
        uint256 fee,
        string method,
        uint256 timestamp
    );
    event TokenWhitelisted(address indexed token);
    event TokenRemovedFromWhitelist(address indexed token);
    event FeeRateUpdated(uint256 oldRate, uint256 newRate);
    event MerchantUpdated(address oldMerchant, address newMerchant);
    event Withdrawn(address indexed token, uint256 amount);

    // ========== Constructor ==========

    constructor(
        address initialOwner,
        address initialMerchant,
        uint256 initialFeeRate
    ) Ownable(initialOwner) {
        require(initialMerchant != address(0), "CafePayment: merchant is zero address");
        require(initialFeeRate <= MAX_FEE_RATE, "CafePayment: fee rate exceeds max");
        _merchant = initialMerchant;
        _feeRate = initialFeeRate;
        emit MerchantUpdated(address(0), initialMerchant);
        emit FeeRateUpdated(0, initialFeeRate);
    }

    // ========== 결제: 방식 A (approve + pay) ==========

    /**
     * @notice ERC-20 approve 후 결제
     * @dev 고객이 먼저 token.approve(cafePayment, amount)를 호출해야 함
     * @param token 결제 토큰 주소 (화이트리스트 필수)
     * @param amount 결제 금액 (토큰 단위)
     */
    function pay(address token, uint256 amount) external {
        _validatePayment(token, amount);

        uint256 fee = _calculateFee(amount);
        uint256 merchantAmount = amount - fee;

        // 고객 → 가맹점 (수수료 제외)
        IERC20(token).safeTransferFrom(msg.sender, _merchant, merchantAmount);

        // 고객 → 컨트랙트 (수수료)
        if (fee > 0) {
            IERC20(token).safeTransferFrom(msg.sender, address(this), fee);
        }

        emit Paid(msg.sender, token, amount, fee, "ERC20", block.timestamp);
    }

    // ========== 결제: 방식 B (ERC-3009, approve 불필요) ==========

    /**
     * @notice ERC-3009 서명 기반 결제 (gasless approve)
     * @dev 고객이 오프체인 서명을 생성하면 가맹점(또는 릴레이어)이 호출
     * @param token ERC-3009 지원 토큰 주소
     * @param amount 결제 금액
     * @param validAfter 서명 유효 시작 타임스탬프
     * @param validBefore 서명 유효 만료 타임스탬프
     * @param nonce 재사용 방지 nonce (랜덤 bytes32)
     * @param v, r, s 서명 값
     */
    function payWithAuthorization(
        address token,
        uint256 amount,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _validatePayment(token, amount);

        uint256 fee = _calculateFee(amount);
        uint256 merchantAmount = amount - fee;

        // ERC-3009: from(customer) → to(this contract) 전체 금액
        IKUSDC(token).transferWithAuthorization(
            tx.origin, // from: 최초 서명자(고객) — 릴레이어 호출 시 tx.origin 사용
            address(this),
            amount,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );

        // 수수료 제외 후 가맹점에게 전달
        IERC20(token).safeTransfer(_merchant, merchantAmount);

        emit Paid(tx.origin, token, amount, fee, "ERC3009", block.timestamp);
    }

    // ========== 화이트리스트 관리 ==========

    function addWhitelistedToken(address token) external onlyOwner {
        require(token != address(0), "CafePayment: token is zero address");
        _whitelistedTokens[token] = true;
        emit TokenWhitelisted(token);
    }

    function removeWhitelistedToken(address token) external onlyOwner {
        _whitelistedTokens[token] = false;
        emit TokenRemovedFromWhitelist(token);
    }

    function whitelistedTokens(address token) external view returns (bool) {
        return _whitelistedTokens[token];
    }

    // ========== Merchant 관리 ==========

    function setMerchant(address newMerchant) external onlyOwner {
        require(newMerchant != address(0), "CafePayment: new merchant is zero address");
        address old = _merchant;
        _merchant = newMerchant;
        emit MerchantUpdated(old, newMerchant);
    }

    function merchant() external view returns (address) {
        return _merchant;
    }

    // ========== 수수료 관리 ==========

    function setFeeRate(uint256 newFeeRate) external onlyOwner {
        require(newFeeRate <= MAX_FEE_RATE, "CafePayment: fee rate exceeds max (10%)");
        uint256 old = _feeRate;
        _feeRate = newFeeRate;
        emit FeeRateUpdated(old, newFeeRate);
    }

    function feeRate() external view returns (uint256) {
        return _feeRate;
    }

    // ========== 수수료 인출 ==========

    function withdrawFees(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "CafePayment: no fees to withdraw");
        IERC20(token).safeTransfer(owner(), balance);
        emit Withdrawn(token, balance);
    }

    // ========== 내부 유틸 ==========

    function _validatePayment(address token, uint256 amount) internal view {
        require(_whitelistedTokens[token], "CafePayment: token not whitelisted");
        require(amount > 0, "CafePayment: amount must be greater than 0");
    }

    function _calculateFee(uint256 amount) internal view returns (uint256) {
        return (amount * _feeRate) / FEE_DENOMINATOR;
    }
}
