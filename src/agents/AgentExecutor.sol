// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ContractAllowlist} from "../registry/ContractAllowlist.sol";
import {ISafe} from "../interfaces/ISafe.sol";

/// @title AgentExecutor
/// @notice Gnosis Safe module that grants a single agent wallet the ability to execute
///         arbitrary calls originating from the Safe treasury, subject to an on-chain
///         allowlist enforced by the platform superadmin.
///
/// Security model (ERC-7710-style policy enforcement):
///   - Only the immutable AGENT address may trigger execution.
///   - The call target must exist in the ContractAllowlist; only the superadmin can
///     extend or shrink that list.
///   - The treasury address itself, this module, and the allowlist registry are
///     hard-blocked as targets to prevent self-referential or privilege-escalation calls.
///   - DelegateCall is never used; only Call operations are forwarded.
///   - Reentrancy is blocked via OpenZeppelin's ReentrancyGuard.
///
/// All operations ultimately originate from the Safe (treasury), so asset custody
/// remains with the Safe at all times.
contract AgentExecutor is ReentrancyGuard {
    address public immutable AGENT;
    address public immutable TREASURY;
    address public immutable ADMIN;
    ContractAllowlist public immutable ALLOWLIST;
    bool public allowlistEnforced;

    event Executed(address indexed target, uint256 value, bytes data);
    event AllowlistEnforcementUpdated(bool enforced);

    error Unauthorized();
    error TargetNotAllowed();
    error ExecutionFailed();
    error InvalidAddress();

    modifier onlyAgent() {
        if (msg.sender != AGENT) revert Unauthorized();
        _;
    }

    modifier onlyAdmin() {
        if (msg.sender != ADMIN) revert Unauthorized();
        _;
    }

    constructor(address agent_, address treasury_, address allowlist_, address admin_) {
        if (agent_ == address(0)) revert InvalidAddress();
        if (treasury_ == address(0)) revert InvalidAddress();
        if (allowlist_ == address(0)) revert InvalidAddress();
        if (admin_ == address(0)) revert InvalidAddress();
        AGENT = agent_;
        TREASURY = treasury_;
        ALLOWLIST = ContractAllowlist(allowlist_);
        ADMIN = admin_;
        allowlistEnforced = true;
    }

    /// @notice Enables/disables allowlist checks for treasury execution.
    /// @dev When disabled, agent can call any target except hard-blocked addresses.
    function setAllowlistEnforced(bool enforced) external onlyAdmin {
        allowlistEnforced = enforced;
        emit AllowlistEnforcementUpdated(enforced);
    }

    /// @notice Execute a call from the Safe treasury to an allowlisted target.
    /// @param target   Contract to call. Must be in the ContractAllowlist.
    /// @param value    ETH value forwarded with the call (paid from the Safe balance).
    /// @param data     Calldata to forward.
    /// @return result  Return data from the target call.
    function execute(address target, uint256 value, bytes calldata data)
        external
        nonReentrant
        onlyAgent
        returns (bytes memory result)
    {
        if (target == TREASURY || target == address(this) || target == address(ALLOWLIST)) revert TargetNotAllowed();

        if (allowlistEnforced && !ALLOWLIST.isAllowed(target)) revert TargetNotAllowed();

        bool success;
        (success, result) = ISafe(TREASURY)
            .execTransactionFromModuleReturnData(target, value, data, ISafe.Operation.Call);
        if (!success) revert ExecutionFailed();

        emit Executed(target, value, data);
    }
}
