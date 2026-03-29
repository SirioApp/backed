// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {AgentExecutor} from "../../src/agents/AgentExecutor.sol";
import {ContractAllowlist} from "../../src/registry/ContractAllowlist.sol";
import {MockSafe} from "../mocks/MockSafe.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {ISafeModuleSetup} from "../../src/interfaces/ISafe.sol";

contract AgentExecutorTest is Test {
    AgentExecutor internal executor;
    ContractAllowlist internal allowlist;
    MockSafe internal treasury;
    MockERC20 internal token;

    address internal admin = makeAddr("admin");
    address internal agent = makeAddr("agent");
    address internal attacker = makeAddr("attacker");
    address internal target = makeAddr("target");

    function setUp() public {
        allowlist = new ContractAllowlist(admin);
        treasury = new MockSafe();
        token = new MockERC20("TKN", "TKN", 18);

        executor = new AgentExecutor(agent, address(treasury), address(allowlist), admin);

        address[] memory owners = new address[](1);
        owners[0] = admin;
        address[] memory modules = new address[](1);
        modules[0] = address(executor);
        bytes memory setupData =
            abi.encodeWithSelector(ISafeModuleSetup.enableModules.selector, modules);
        treasury.setup(
            owners, 1, address(0), setupData, address(0), address(0), 0, payable(address(0))
        );
    }

    function test_Execute_RevertsNotAgent() public {
        vm.prank(admin);
        allowlist.addContract(target);
        vm.prank(attacker);
        vm.expectRevert(AgentExecutor.Unauthorized.selector);
        executor.execute(target, 0, "");
    }

    function test_Execute_RevertsTargetNotAllowed() public {
        vm.prank(agent);
        vm.expectRevert(AgentExecutor.TargetNotAllowed.selector);
        executor.execute(target, 0, "");
    }

    function test_Execute_RevertsTreasuryTarget() public {
        vm.prank(agent);
        vm.expectRevert(AgentExecutor.TargetNotAllowed.selector);
        executor.execute(address(treasury), 0, "");
    }

    function test_Execute_RevertsAllowlistTarget() public {
        vm.prank(agent);
        vm.expectRevert(AgentExecutor.TargetNotAllowed.selector);
        executor.execute(address(allowlist), 0, "");
    }

    function test_Execute_RevertsExecutorSelf() public {
        vm.prank(admin);
        allowlist.addContract(address(executor));
        vm.prank(agent);
        vm.expectRevert(AgentExecutor.TargetNotAllowed.selector);
        executor.execute(address(executor), 0, "");
    }

    function test_Execute_Success() public {
        vm.prank(admin);
        allowlist.addContract(address(token));
        vm.prank(admin);
        executor.setSelectorAllowed(
            address(token), bytes4(keccak256("transfer(address,uint256)")), true
        );
        token.mint(address(treasury), 1_000e18);

        bytes memory transferCall =
            abi.encodeWithSignature("transfer(address,uint256)", agent, 100e18);
        vm.prank(agent);
        executor.execute(address(token), 0, transferCall);

        assertEq(token.balanceOf(agent), 100e18);
    }

    function test_Immutables() public view {
        assertEq(executor.AGENT(), agent);
        assertEq(executor.TREASURY(), address(treasury));
        assertEq(executor.ADMIN(), admin);
        assertEq(address(executor.ALLOWLIST()), address(allowlist));
    }

    function test_SetAllowlistEnforced_OnlyAdmin() public {
        vm.prank(attacker);
        vm.expectRevert(AgentExecutor.Unauthorized.selector);
        executor.setAllowlistEnforced(false);

        vm.prank(admin);
        executor.setAllowlistEnforced(false);
        assertFalse(executor.allowlistEnforced());

        vm.prank(admin);
        executor.setAllowlistEnforced(true);
        assertTrue(executor.allowlistEnforced());
    }

    function test_Execute_SucceedsWithoutAllowlist_WhenDisabledByAdmin() public {
        token.mint(address(treasury), 1_000e18);

        vm.prank(admin);
        executor.setAllowlistEnforced(false);

        bytes memory transferCall =
            abi.encodeWithSignature("transfer(address,uint256)", agent, 100e18);
        vm.prank(agent);
        executor.execute(address(token), 0, transferCall);

        assertEq(token.balanceOf(agent), 100e18);
    }

    function test_Execute_RevertsSelectorNotAllowed() public {
        vm.prank(admin);
        allowlist.addContract(address(token));
        token.mint(address(treasury), 1_000e18);

        bytes memory transferCall =
            abi.encodeWithSignature("transfer(address,uint256)", agent, 100e18);
        vm.prank(agent);
        vm.expectRevert(AgentExecutor.SelectorNotAllowed.selector);
        executor.execute(address(token), 0, transferCall);
    }

    function test_Execute_RevertsApproveToUnallowlistedSpender() public {
        vm.prank(admin);
        allowlist.addContract(address(token));
        vm.prank(admin);
        executor.setSelectorAllowed(
            address(token), bytes4(keccak256("approve(address,uint256)")), true
        );

        bytes memory approveCall =
            abi.encodeWithSignature("approve(address,uint256)", attacker, type(uint256).max);
        vm.prank(agent);
        vm.expectRevert(AgentExecutor.SpenderNotAllowed.selector);
        executor.execute(address(token), 0, approveCall);
    }

    function test_Execute_AllowsApproveToAllowlistedSpender() public {
        address spender = makeAddr("spender");
        vm.startPrank(admin);
        allowlist.addContract(address(token));
        allowlist.addContract(spender);
        executor.setSelectorAllowed(
            address(token), bytes4(keccak256("approve(address,uint256)")), true
        );
        vm.stopPrank();

        bytes memory approveCall =
            abi.encodeWithSignature("approve(address,uint256)", spender, 123e18);
        vm.prank(agent);
        executor.execute(address(token), 0, approveCall);

        assertEq(token.allowance(address(treasury), spender), 123e18);
    }
}
