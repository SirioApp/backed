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
    mapping(address => mapping(bytes4 => bool)) public isSelectorAllowed;

    bytes4 internal constant APPROVE_SELECTOR = 0x095ea7b3;
    bytes4 internal constant INCREASE_ALLOWANCE_SELECTOR = 0x39509351;
    bytes4 internal constant DECREASE_ALLOWANCE_SELECTOR = 0xa457c2d7;
    bytes4 internal constant SET_APPROVAL_FOR_ALL_SELECTOR = 0xa22cb465;

    event Executed(address indexed target, uint256 value, bytes data);
    event AllowlistEnforcementUpdated(bool enforced);
    event SelectorPolicyUpdated(address indexed target, bytes4 indexed selector, bool allowed);

    error Unauthorized();
    error TargetNotAllowed();
    error SelectorNotAllowed();
    error SpenderNotAllowed();
    error ExecutionFailed();
    error InvalidAddress();
    error InvalidCalldata();

    modifier onlyAgent() {
        _onlyAgent();
        _;
    }

    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    function _onlyAgent() internal view {
        if (msg.sender != AGENT) revert Unauthorized();
    }

    function _onlyAdmin() internal view {
        if (msg.sender != ADMIN) revert Unauthorized();
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

    /// @notice Configure selector-level policy for a specific target.
    function setSelectorAllowed(address target, bytes4 selector, bool allowed) external onlyAdmin {
        if (target == address(0)) revert InvalidAddress();
        isSelectorAllowed[target][selector] = allowed;
        emit SelectorPolicyUpdated(target, selector, allowed);
    }

    /// @notice Batch version of setSelectorAllowed for operational convenience.
    function setSelectorsAllowed(address target, bytes4[] calldata selectors, bool allowed)
        external
        onlyAdmin
    {
        if (target == address(0)) revert InvalidAddress();
        for (uint256 i; i < selectors.length; ++i) {
            isSelectorAllowed[target][selectors[i]] = allowed;
            emit SelectorPolicyUpdated(target, selectors[i], allowed);
        }
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

        if (allowlistEnforced) _enforcePolicy(target, data);

        bool success;
        (success, result) = ISafe(TREASURY)
            .execTransactionFromModuleReturnData(target, value, data, ISafe.Operation.Call);
        if (!success) revert ExecutionFailed();

        emit Executed(target, value, data);
    }

    function _enforcePolicy(address target, bytes calldata data) internal view {
        if (!ALLOWLIST.isAllowed(target)) revert TargetNotAllowed();
        bytes4 selector = _selectorFromData(data);
        if (!isSelectorAllowed[target][selector]) revert SelectorNotAllowed();

        if (_isApprovalSelector(selector)) {
            address spender = _approvalSpender(selector, data);
            if (spender == TREASURY || spender == address(this) || spender == address(ALLOWLIST)) {
                revert SpenderNotAllowed();
            }
            if (!ALLOWLIST.isAllowed(spender)) revert SpenderNotAllowed();
        }
    }

    function _selectorFromData(bytes calldata data) internal pure returns (bytes4 selector) {
        if (data.length < 4) return bytes4(0);
        assembly {
            selector := calldataload(data.offset)
        }
    }

    function _isApprovalSelector(bytes4 selector) internal pure returns (bool) {
        return selector == APPROVE_SELECTOR || selector == INCREASE_ALLOWANCE_SELECTOR
            || selector == DECREASE_ALLOWANCE_SELECTOR || selector == SET_APPROVAL_FOR_ALL_SELECTOR;
    }

    function _approvalSpender(bytes4 selector, bytes calldata data)
        internal
        pure
        returns (address spender)
    {
        if (data.length < 68) revert InvalidCalldata();
        if (selector == SET_APPROVAL_FOR_ALL_SELECTOR) {
            (spender,) = abi.decode(data[4:], (address, bool));
            return spender;
        }
        (spender,) = abi.decode(data[4:], (address, uint256));
    }
}
