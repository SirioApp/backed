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

contract FlowMatrixTarget {
    uint256 public touched;

    function touch() external {
        touched += 1;
    }
}

contract AgentRaiseFlowMatrixTest is Test {
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
    address internal investor3 = makeAddr("investor3");
    address internal outsider = makeAddr("outsider");
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

        identityRegistry.register(agentOwner, "ipfs://agent-matrix");
        collateral.mint(investor1, 2_000_000e18);
        collateral.mint(investor2, 2_000_000e18);
        collateral.mint(investor3, 2_000_000e18);
    }

    function test_Flow_Success_Oversubscribed_Settle_Claim_Redeem() public {
        (AgentRaiseFactory.AgentProject memory p, uint256 launchTime) =
            _createApprovedProject("success-flow");
        Sale sale = Sale(p.sale);
        AgentExecutor executor = AgentExecutor(p.agentExecutor);

        vm.warp(launchTime + 1);
        _commit(investor1, sale, 7_000e18);
        _commit(investor2, sale, 6_000e18);

        vm.warp(launchTime + SALE_DURATION + 1);
        sale.finalize();
        assertTrue(sale.finalized());
        assertFalse(sale.failed());
        assertEq(sale.totalCommitted(), 13_000e18);
        assertEq(sale.acceptedAmount(), 10_000e18);
        assertEq(collateral.balanceOf(p.treasury), 10_000e18);

        AgentVaultToken shareToken = AgentVaultToken(sale.token());
        vm.startPrank(admin);
        allowlist.addContract(address(collateral));
        allowlist.addContract(address(shareToken));
        executor.setSelectorAllowed(address(collateral), TRANSFER_SELECTOR, true);
        executor.setSelectorAllowed(
            address(shareToken), AgentVaultToken.finalizeSettlement.selector, true
        );
        vm.stopPrank();

        collateral.mint(p.treasury, 1_000e18);

        vm.prank(investor1);
        sale.claim();
        vm.prank(investor2);
        sale.claim();

        assertEq(sale.totalRefundedAmount(), 3_000e18);
        assertEq(shareToken.balanceOf(investor1) + shareToken.balanceOf(investor2), sale.totalSharesMinted());

        vm.warp(shareToken.LOCKUP_END_TIME());
        vm.prank(agentOperator);
        executor.execute(
            address(collateral),
            0,
            abi.encodeWithSignature("transfer(address,uint256)", address(shareToken), 11_000e18)
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

        uint256 redeemedTotal = user1Assets + user2Assets;
        uint256 expectedRedeemedTotal = 10_950e18;
        assertEq(redeemedTotal, expectedRedeemedTotal);
        assertEq(collateral.balanceOf(investor1), user1Before + user1Assets);
        assertEq(collateral.balanceOf(investor2), user2Before + user2Assets);
    }

    function test_Flow_FailedUnderMinRaise_Finalize_Refund() public {
        (AgentRaiseFactory.AgentProject memory p, uint256 launchTime) =
            _createApprovedProject("min-raise-fail");
        Sale sale = Sale(p.sale);

        vm.warp(launchTime + 1);
        _commit(investor1, sale, 1_000e18);

        vm.warp(launchTime + SALE_DURATION + 1);
        sale.finalize();

        assertTrue(sale.finalized());
        assertTrue(sale.failed());
        assertEq(sale.acceptedAmount(), 1_000e18);

        uint256 beforeRefund = collateral.balanceOf(investor1);
        vm.prank(investor1);
        sale.refund();
        assertEq(collateral.balanceOf(investor1), beforeRefund + 1_000e18);
    }

    function test_Flow_EmergencyRefund_Path() public {
        (AgentRaiseFactory.AgentProject memory p, uint256 launchTime) =
            _createApprovedProject("emergency-flow");
        Sale sale = Sale(p.sale);

        vm.warp(launchTime + 1);
        _commit(investor1, sale, 1_200e18);
        _commit(investor2, sale, 800e18);

        vm.prank(admin);
        sale.emergencyRefund();
        assertTrue(sale.finalized());
        assertTrue(sale.failed());

        uint256 user1Before = collateral.balanceOf(investor1);
        uint256 user2Before = collateral.balanceOf(investor2);
        vm.prank(investor1);
        sale.refund();
        vm.prank(investor2);
        sale.refund();
        assertEq(collateral.balanceOf(investor1), user1Before + 1_200e18);
        assertEq(collateral.balanceOf(investor2), user2Before + 800e18);
    }

    function test_Flow_AllowlistToggle_Path() public {
        (AgentRaiseFactory.AgentProject memory p,) = _createApprovedProject("allowlist-toggle");
        AgentExecutor executor = AgentExecutor(p.agentExecutor);
        FlowMatrixTarget target = new FlowMatrixTarget();

        vm.prank(agentOperator);
        vm.expectRevert(AgentExecutor.TargetNotAllowed.selector);
        executor.execute(
            address(target), 0, abi.encodeWithSelector(FlowMatrixTarget.touch.selector)
        );

        vm.prank(admin);
        executor.setAllowlistEnforced(false);

        vm.prank(agentOperator);
        executor.execute(
            address(target), 0, abi.encodeWithSelector(FlowMatrixTarget.touch.selector)
        );
        assertEq(target.touched(), 1);

        vm.prank(admin);
        executor.setAllowlistEnforced(true);

        vm.prank(agentOperator);
        vm.expectRevert(AgentExecutor.TargetNotAllowed.selector);
        executor.execute(
            address(target), 0, abi.encodeWithSelector(FlowMatrixTarget.touch.selector)
        );
    }

    function test_Flow_SelectorPolicy_BlocksUnknownCalls() public {
        (AgentRaiseFactory.AgentProject memory p,) = _createApprovedProject("selector-policy");
        AgentExecutor executor = AgentExecutor(p.agentExecutor);

        collateral.mint(p.treasury, 500e18);
        vm.prank(admin);
        allowlist.addContract(address(collateral));

        bytes memory transferCall =
            abi.encodeWithSignature("transfer(address,uint256)", outsider, 100e18);
        vm.prank(agentOperator);
        vm.expectRevert(AgentExecutor.SelectorNotAllowed.selector);
        executor.execute(address(collateral), 0, transferCall);
    }

    function test_Flow_ApprovalPolicy_BlocksUnallowlistedSpender() public {
        (AgentRaiseFactory.AgentProject memory p,) = _createApprovedProject("approval-policy");
        AgentExecutor executor = AgentExecutor(p.agentExecutor);

        vm.startPrank(admin);
        allowlist.addContract(address(collateral));
        executor.setSelectorAllowed(
            address(collateral), bytes4(keccak256("approve(address,uint256)")), true
        );
        vm.stopPrank();

        bytes memory approveCall =
            abi.encodeWithSignature("approve(address,uint256)", outsider, type(uint256).max);
        vm.prank(agentOperator);
        vm.expectRevert(AgentExecutor.SpenderNotAllowed.selector);
        executor.execute(address(collateral), 0, approveCall);
    }

    function _createApprovedProject(string memory description)
        internal
        returns (AgentRaiseFactory.AgentProject memory p, uint256 launchTime)
    {
        launchTime = block.timestamp + 1 days;
        vm.prank(agentOwner);
        uint256 projectId = factory.createAgentRaise(
            1,
            "Flow Matrix Agent",
            description,
            "defi,testing,matrix",
            agentOperator,
            address(collateral),
            SALE_DURATION,
            launchTime,
            "Flow Matrix Fund",
            "FMF"
        );
        vm.prank(admin);
        factory.approveProject(projectId);
        p = factory.getProject(projectId);
    }

    function _commit(address user, Sale sale, uint256 amount) internal {
        vm.startPrank(user);
        collateral.approve(address(sale), amount);
        sale.commit(amount);
        vm.stopPrank();
    }
}
