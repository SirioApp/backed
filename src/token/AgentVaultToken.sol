// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {BPS} from "../Constants.sol";

/// @title AgentVaultToken
/// @notice Fixed-supply fund share token for an agent raise.
///
/// The accepted raise capital lives in the project treasury and is operated through
/// AgentExecutor. This token only tracks investor ownership during the fund term and,
/// once the treasury unwinds back into the collateral asset, distributes that asset
/// pro-rata when settlement is finalized.
contract AgentVaultToken is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 internal immutable _asset;

    address public immutable SALE;
    address public immutable TREASURY;
    uint16 public immutable PLATFORM_FEE_BPS;
    address public immutable PLATFORM_FEE_RECIPIENT;
    uint256 public immutable LOCKUP_END_TIME;
    uint8 internal immutable _assetDecimals;

    uint256 public initialAssets;
    uint256 public settledAssets;
    uint256 public settledShareSupply;
    bool public bootstrapped;
    bool public saleCompleted;
    bool public settled;

    event Bootstrapped(uint256 assets, uint256 shares);
    event SaleCompleted();
    event SettlementFinalized(uint256 grossAssets, uint256 feeAmount, uint256 netAssets);
    event Redeemed(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    error InvalidAddress();
    error InvalidAmount();
    error NotBootstrapped();
    error AlreadyBootstrapped();
    error OnlySale();
    error OnlyTreasury();
    error SaleAlreadyCompleted();
    error SettlementAlreadyFinalized();
    error SettlementNotFinalized();
    error LockupActive(uint256 lockupEndTime);

    constructor(
        address asset_,
        address sale_,
        address treasury_,
        uint16 platformFeeBps_,
        address platformFeeRecipient_,
        uint256 lockupEndTime_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        if (asset_ == address(0) || sale_ == address(0)) revert InvalidAddress();
        if (treasury_ == address(0)) revert InvalidAddress();
        if (platformFeeRecipient_ == address(0)) revert InvalidAddress();
        if (platformFeeBps_ >= BPS) revert InvalidAmount();

        _asset = IERC20(asset_);
        SALE = sale_;
        TREASURY = treasury_;
        PLATFORM_FEE_BPS = platformFeeBps_;
        PLATFORM_FEE_RECIPIENT = platformFeeRecipient_;
        LOCKUP_END_TIME = lockupEndTime_;
        _assetDecimals = IERC20Metadata(asset_).decimals();
    }

    function asset() external view returns (address) {
        return address(_asset);
    }

    function TERM_END_TIME() external view returns (uint256) {
        return LOCKUP_END_TIME;
    }

    /// @notice Backward-compatible alias kept for older integrations.
    function REDEEM_UNLOCK_TIME() external view returns (uint256) {
        return LOCKUP_END_TIME;
    }

    /// @notice Mint the fixed fund share supply at the close of the raise.
    function bootstrap(uint256 assets, address receiver) external returns (uint256 shares) {
        if (msg.sender != SALE) revert OnlySale();
        if (bootstrapped) revert AlreadyBootstrapped();
        if (assets == 0 || receiver == address(0)) revert InvalidAmount();

        shares = _assetsToShares(assets);
        if (shares == 0) revert InvalidAmount();

        bootstrapped = true;
        initialAssets = assets;
        _mint(receiver, shares);

        emit Bootstrapped(assets, shares);
    }

    function completeSale() external {
        if (msg.sender != SALE) revert OnlySale();
        if (!bootstrapped) revert NotBootstrapped();
        if (saleCompleted) revert SaleAlreadyCompleted();
        saleCompleted = true;
        emit SaleCompleted();
    }

    /// @notice Treasury finalizes settlement after unwinding back into the collateral asset.
    ///
    /// The treasury must transfer the final gross asset amount to this contract before
    /// calling this function. Platform fees, if any, are taken only on positive profits.
    function finalizeSettlement() external nonReentrant {
        if (msg.sender != TREASURY) revert OnlyTreasury();
        if (!saleCompleted) revert NotBootstrapped();
        if (settled) revert SettlementAlreadyFinalized();
        _revertIfLockupActive();

        uint256 grossAssets = _asset.balanceOf(address(this));
        uint256 feeAmount;
        if (grossAssets > initialAssets && PLATFORM_FEE_BPS > 0) {
            uint256 profit = grossAssets - initialAssets;
            feeAmount = (profit * PLATFORM_FEE_BPS) / BPS;
            if (feeAmount > 0) {
                _asset.safeTransfer(PLATFORM_FEE_RECIPIENT, feeAmount);
            }
        }

        settledAssets = grossAssets - feeAmount;
        settledShareSupply = totalSupply();
        settled = true;

        emit SettlementFinalized(grossAssets, feeAmount, settledAssets);
    }

    function totalAssets() public view returns (uint256) {
        return settled ? settledAssets : 0;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        if (!settled || shares == 0) return 0;
        uint256 supply = totalSupply();
        if (supply == 0) return 0;
        if (shares >= supply) return settledAssets;
        return (shares * settledAssets) / supply;
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        return convertToAssets(shares);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        if (!settled || assets == 0) return 0;
        uint256 supply = totalSupply();
        uint256 assetsAvailable = settledAssets;
        if (supply == 0 || assetsAvailable == 0) return 0;
        if (assets >= assetsAvailable) return supply;
        return _ceilDiv(assets * supply, assetsAvailable);
    }

    function maxRedeem(address owner) public view returns (uint256) {
        if (!_redemptionsOpen()) return 0;
        return balanceOf(owner);
    }

    function maxWithdraw(address owner) public view returns (uint256) {
        if (!_redemptionsOpen()) return 0;
        return convertToAssets(balanceOf(owner));
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        nonReentrant
        returns (uint256 assets)
    {
        _requireRedemptionsOpen();
        if (shares == 0) revert InvalidAmount();

        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, shares);
        }

        assets = _previewRedeemForState(shares);
        _burn(owner, shares);

        if (assets > 0) {
            settledAssets -= assets;
            _asset.safeTransfer(receiver, assets);
        }

        emit Redeemed(msg.sender, receiver, owner, assets, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        nonReentrant
        returns (uint256 shares)
    {
        _requireRedemptionsOpen();
        if (assets == 0) revert InvalidAmount();

        shares = previewWithdraw(assets);
        if (shares == 0) revert InvalidAmount();

        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, shares);
        }

        uint256 payoutAssets = _previewRedeemForState(shares);
        _burn(owner, shares);

        if (payoutAssets > 0) {
            settledAssets -= payoutAssets;
            _asset.safeTransfer(receiver, payoutAssets);
        }

        emit Redeemed(msg.sender, receiver, owner, payoutAssets, shares);
    }

    function decimals() public view override returns (uint8) {
        if (_assetDecimals >= 18) return _assetDecimals;
        return 18;
    }

    function _previewRedeemForState(uint256 shares) internal view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 0;
        if (shares >= supply) return settledAssets;
        return (shares * settledAssets) / supply;
    }

    function _assetsToShares(uint256 assets) internal view returns (uint256) {
        if (_assetDecimals >= 18) return assets;
        return assets * (10 ** (18 - _assetDecimals));
    }

    function _redemptionsOpen() internal view returns (bool) {
        return settled && block.timestamp >= LOCKUP_END_TIME;
    }

    function _requireRedemptionsOpen() internal view {
        _revertIfLockupActive();
        if (!settled) revert SettlementNotFinalized();
    }

    function _revertIfLockupActive() internal view {
        if (block.timestamp < LOCKUP_END_TIME) revert LockupActive(LOCKUP_END_TIME);
    }

    function _ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return a == 0 ? 0 : ((a - 1) / b) + 1;
    }
}
