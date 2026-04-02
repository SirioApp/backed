// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, Vm} from "forge-std/Test.sol";

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

    function test_E2E_FullLifecycle_WithProfitDistribution() public {
        uint256 launchTime = block.timestamp + 1 days;
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
            "Agent Vault",
            "AGV"
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

        address vaultAddr = sale.token();
        AgentVaultToken vault = AgentVaultToken(vaultAddr);
        assertTrue(vaultAddr != address(0));
        assertEq(vault.PLATFORM_FEE_BPS(), 500);
        assertEq(vault.PLATFORM_FEE_RECIPIENT(), admin);

        vm.startPrank(admin);
        allowlist.addContract(address(collateral));
        allowlist.addContract(vaultAddr);
        executor.setSelectorAllowed(
            address(collateral), bytes4(keccak256("approve(address,uint256)")), true
        );
        executor.setSelectorAllowed(vaultAddr, AgentVaultToken.distributeProfits.selector, true);
        vm.stopPrank();

        uint256 grossProfit = 1_000e18;
        collateral.mint(p.treasury, grossProfit);
        uint256 feeRecipientBefore = collateral.balanceOf(admin);

        bytes memory approveCall =
            abi.encodeWithSignature("approve(address,uint256)", vaultAddr, grossProfit);
        vm.prank(agentOperator);
        executor.execute(address(collateral), 0, approveCall);

        bytes memory distributeCall =
            abi.encodeWithSelector(AgentVaultToken.distributeProfits.selector, grossProfit);
        vm.prank(agentOperator);
        executor.execute(vaultAddr, 0, distributeCall);

        uint256 user1Before = collateral.balanceOf(investor1);
        uint256 user2Before = collateral.balanceOf(investor2);

        vm.recordLogs();
        vm.prank(investor1);
        sale.claim();
        vm.prank(investor2);
        sale.claim();
        Vm.Log[] memory entries = vm.getRecordedLogs();

        uint256 user1Shares = vault.balanceOf(investor1);
        uint256 user2Shares = vault.balanceOf(investor2);
        assertEq(user1Shares, 3_000e18);
        assertEq(user2Shares, 2_000e18);
        assertEq(collateral.balanceOf(investor1), user1Before);
        assertEq(collateral.balanceOf(investor2), user2Before);

        bytes32 withdrawTopic =
            keccak256("Withdraw(address,address,address,uint256,uint256)");
        for (uint256 i = 0; i < entries.length; ++i) {
            if (entries[i].emitter == vaultAddr) {
                assertTrue(entries[i].topics[0] != withdrawTopic);
            }
        }

        vm.prank(investor1);
        vault.redeem(user1Shares, investor1, investor1);
        vm.prank(investor2);
        vault.redeem(user2Shares, investor2, investor2);

        uint256 user1Redeemed = collateral.balanceOf(investor1) - user1Before;
        uint256 user2Redeemed = collateral.balanceOf(investor2) - user2Before;
        assertLe(_absDiff(user1Redeemed, 3_570e18), 1);
        assertLe(_absDiff(user2Redeemed, 2_380e18), 1);
        assertEq(collateral.balanceOf(admin) - feeRecipientBefore, 50e18);
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
            "Agent Vault",
            "AGV"
        );

        vm.prank(admin);
        factory.approveProject(projectId);

        Sale sale = Sale(factory.getProject(projectId).sale);

        vm.warp(launchTime + 1);
        vm.prank(investor1);
        collateral.approve(address(sale), 1_200e18);
        vm.prank(investor1);
        sale.commit(1_200e18);

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
            "Agent Vault",
            "AGV"
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

    function test_E2E_EarlyClaimerStillKeepsProRataUpsideAfterDistribution() public {
        uint256 launchTime = block.timestamp + 1 days;
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
            "Agent Vault",
            "AGV"
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
        collateral.approve(address(sale), 3_000e18);
        sale.commit(3_000e18);
        vm.stopPrank();

        vm.warp(sale.endTime() + 1);
        sale.finalize();
        AgentVaultToken vault = AgentVaultToken(sale.token());

        vm.prank(investor1);
        sale.claim(); // claims shares early
        uint256 user1Shares = vault.balanceOf(investor1);
        assertEq(user1Shares, 3_000e18);

        vm.startPrank(admin);
        allowlist.addContract(address(collateral));
        allowlist.addContract(address(vault));
        executor.setSelectorAllowed(
            address(collateral), bytes4(keccak256("approve(address,uint256)")), true
        );
        executor.setSelectorAllowed(
            address(vault), AgentVaultToken.distributeProfits.selector, true
        );
        vm.stopPrank();

        uint256 grossProfit = 1_000e18;
        collateral.mint(p.treasury, grossProfit);
        bytes memory approveCall =
            abi.encodeWithSignature("approve(address,uint256)", address(vault), grossProfit);
        vm.prank(agentOperator);
        executor.execute(address(collateral), 0, approveCall);
        bytes memory distributeCall =
            abi.encodeWithSelector(AgentVaultToken.distributeProfits.selector, grossProfit);
        vm.prank(agentOperator);
        executor.execute(address(vault), 0, distributeCall);

        vm.prank(investor2);
        sale.claim(); // claims shares late
        uint256 user2Shares = vault.balanceOf(investor2);
        assertEq(user2Shares, 3_000e18);

        uint256 user1BeforeRedeem = collateral.balanceOf(investor1);
        uint256 user2BeforeRedeem = collateral.balanceOf(investor2);
        vm.prank(investor1);
        vault.redeem(user1Shares, investor1, investor1);
        vm.prank(investor2);
        vault.redeem(user2Shares, investor2, investor2);

        assertLe(_absDiff(collateral.balanceOf(investor1) - user1BeforeRedeem, 3_475e18), 1);
        assertLe(_absDiff(collateral.balanceOf(investor2) - user2BeforeRedeem, 3_475e18), 1);
    }

    function test_E2E_RedemptionLockedUntilLockupEnds() public {
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
            "Locked Vault",
            "LCK"
        );

        vm.prank(admin);
        factory.approveProject(projectId);

        AgentRaiseFactory.AgentProject memory p = factory.getProject(projectId);
        Sale sale = Sale(p.sale);

        vm.warp(launchTime + 1);
        vm.startPrank(investor1);
        collateral.approve(address(sale), 3_000e18);
        sale.commit(3_000e18);
        vm.stopPrank();

        vm.warp(sale.endTime() + 1);
        sale.finalize();

        AgentVaultToken vault = AgentVaultToken(sale.token());
        assertEq(vault.LOCKUP_END_TIME(), sale.endTime() + (lockupMinutes * 1 minutes));
        assertGt(vault.LOCKUP_END_TIME(), block.timestamp);

        vm.prank(investor1);
        sale.claim();
        uint256 shares = vault.balanceOf(investor1);
        assertEq(shares, 3_000e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                AgentVaultToken.LockupActive.selector, vault.LOCKUP_END_TIME()
            )
        );
        vm.prank(investor1);
        vault.redeem(shares, investor1, investor1);

        vm.warp(vault.LOCKUP_END_TIME());
        uint256 beforeRedeem = collateral.balanceOf(investor1);
        vm.prank(investor1);
        vault.redeem(shares, investor1, investor1);
        assertEq(collateral.balanceOf(investor1) - beforeRedeem, 3_000e18);
    }

    function _absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }
}
