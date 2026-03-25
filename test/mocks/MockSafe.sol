// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ISafe} from "../../src/interfaces/ISafe.sol";

contract MockSafe is ISafe {
    bool public lastSuccess = true;

    function setSuccess(bool success_) external {
        lastSuccess = success_;
    }

    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation
    ) external override returns (bool success) {
        if (!lastSuccess) return false;
        if (to.code.length > 0 && data.length > 0) {
            if (operation == Operation.Call) {
                (success,) = to.call{value: value}(data);
            } else {
                (success,) = to.delegatecall(data);
            }
        } else {
            success = true;
        }
    }

    function execTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation
    ) external override returns (bool success, bytes memory returnData) {
        if (!lastSuccess) return (false, "");
        if (to.code.length > 0 && data.length > 0) {
            if (operation == Operation.Call) {
                (success, returnData) = to.call{value: value}(data);
            } else {
                (success, returnData) = to.delegatecall(data);
            }
        } else {
            success = true;
        }
    }

    function enableModule(address) external override {}

    function disableModule(address, address) external override {}

    function isModuleEnabled(address) external pure override returns (bool) {
        return true;
    }

    function getModulesPaginated(address, uint256) external pure override returns (address[] memory array, address next) {
        array = new address[](0);
        next = address(0);
    }

    receive() external payable {}
}
