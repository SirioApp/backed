// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AgentVaultToken} from "../token/AgentVaultToken.sol";
import {ISale, ISaleFactory} from "../interfaces/ISale.sol";
import {BPS} from "../Constants.sol";

/// @title Sale
/// @notice Token Generation Event (TGE) for an agent project.
///
/// Investors commit collateral during the sale window. At finalization (callable by anyone
/// after the window closes), the contract:
///   1. Caps accepted collateral at MAX_RAISE.
///   2. Deploys an AgentVaultToken (ERC-4626) and deposits the accepted proceeds into it,
///      receiving all shares back to this contract.
///   4. Locks the vault against further deposits.
///
/// Investors then call claim() to receive their pro-rata share of vault tokens,
/// plus a collateral refund for any over-committed amount.
///
/// If no funds were committed, or an admin triggers emergencyRefund(), investors
/// can reclaim their full collateral via refund().
contract Sale is ReentrancyGuard, ISale {
    using SafeERC20 for IERC20;

    IERC20 public immutable COLLATERAL;
    address public immutable TREASURY;
    address public immutable FOUNDER;
    ISaleFactory public immutable FACTORY;
    uint256 public immutable PROJECT_ID;
    uint256 public immutable DURATION;
    uint256 public immutable MIN_RAISE;
    uint256 public immutable MAX_RAISE;
    uint16 public immutable PLATFORM_FEE_BPS;
    address public immutable PLATFORM_FEE_RECIPIENT;

    uint256 public startTime;
    uint256 public endTime;
    string public tokenName;
    string public tokenSymbol;

    IERC20 internal _token;
    uint256 public totalCommitted;
    uint256 public acceptedAmount;
    uint256 public totalSharesMinted;
    uint256 public totalRefundedAmount;
    uint256 public participantCount;
    uint256 public claimedCount;
    uint256 public totalAcceptedClaimed;
    uint256 public totalSharesClaimed;
    bool public finalized;
    bool public failed;

    mapping(address => uint256) public commitments;
    mapping(address => bool) public claimed;
    mapping(address => bool) public refunded;

    event Committed(address indexed user, uint256 amount);
    event Finalized(address indexed token, uint256 accepted, uint256 sharesMinted);
    event Claimed(address indexed user, uint256 payoutUsdm, uint256 refund);
    event Refunded(address indexed user, uint256 amount);

    error InvalidAddress();
    error Unauthorized();
    error InvalidParams();
    error NotApproved();
    error NotActive();
    error NotReady();
    error AlreadyFinalized();
    error NothingToClaim();
    error AlreadyClaimed();
    error AlreadyRefunded();
    error RefundNotAvailable();
    error ZeroAmount();
    error InvalidCollateralTransfer();
    error InvalidCollateralBehavior();
    error InvalidConfig();

    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    function _onlyAdmin() internal view {
        if (msg.sender != FACTORY.SUPER_ADMIN()) revert Unauthorized();
    }

    constructor(
        address collateral_,
        address treasury_,
        address founder_,
        uint256 duration_,
        uint256 launchTime_,
        string memory name_,
        string memory symbol_,
        address factory_,
        ISale.SaleConfigSnapshot memory saleConfig_,
        uint256 projectId_
    ) {
        if (collateral_ == address(0)) {
            revert InvalidAddress();
        }
        if (treasury_ == address(0)) revert InvalidAddress();
        if (founder_ == address(0)) revert InvalidAddress();
        if (factory_ == address(0)) revert InvalidAddress();
        if (saleConfig_.minRaise == 0 || saleConfig_.maxRaise == 0) revert InvalidConfig();
        if (saleConfig_.minRaise > saleConfig_.maxRaise) revert InvalidConfig();
        if (saleConfig_.platformFeeBps >= BPS) revert InvalidConfig();
        if (saleConfig_.platformFeeRecipient == address(0)) revert InvalidAddress();

        COLLATERAL = IERC20(collateral_);
        TREASURY = treasury_;
        FOUNDER = founder_;
        FACTORY = ISaleFactory(factory_);
        PROJECT_ID = projectId_;
        DURATION = duration_;
        MIN_RAISE = saleConfig_.minRaise;
        MAX_RAISE = saleConfig_.maxRaise;
        PLATFORM_FEE_BPS = saleConfig_.platformFeeBps;
        PLATFORM_FEE_RECIPIENT = saleConfig_.platformFeeRecipient;
        startTime = launchTime_;
        endTime = launchTime_ + duration_;
        tokenName = name_;
        tokenSymbol = symbol_;
    }

    /// @notice Commit collateral to the sale. Requires project approval and an active sale window.
    /// @param amount Amount of collateral to commit. No individual cap — pro-rata handles excess.
    function commit(uint256 amount) external nonReentrant {
        if (!FACTORY.isProjectApproved(PROJECT_ID)) revert NotApproved();
        if (block.timestamp < startTime || block.timestamp >= endTime) revert NotActive();
        if (finalized) revert AlreadyFinalized();
        if (amount == 0) revert ZeroAmount();

        uint256 balanceBefore = COLLATERAL.balanceOf(address(this));
        COLLATERAL.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = COLLATERAL.balanceOf(address(this)) - balanceBefore;
        if (received == 0) revert InvalidCollateralTransfer();
        if (received != amount) revert InvalidCollateralBehavior();

        if (commitments[msg.sender] == 0) {
            participantCount += 1;
        }
        commitments[msg.sender] += received;
        totalCommitted += received;

        emit Committed(msg.sender, received);
    }

    /// @notice Finalise the sale. Callable by anyone after the sale window closes.
    ///
    /// Accepts up to MAX_RAISE collateral units. Any excess above MAX_RAISE remains in this
    /// contract for pro-rata refunds.
    function finalize() external nonReentrant {
        if (block.timestamp < endTime) revert NotReady();
        if (finalized) revert AlreadyFinalized();
        finalized = true;

        if (totalCommitted == 0) {
            failed = true;
            emit Finalized(address(0), 0, 0);
            return;
        }

        acceptedAmount = totalCommitted > MAX_RAISE ? MAX_RAISE : totalCommitted;
        if (acceptedAmount < MIN_RAISE) {
            failed = true;
            emit Finalized(address(0), acceptedAmount, 0);
            return;
        }

        AgentVaultToken vault = new AgentVaultToken(
            address(COLLATERAL),
            address(this),
            TREASURY,
            PLATFORM_FEE_BPS,
            PLATFORM_FEE_RECIPIENT,
            tokenName,
            tokenSymbol
        );
        _token = IERC20(address(vault));

        COLLATERAL.forceApprove(address(vault), acceptedAmount);
        uint256 shares = vault.bootstrap(acceptedAmount, address(this));
        totalSharesMinted = shares;

        vault.completeSale();

        emit Finalized(address(vault), acceptedAmount, shares);
    }

    /// @notice Claim pro-rata vault shares after successful finalization.
    ///
    /// Each investor receives transfer of pro-rata vault shares and any overflow refund.
    function claim() external nonReentrant {
        if (!finalized || failed || acceptedAmount == 0) revert NotReady();
        if (claimed[msg.sender]) revert AlreadyClaimed();

        uint256 committed = commitments[msg.sender];
        if (committed == 0) revert NothingToClaim();

        claimed[msg.sender] = true;

        bool isLastClaimer = claimedCount + 1 == participantCount;
        uint256 accepted;
        if (isLastClaimer) {
            accepted = acceptedAmount - totalAcceptedClaimed;
        } else {
            accepted = totalCommitted > MAX_RAISE
                ? (committed * acceptedAmount) / totalCommitted
                : committed;
        }
        if (accepted > committed) accepted = committed;

        uint256 shares = isLastClaimer
            ? totalSharesMinted - totalSharesClaimed
            : (accepted * totalSharesMinted) / acceptedAmount;
        uint256 payoutShares = shares;
        uint256 refundAmt = committed - accepted;
        if (payoutShares > 0) {
            _token.safeTransfer(msg.sender, payoutShares);
        }

        totalAcceptedClaimed += accepted;
        totalSharesClaimed += payoutShares;
        claimedCount += 1;

        if (refundAmt > 0) {
            uint256 overflow = totalCommitted - acceptedAmount;
            uint256 remainingOverflow = overflow - totalRefundedAmount;
            if (refundAmt > remainingOverflow) refundAmt = remainingOverflow;
            if (refundAmt > 0) {
                totalRefundedAmount += refundAmt;
                COLLATERAL.safeTransfer(msg.sender, refundAmt);
            }
        }

        emit Claimed(msg.sender, payoutShares, refundAmt);
    }

    /// @notice Reclaim full collateral commitment when the sale failed.
    function refund() external nonReentrant {
        if (!finalized || !failed) revert RefundNotAvailable();
        if (refunded[msg.sender]) revert AlreadyRefunded();

        uint256 committed = commitments[msg.sender];
        if (committed == 0) revert NothingToClaim();

        refunded[msg.sender] = true;
        COLLATERAL.safeTransfer(msg.sender, committed);

        emit Refunded(msg.sender, committed);
    }

    /// @notice Admin-only emergency: mark the sale as failed so investors can refund.
    ///         Callable at any time before finalization.
    function emergencyRefund() external nonReentrant onlyAdmin {
        if (finalized) revert AlreadyFinalized();
        finalized = true;
        failed = true;
        emit Finalized(address(0), 0, 0);
    }

    // ─── View ────────────────────────────────────────────────────────────

    function getClaimable(address user)
        external
        view
        returns (uint256 payoutShares, uint256 refundAmt)
    {
        if (!finalized || failed || acceptedAmount == 0 || commitments[user] == 0 || claimed[user])
        {
            return (0, 0);
        }
        uint256 committed = commitments[user];
        bool isLastClaimer = claimedCount + 1 == participantCount;
        uint256 accepted = isLastClaimer
            ? acceptedAmount - totalAcceptedClaimed
            : (totalCommitted > MAX_RAISE
                    ? (committed * acceptedAmount) / totalCommitted
                    : committed);
        if (accepted > committed) accepted = committed;
        payoutShares = isLastClaimer
            ? totalSharesMinted - totalSharesClaimed
            : (accepted * totalSharesMinted) / acceptedAmount;
        refundAmt = committed - accepted;
        if (refundAmt > 0) {
            uint256 overflow = totalCommitted - acceptedAmount;
            uint256 remainingOverflow = overflow - totalRefundedAmount;
            if (refundAmt > remainingOverflow) refundAmt = remainingOverflow;
        }
    }

    function token() external view returns (address) {
        return address(_token);
    }

    function getRefundable(address user) external view returns (uint256) {
        return (finalized && failed && !refunded[user]) ? commitments[user] : 0;
    }

    function isActive() external view returns (bool) {
        return
            startTime > 0 && block.timestamp >= startTime && block.timestamp < endTime && !finalized;
    }

    function timeRemaining() external view returns (uint256) {
        return block.timestamp >= endTime ? 0 : endTime - block.timestamp;
    }

    function getStatus() external view returns (uint256, uint256, bool, bool) {
        return (totalCommitted, acceptedAmount, finalized, failed);
    }
}
