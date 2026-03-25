// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract SafeModuleSetup {
    error InvalidModule();
    error ModuleEnableFailed();

    function enableModules(address[] calldata modules) external {
        for (uint256 i = 0; i < modules.length; i++) {
            _enableModule(modules[i]);
        }
    }

    function _enableModule(address module) internal {
        if (module == address(0) || module == address(0x1)) revert InvalidModule();
        (bool success,) = address(this).call(abi.encodeWithSignature("enableModule(address)", module));
        if (!success) revert ModuleEnableFailed();
    }
}
