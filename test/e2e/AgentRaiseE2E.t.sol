// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {AgentRaiseFactory} from "../../src/agents/AgentRaiseFactory.sol";
import {AgentExecutor} from "../../src/agents/AgentExecutor.sol";
import {Sale} from "../../src/launch/Sale.sol";
import {AgentVaultToken} from "../../src/token/AgentVaultToken.sol";
import {ContractAllowlist} from "../../src/registry/ContractAllowlist.sol";
import {MockIdentityRegistry} from "../mocks/MockIdentityRegistry.sol";
import {MockSafeProxyFactory} from "../mocks/MockSafeProxyFactory.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract ExecutorTarget {
    uint256 public touched;

    function touch() external {
        touched += 1;
    }
}

contract AgentRaiseE2ETest is Test {
    AgentRaiseFactory internal factory;
    ContractAllowlist internal allowlist;
    MockIdentityRegistry internal identityRegistry;
    MockSafeProxyFactory internal safeProxyFactory;
    MockERC20 internal collateral;

    address internal admin = makeAddr("admin");
    address internal agentOwner = makeAddr("agentOwner");
    address internal agentOperator = makeAddr("agentOperator");
    address internal investor1 = makeAddr("investor1");
    address internal investor2 = makeAddr("investor2");
    address internal safeSingleton = makeAddr("safeSingleton");
    address internal safeFallbackHandler = makeAddr("safeFallbackHandler");
    address internal safeModuleSetup = makeAddr("safeModuleSetup");

    uint256 internal constant SALE_DURATION = 3 days;
    bytes4 internal constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));

    function setUp() public {
        identityRegistry = new MockIdentityRegistry();
        safeProxyFactory = new MockSafeProxyFactory();
        allowlist = new ContractAllowlist(admin);
        collateral = new MockERC20("USDM", "USDM", 18);

        factory = new AgentRaiseFactory(
            address(identityRegistry),
            address(safeProxyFactory),
            safeSingleton,
            safeFallbackHandler,
            safeModuleSetup,
            admin,
            address(allowlist),
            address(collateral)
        );

        identityRegistry.register(agentOwner, "ipfs://agent");

        collateral.mint(investor1, 1_000_000e18);
        collateral.mint(investor2, 1_000_000e18);
    }

    function test_E2E_FullLifecycle_TreasuryOperatesAndSettlesInCollateral() public {
        uint256 launchTime = block.timestamp + 1 days;
        uint256 lockupMinutes = 60;

        vm.prank(agentOwner);
        uint256 projectId = factory.createAgentRaise(
            1,
            "Agent Project",
            "E2E flow",
            "defi,ai",
            agentOperator,
            address(collateral),
            SALE_DURATION,
            launchTime,
            lockupMinutes,
            "Agent Fund",
            "AGF"
        );

        vm.prank(admin);
        factory.approveProject(projectId);

        AgentRaiseFactory.AgentProject memory p = factory.getProject(projectId);
        Sale sale = Sale(p.sale);
        AgentExecutor executor = AgentExecutor(p.agentExecutor);

        vm.warp(launchTime + 1);

        vm.startPrank(investor1);
        collateral.approve(address(sale), 3_000e18);
        sale.commit(3_000e18);
        vm.stopPrank();

        vm.startPrank(investor2);
        collateral.approve(address(sale), 2_000e18);
        sale.commit(2_000e18);
        vm.stopPrank();

        vm.warp(sale.endTime() + 1);
        sale.finalize();

        address shareTokenAddr = sale.token();
        AgentVaultToken shareToken = AgentVaultToken(shareTokenAddr);
        assertTrue(shareTokenAddr != address(0));
        assertEq(collateral.balanceOf(p.treasury), 5_000e18);
        assertEq(collateral.balanceOf(address(sale)), 0);
        assertEq(shareToken.totalAssets(), 0);
        assertEq(shareToken.totalSupply(), 5_000e18);
        assertEq(shareToken.LOCKUP_END_TIME(), sale.endTime() + (lockupMinutes * 1 minutes));

        vm.prank(investor1);
        sale.claim();
        vm.prank(investor2);
        sale.claim();

        assertEq(shareToken.balanceOf(investor1), 3_000e18);
        assertEq(shareToken.balanceOf(investor2), 2_000e18);

        vm.startPrank(admin);
        allowlist.addContract(address(collateral));
        allowlist.addContract(shareTokenAddr);
        executor.setSelectorAllowed(address(collateral), TRANSFER_SELECTOR, true);
        executor.setSelectorAllowed(
            shareTokenAddr, AgentVaultToken.finalizeSettlement.selector, true
        );
        vm.stopPrank();

        collateral.mint(p.treasury, 1_000e18);

        vm.warp(shareToken.LOCKUP_END_TIME());
        bytes memory transferCall =
            abi.encodeWithSignature("transfer(address,uint256)", shareTokenAddr, 6_000e18);
        vm.prank(agentOperator);
        executor.execute(address(collateral), 0, transferCall);

        vm.prank(agentOperator);
        executor.execute(
            shareTokenAddr, 0, abi.encodeWithSelector(AgentVaultToken.finalizeSettlement.selector)
        );

        assertTrue(shareToken.settled());
        assertEq(shareToken.totalAssets(), 5_950e18);
        assertEq(collateral.balanceOf(admin), 50e18);
        assertEq(collateral.balanceOf(p.treasury), 0);

        uint256 user1Before = collateral.balanceOf(investor1);
        uint256 user2Before = collateral.balanceOf(investor2);
        uint256 user1Shares = shareToken.balanceOf(investor1);
        uint256 user2Shares = shareToken.balanceOf(investor2);

        vm.prank(investor1);
        uint256 user1Assets = shareToken.redeem(user1Shares, investor1, investor1);
        vm.prank(investor2);
        uint256 user2Assets = shareToken.redeem(user2Shares, investor2, investor2);

        assertEq(user1Assets, 3_570e18);
        assertEq(user2Assets, 2_380e18);
        assertEq(collateral.balanceOf(investor1), user1Before + user1Assets);
        assertEq(collateral.balanceOf(investor2), user2Before + user2Assets);
        assertEq(shareToken.totalAssets(), 0);
    }

    function test_E2E_EmergencyRefundFlow() public {
        uint256 launchTime = block.timestamp + 1 days;
        vm.prank(agentOwner);
        uint256 projectId = factory.createAgentRaise(
            1,
            "Agent Project",
            "Emergency flow",
            "defi",
            agentOperator,
            address(collateral),
            SALE_DURATION,
            launchTime,
            "Agent Fund",
            "AGF"
        );

        vm.prank(admin);
        factory.approveProject(projectId);

        Sale sale = Sale(factory.getProject(projectId).sale);

        vm.warp(launchTime + 1);
        vm.startPrank(investor1);
        collateral.approve(address(sale), 1_200e18);
        sale.commit(1_200e18);
        vm.stopPrank();

        vm.prank(admin);
        sale.emergencyRefund();

        uint256 beforeRefund = collateral.balanceOf(investor1);
        vm.prank(investor1);
        sale.refund();
        assertEq(collateral.balanceOf(investor1), beforeRefund + 1_200e18);
    }

    function test_E2E_AllowlistToggle_ByAdmin() public {
        uint256 launchTime = block.timestamp + 1 days;
        vm.prank(agentOwner);
        uint256 projectId = factory.createAgentRaise(
            1,
            "Agent Project",
            "Allowlist toggle flow",
            "defi",
            agentOperator,
            address(collateral),
            SALE_DURATION,
            launchTime,
            "Agent Fund",
            "AGF"
        );

        AgentExecutor executor = AgentExecutor(factory.getProject(projectId).agentExecutor);
        ExecutorTarget target = new ExecutorTarget();

        vm.prank(agentOperator);
        vm.expectRevert(AgentExecutor.TargetNotAllowed.selector);
        executor.execute(address(target), 0, abi.encodeWithSelector(ExecutorTarget.touch.selector));

        vm.prank(admin);
        executor.setAllowlistEnforced(false);

        vm.prank(agentOperator);
        executor.execute(address(target), 0, abi.encodeWithSelector(ExecutorTarget.touch.selector));
        assertEq(target.touched(), 1);

        vm.prank(admin);
        executor.setAllowlistEnforced(true);

        vm.prank(agentOperator);
        vm.expectRevert(AgentExecutor.TargetNotAllowed.selector);
        executor.execute(address(target), 0, abi.encodeWithSelector(ExecutorTarget.touch.selector));
    }

    function test_E2E_EarlyClaimerStillKeepsProRataSettlementUpside() public {
        uint256 launchTime = block.timestamp + 1 days;
        uint256 lockupMinutes = 15;

        vm.prank(agentOwner);
        uint256 projectId = factory.createAgentRaise(
            1,
            "Agent Project",
            "claim fairness flow",
            "defi,ai",
            agentOperator,
            address(collateral),
            SALE_DURATION,
            launchTime,
            lockupMinutes,
            "Agent Fund",
            "AGF"
        );
        vm.prank(admin);
        factory.approveProject(projectId);

        AgentRaiseFactory.AgentProject memory p = factory.getProject(projectId);
        Sale sale = Sale(p.sale);
        AgentExecutor executor = AgentExecutor(p.agentExecutor);

        vm.warp(launchTime + 1);
        _commit(investor1, sale, 3_000e18);
        _commit(investor2, sale, 3_000e18);

        vm.warp(sale.endTime() + 1);
        sale.finalize();
        AgentVaultToken shareToken = AgentVaultToken(sale.token());

        vm.prank(investor1);
        sale.claim();
        assertEq(shareToken.balanceOf(investor1), 3_000e18);

        vm.startPrank(admin);
        allowlist.addContract(address(collateral));
        allowlist.addContract(address(shareToken));
        executor.setSelectorAllowed(address(collateral), TRANSFER_SELECTOR, true);
        executor.setSelectorAllowed(
            address(shareToken), AgentVaultToken.finalizeSettlement.selector, true
        );
        vm.stopPrank();

        collateral.mint(p.treasury, 1_000e18);

        vm.prank(investor2);
        sale.claim();
        assertEq(shareToken.balanceOf(investor2), 3_000e18);

        vm.warp(shareToken.LOCKUP_END_TIME());
        vm.prank(agentOperator);
        executor.execute(
            address(collateral),
            0,
            abi.encodeWithSignature("transfer(address,uint256)", address(shareToken), 7_000e18)
        );
        vm.prank(agentOperator);
        executor.execute(
            address(shareToken), 0, abi.encodeWithSelector(AgentVaultToken.finalizeSettlement.selector)
        );

        uint256 user1Before = collateral.balanceOf(investor1);
        uint256 user2Before = collateral.balanceOf(investor2);
        uint256 user1Shares = shareToken.balanceOf(investor1);
        uint256 user2Shares = shareToken.balanceOf(investor2);

        vm.prank(investor1);
        uint256 user1Assets = shareToken.redeem(user1Shares, investor1, investor1);
        vm.prank(investor2);
        uint256 user2Assets = shareToken.redeem(user2Shares, investor2, investor2);

        assertEq(user1Assets, 3_475e18);
        assertEq(user2Assets, 3_475e18);
        assertEq(collateral.balanceOf(investor1), user1Before + user1Assets);
        assertEq(collateral.balanceOf(investor2), user2Before + user2Assets);
    }

    function test_E2E_RedemptionLockedUntilSettlementWindowOpens() public {
        uint256 launchTime = block.timestamp + 1 days;
        uint256 lockupMinutes = 60;
        vm.prank(agentOwner);
        uint256 projectId = factory.createAgentRaise(
            1,
            "Locked Agent Project",
            "lockup flow",
            "defi",
            agentOperator,
            address(collateral),
            SALE_DURATION,
            launchTime,
            lockupMinutes,
            "Locked Fund",
            "LCK"
        );

        vm.prank(admin);
        factory.approveProject(projectId);

        AgentRaiseFactory.AgentProject memory p = factory.getProject(projectId);
        Sale sale = Sale(p.sale);
        AgentExecutor executor = AgentExecutor(p.agentExecutor);

        vm.warp(launchTime + 1);
        _commit(investor1, sale, 3_000e18);

        vm.warp(sale.endTime() + 1);
        sale.finalize();

        AgentVaultToken shareToken = AgentVaultToken(sale.token());
        vm.prank(investor1);
        sale.claim();

        vm.prank(investor1);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgentVaultToken.LockupActive.selector, shareToken.LOCKUP_END_TIME()
            )
        );
        shareToken.redeem(3_000e18, investor1, investor1);

        vm.startPrank(admin);
        allowlist.addContract(address(collateral));
        allowlist.addContract(address(shareToken));
        executor.setSelectorAllowed(address(collateral), TRANSFER_SELECTOR, true);
        executor.setSelectorAllowed(
            address(shareToken), AgentVaultToken.finalizeSettlement.selector, true
        );
        vm.stopPrank();

        vm.warp(shareToken.LOCKUP_END_TIME());

        vm.prank(investor1);
        vm.expectRevert(AgentVaultToken.SettlementNotFinalized.selector);
        shareToken.redeem(3_000e18, investor1, investor1);

        vm.prank(agentOperator);
        executor.execute(
            address(collateral),
            0,
            abi.encodeWithSignature("transfer(address,uint256)", address(shareToken), 3_000e18)
        );
        vm.prank(agentOperator);
        executor.execute(
            address(shareToken), 0, abi.encodeWithSelector(AgentVaultToken.finalizeSettlement.selector)
        );

        uint256 before = collateral.balanceOf(investor1);
        uint256 shares = shareToken.balanceOf(investor1);
        vm.prank(investor1);
        shareToken.redeem(shares, investor1, investor1);
        assertEq(collateral.balanceOf(investor1), before + 3_000e18);
    }

    function _commit(address user, Sale sale, uint256 amount) internal {
        vm.startPrank(user);
        collateral.approve(address(sale), amount);
        sale.commit(amount);
        vm.stopPrank();
    }
}
