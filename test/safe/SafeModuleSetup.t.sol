// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {SafeModuleSetup} from "../../src/safe/SafeModuleSetup.sol";

contract MockSafeForModuleSetup {
    mapping(address => bool) public enabledModules;
    bool public shouldFail;
    
    function enableModule(address module) external {
        if (shouldFail) revert("Module enable failed");
        enabledModules[module] = true;
    }
    
    function setShouldFail(bool fail) external {
        shouldFail = fail;
    }
    
    function isModuleEnabled(address module) external view returns (bool) {
        return enabledModules[module];
    }
}

contract SafeModuleSetupTest is Test {
    /*//////////////////////////////////////////////////////////////
                              CONTRACTS
    //////////////////////////////////////////////////////////////*/

    SafeModuleSetup internal setup;
    MockSafeForModuleSetup internal safe;

    /*//////////////////////////////////////////////////////////////
                                ADDRESSES
    //////////////////////////////////////////////////////////////*/

    address internal module1;
    address internal module2;
    address internal module3;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        setup = new SafeModuleSetup();
        safe = new MockSafeForModuleSetup();
        
        module1 = makeAddr("module1");
        module2 = makeAddr("module2");
        module3 = makeAddr("module3");
    }

    /*//////////////////////////////////////////////////////////////
                      ENABLE MODULES TESTS
    //////////////////////////////////////////////////////////////*/

    function test_EnableModules_RevertIf_ZeroAddress() external {
        address[] memory modules = new address[](1);
        modules[0] = address(0);
        
        vm.expectRevert(SafeModuleSetup.InvalidModule.selector);
        setup.enableModules(modules);
    }

    function test_EnableModules_RevertIf_SentinelAddress() external {
        address[] memory modules = new address[](1);
        modules[0] = address(0x1);
        
        vm.expectRevert(SafeModuleSetup.InvalidModule.selector);
        setup.enableModules(modules);
    }

    function test_EnableModules_RevertIf_EnableFails() external {
        address[] memory modules = new address[](1);
        modules[0] = module1;
        
        vm.expectRevert(SafeModuleSetup.ModuleEnableFailed.selector);
        setup.enableModules(modules);
    }

    function test_EnableModules_EmptyArray_DoesNotRevert() external {
        address[] memory modules = new address[](0);
        
        setup.enableModules(modules);
    }

    function test_EnableModules_ValidModulesArray_ValidatesAll() external {
        address[] memory modules = new address[](3);
        modules[0] = module1;
        modules[1] = address(0);
        modules[2] = module3;
        
        vm.expectRevert();
        setup.enableModules(modules);
    }
}
