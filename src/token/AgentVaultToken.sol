// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TOKEN_FIXED_SUPPLY, BPS} from "../Constants.sol";

/// @title AgentVaultToken
/// @notice ERC-4626 vault token representing fractional ownership of an agent project.
///
/// Shares are minted exclusively by the Sale contract during the finalization phase.
/// Once the sale is complete, no new shares can be created; the only way for share
/// value to increase is through direct collateral transfers to this address, which increases
/// totalAssets() without diluting supply.
///
/// Revenue flow: agent operations generate collateral that accumulates in the Safe treasury.
/// The agent owner periodically transfers collateral directly to this vault address, increasing
/// the redemption value of each share.
contract AgentVaultToken is ERC4626 {
    using SafeERC20 for IERC20;

    address public immutable SALE;
    address public immutable TREASURY;
    uint16 public immutable PLATFORM_FEE_BPS;
    address public immutable PLATFORM_FEE_RECIPIENT;

    bool public bootstrapped;
    bool public saleCompleted;

    event Bootstrapped(uint256 assets, uint256 shares);
    event SaleCompleted();
    event ProfitsDistributed(uint256 grossAmount, uint256 feeAmount, uint256 netAmount);

    error InvalidAddress();
    error InvalidAmount();
    error NotBootstrapped();
    error AlreadyBootstrapped();
    error DepositDisabled();
    error MintDisabled();
    error OnlySale();
    error OnlyTreasury();
    error SaleAlreadyCompleted();

    /// @param asset_   The underlying ERC-20 collateral token.
    /// @param sale_    The Sale contract authorised to deposit during the raise.
    /// @param name_    ERC-20 name of the share token.
    /// @param symbol_  ERC-20 symbol of the share token.
    constructor(
        address asset_,
        address sale_,
        address treasury_,
        uint16 platformFeeBps_,
        address platformFeeRecipient_,
        string memory name_,
        string memory symbol_
    ) ERC4626(IERC20(asset_)) ERC20(name_, symbol_) {
        if (asset_ == address(0) || sale_ == address(0)) revert InvalidAddress();
        if (treasury_ == address(0)) revert InvalidAddress();
        if (platformFeeRecipient_ == address(0)) revert InvalidAddress();
        if (platformFeeBps_ >= BPS) revert InvalidAmount();
        SALE = sale_;
        TREASURY = treasury_;
        PLATFORM_FEE_BPS = platformFeeBps_;
        PLATFORM_FEE_RECIPIENT = platformFeeRecipient_;
    }

    /// @notice Bootstrap vault assets and mint fixed supply once.
    function bootstrap(uint256 assets, address receiver) external returns (uint256 shares) {
        if (msg.sender != SALE) revert OnlySale();
        if (bootstrapped) revert AlreadyBootstrapped();
        if (assets == 0 || receiver == address(0)) revert InvalidAmount();

        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);
        shares = TOKEN_FIXED_SUPPLY;
        _mint(receiver, shares);
        bootstrapped = true;

        emit Bootstrapped(assets, shares);
    }

    /// @notice Called by the Sale contract after successful bootstrap to lock setup actions.
    function completeSale() external {
        if (msg.sender != SALE) revert OnlySale();
        if (!bootstrapped) revert NotBootstrapped();
        if (saleCompleted) revert SaleAlreadyCompleted();
        saleCompleted = true;
        emit SaleCompleted();
    }

    /// @notice Distribute profits from the treasury into the vault and take platform fee.
    ///         Caller must be the treasury (Safe) and must approve this vault to pull funds.
    function distributeProfits(uint256 grossAmount) external {
        if (msg.sender != TREASURY) revert OnlyTreasury();
        if (grossAmount == 0) revert InvalidAmount();

        uint256 feeAmount = (grossAmount * PLATFORM_FEE_BPS) / BPS;
        uint256 netAmount = grossAmount - feeAmount;

        if (feeAmount > 0) {
            IERC20(asset()).safeTransferFrom(msg.sender, PLATFORM_FEE_RECIPIENT, feeAmount);
        }
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), netAmount);

        emit ProfitsDistributed(grossAmount, feeAmount, netAmount);
    }

    /// @notice Returns fixed 18 decimals for share tokens.
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    // ─── ERC-4626 overrides ──────────────────────────────────────────────

    /// @dev Deposits are disabled to enforce fixed-supply share issuance.
    function deposit(uint256, address) public pure override returns (uint256) {
        revert DepositDisabled();
    }

    /// @dev Mint is disabled; shares are only created via deposit().
    function mint(uint256, address) public pure override returns (uint256) {
        revert MintDisabled();
    }

    // withdraw() and redeem() are inherited without restriction — shareholders
    // can exit at any time by burning shares in exchange for their collateral share.
}
