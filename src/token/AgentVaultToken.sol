// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BPS} from "../Constants.sol";

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
    uint256 public immutable LOCKUP_END_TIME;
    uint8 internal immutable _assetDecimals;

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
    error InvalidAssetBehavior();
    error LockupActive(uint256 lockupEndTime);

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
        uint256 lockupEndTime_,
        string memory name_,
        string memory symbol_
    ) ERC4626(IERC20(asset_)) ERC20(name_, symbol_) {
        if (asset_ == address(0) || sale_ == address(0)) {
            revert InvalidAddress();
        }
        if (treasury_ == address(0)) revert InvalidAddress();
        if (platformFeeRecipient_ == address(0)) revert InvalidAddress();
        if (platformFeeBps_ >= BPS) revert InvalidAmount();
        SALE = sale_;
        TREASURY = treasury_;
        PLATFORM_FEE_BPS = platformFeeBps_;
        PLATFORM_FEE_RECIPIENT = platformFeeRecipient_;
        LOCKUP_END_TIME = lockupEndTime_;
        _assetDecimals = IERC20Metadata(asset_).decimals();
    }

    /// @notice Bootstrap vault assets and mint initial shares at a 1:1 asset price.
    function bootstrap(uint256 assets, address receiver) external returns (uint256 shares) {
        if (msg.sender != SALE) revert OnlySale();
        if (bootstrapped) revert AlreadyBootstrapped();
        if (assets == 0 || receiver == address(0)) revert InvalidAmount();

        shares = previewDeposit(assets);
        if (shares == 0) revert InvalidAmount();
        uint256 balanceBefore = IERC20(asset()).balanceOf(address(this));
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);
        uint256 received = IERC20(asset()).balanceOf(address(this)) - balanceBefore;
        if (received != assets) revert InvalidAssetBehavior();
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
        uint256 vaultBalanceBefore = IERC20(asset()).balanceOf(address(this));

        if (feeAmount > 0) {
            uint256 recipientBalanceBefore = IERC20(asset()).balanceOf(PLATFORM_FEE_RECIPIENT);
            IERC20(asset()).safeTransferFrom(msg.sender, PLATFORM_FEE_RECIPIENT, feeAmount);
            uint256 recipientReceived =
                IERC20(asset()).balanceOf(PLATFORM_FEE_RECIPIENT) - recipientBalanceBefore;
            if (recipientReceived != feeAmount) revert InvalidAssetBehavior();
        }
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), netAmount);
        uint256 vaultReceived = IERC20(asset()).balanceOf(address(this)) - vaultBalanceBefore;
        if (vaultReceived != netAmount) revert InvalidAssetBehavior();

        emit ProfitsDistributed(grossAmount, feeAmount, netAmount);
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        if (block.timestamp < LOCKUP_END_TIME) return 0;
        return super.maxWithdraw(owner);
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        if (block.timestamp < LOCKUP_END_TIME) return 0;
        return super.maxRedeem(owner);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        returns (uint256)
    {
        _revertIfLockupActive();
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        returns (uint256)
    {
        _revertIfLockupActive();
        return super.redeem(shares, receiver, owner);
    }

    /// @notice Backward-compatible alias kept for older integrations.
    function REDEEM_UNLOCK_TIME() external view returns (uint256) {
        return LOCKUP_END_TIME;
    }

    /// @notice Returns fixed 18 decimals for share tokens when collateral is <= 18 decimals.
    function decimals() public view override returns (uint8) {
        if (_assetDecimals >= 18) return _assetDecimals;
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

    function _decimalsOffset() internal view override returns (uint8) {
        if (_assetDecimals >= 18) return 0;
        return 18 - _assetDecimals;
    }

    function _revertIfLockupActive() internal view {
        if (block.timestamp < LOCKUP_END_TIME) {
            revert LockupActive(LOCKUP_END_TIME);
        }
    }
}
