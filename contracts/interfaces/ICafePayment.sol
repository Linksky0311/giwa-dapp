// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title ICafePayment
 * @notice 카페 결제 컨트랙트 인터페이스
 * @dev 방식 A: approve + pay (일반 ERC-20)
 *      방식 B: payWithAuthorization (ERC-3009, approve 불필요)
 */
interface ICafePayment {
    // ========== 결제 ==========

    function pay(address token, uint256 amount) external;

    function payWithAuthorization(
        address token,
        uint256 amount,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    // ========== 화이트리스트 관리 ==========

    function addWhitelistedToken(address token) external;
    function removeWhitelistedToken(address token) external;
    function whitelistedTokens(address token) external view returns (bool);

    // ========== Merchant 관리 ==========

    function setMerchant(address newMerchant) external;
    function merchant() external view returns (address);

    // ========== 수수료 관리 ==========

    function setFeeRate(uint256 newFeeRate) external;
    function feeRate() external view returns (uint256);
    function FEE_DENOMINATOR() external view returns (uint256);
    function MAX_FEE_RATE() external view returns (uint256);

    // ========== 수수료 인출 ==========

    function withdrawFees(address token) external;

    // ========== Ownership ==========

    function owner() external view returns (address);
    function transferOwnership(address newOwner) external;
    function renounceOwnership() external;

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
}
