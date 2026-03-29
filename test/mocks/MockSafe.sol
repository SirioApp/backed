// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {
    ISafe,
    ISafeSetup,
    ISafeModuleSetup,
    SENTINEL_MODULES
} from "../../src/interfaces/ISafe.sol";

contract MockSafe is ISafe, ISafeSetup {
    bool public lastSuccess = true;
    bool public initialized;
    address public owner;
    mapping(address => bool) internal _enabledModules;
    address[] internal _modules;

    error UnauthorizedModule();
    error UnauthorizedSelfCall();
    error AlreadyInitialized();
    error InvalidModule();

    function setup(
        address[] calldata owners,
        uint256 threshold,
        address,
        bytes calldata data,
        address,
        address,
        uint256,
        address payable
    ) external {
        if (initialized) revert AlreadyInitialized();
        if (owners.length == 0 || threshold == 0 || threshold > owners.length) {
            revert InvalidModule();
        }
        initialized = true;
        owner = owners[0];

        if (data.length >= 4) {
            bytes4 selector;
            assembly {
                selector := calldataload(data.offset)
            }
            if (selector == ISafeModuleSetup.enableModules.selector) {
                address[] memory modules = abi.decode(data[4:], (address[]));
                for (uint256 i; i < modules.length; ++i) {
                    _enableModule(modules[i]);
                }
            }
        }
    }

    function setSuccess(bool success_) external {
        lastSuccess = success_;
    }

    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation
    ) external override returns (bool success) {
        if (!_enabledModules[msg.sender]) revert UnauthorizedModule();
        if (!lastSuccess) return false;
        if (operation == Operation.Call) {
            (success,) = to.call{value: value}(data);
        } else {
            (success,) = to.delegatecall(data);
        }
    }

    function execTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation
    ) external override returns (bool success, bytes memory returnData) {
        if (!_enabledModules[msg.sender]) revert UnauthorizedModule();
        if (!lastSuccess) return (false, "");
        if (operation == Operation.Call) {
            (success, returnData) = to.call{value: value}(data);
        } else {
            (success, returnData) = to.delegatecall(data);
        }
    }

    function enableModule(address module) external override {
        if (msg.sender != address(this)) revert UnauthorizedSelfCall();
        _enableModule(module);
    }

    function disableModule(address, address module) external override {
        if (msg.sender != address(this)) revert UnauthorizedSelfCall();
        if (!_enabledModules[module]) revert InvalidModule();
        _enabledModules[module] = false;
        uint256 length = _modules.length;
        for (uint256 i; i < length; ++i) {
            if (_modules[i] == module) {
                _modules[i] = _modules[length - 1];
                _modules.pop();
                break;
            }
        }
    }

    function isModuleEnabled(address module) external view override returns (bool) {
        return _enabledModules[module];
    }

    function getModulesPaginated(address, uint256)
        external
        view
        override
        returns (address[] memory array, address next)
    {
        array = _modules;
        next = address(0);
    }

    function _enableModule(address module) internal {
        if (module == address(0) || module == SENTINEL_MODULES) revert InvalidModule();
        if (_enabledModules[module]) return;
        _enabledModules[module] = true;
        _modules.push(module);
    }

    receive() external payable {}
}
