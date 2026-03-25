// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {DexRegistry} from "../../src/registry/DexRegistry.sol";
import {IDexRegistry} from "../../src/interfaces/IDexRegistry.sol";

contract DexRegistryTest is Test {
    DexRegistry internal registry;
    address internal admin;
    address internal user;

    address internal v3FactoryA = makeAddr("v3FactoryA");
    address internal positionMgrA = makeAddr("positionMgrA");
    address internal swapRouterA = makeAddr("swapRouterA");
    address internal v3FactoryB = makeAddr("v3FactoryB");
    address internal positionMgrB = makeAddr("positionMgrB");
    address internal swapRouterB = makeAddr("swapRouterB");

    function setUp() public {
        admin = address(this);
        user = makeAddr("user");
        registry = new DexRegistry();
    }

    function test_AddDex() public {
        uint256 id = registry.addDex(v3FactoryA, positionMgrA, swapRouterA);
        assertEq(id, 0);
        assertEq(registry.dexCount(), 1);

        IDexRegistry.DexConfig memory dex = registry.getDex(0);
        assertEq(dex.v3Factory, v3FactoryA);
        assertEq(dex.positionManager, positionMgrA);
        assertEq(dex.swapRouter, swapRouterA);
        assertTrue(dex.active);
    }

    function test_AddMultipleDexes() public {
        uint256 idA = registry.addDex(v3FactoryA, positionMgrA, swapRouterA);
        uint256 idB = registry.addDex(v3FactoryB, positionMgrB, swapRouterB);
        assertEq(idA, 0);
        assertEq(idB, 1);
        assertEq(registry.dexCount(), 2);

        IDexRegistry.DexConfig memory dexB = registry.getDex(1);
        assertEq(dexB.v3Factory, v3FactoryB);
    }

    function test_DeactivateDex() public {
        registry.addDex(v3FactoryA, positionMgrA, swapRouterA);
        registry.deactivateDex(0);

        vm.expectRevert(IDexRegistry.DexNotActive.selector);
        registry.getDex(0);
    }

    function test_RevertDeactivateDex_AlreadyInactive() public {
        registry.addDex(v3FactoryA, positionMgrA, swapRouterA);
        registry.deactivateDex(0);

        vm.expectRevert(IDexRegistry.DexAlreadyInactive.selector);
        registry.deactivateDex(0);
    }

    function test_RevertDeactivateDex_NotFound() public {
        vm.expectRevert(IDexRegistry.DexNotFound.selector);
        registry.deactivateDex(99);
    }

    function test_RevertAddDex_NotAdmin() public {
        vm.prank(user);
        vm.expectRevert(IDexRegistry.Unauthorized.selector);
        registry.addDex(v3FactoryA, positionMgrA, swapRouterA);
    }

    function test_RevertAddDex_ZeroAddress() public {
        vm.expectRevert(IDexRegistry.InvalidAddress.selector);
        registry.addDex(address(0), positionMgrA, swapRouterA);
    }

    function test_RevertGetDex_OutOfBounds() public {
        vm.expectRevert(IDexRegistry.DexNotFound.selector);
        registry.getDex(99);
    }
}
