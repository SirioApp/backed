// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {AgentRaiseFactory} from "../../src/agents/AgentRaiseFactory.sol";
import {AgentExecutor} from "../../src/agents/AgentExecutor.sol";
import {Sale} from "../../src/launch/Sale.sol";
import {ContractAllowlist} from "../../src/registry/ContractAllowlist.sol";
import {MockIdentityRegistry} from "../mocks/MockIdentityRegistry.sol";
import {MockSafeProxyFactory} from "../mocks/MockSafeProxyFactory.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {USDM, DEFAULT_MAX_RAISE, DEFAULT_MIN_RAISE} from "../../src/Constants.sol";

contract AgentRaiseFactoryTest is Test {
    uint256 internal constant SALE_DURATION = 7 days;

    AgentRaiseFactory internal factory;
    ContractAllowlist internal allowlist;
    MockIdentityRegistry internal identityRegistry;
    MockSafeProxyFactory internal safeProxyFactory;
    MockERC20 internal usdm;

    address internal agent1 = makeAddr("agent1");
    address internal agent2 = makeAddr("agent2");
    address internal agentAddr = makeAddr("agentAddr");
    address internal attacker = makeAddr("attacker");
    address internal safeSingleton = makeAddr("safeSingleton");
    address internal safeFallbackHandler = makeAddr("safeFallbackHandler");
    address internal safeModuleSetup = makeAddr("safeModuleSetup");

    function setUp() public {
        identityRegistry = new MockIdentityRegistry();
        safeProxyFactory = new MockSafeProxyFactory();
        allowlist = new ContractAllowlist(address(this));

        usdm = new MockERC20("USDM", "USDM", 18);
        vm.etch(USDM, address(usdm).code);

        factory = new AgentRaiseFactory(
            address(identityRegistry),
            address(safeProxyFactory),
            safeSingleton,
            safeFallbackHandler,
            safeModuleSetup,
            address(this),
            address(allowlist),
            USDM
        );

        identityRegistry.register(agent1, "");
        identityRegistry.register(agent2, "");
    }

    function test_CreateAgentRaise_Success() public {
        uint256 launchTime = block.timestamp + 1 days;
        vm.prank(agent1);
        uint256 projectId = factory.createAgentRaise(
            1,
            "Agent Project",
            "Momentum strategy",
            "defi,trading",
            agentAddr,
            USDM,
            SALE_DURATION,
            launchTime,
            "AgentToken",
            "AGT"
        );

        assertEq(projectId, 0);
        assertEq(factory.projectCount(), 1);
        assertFalse(factory.isProjectApproved(projectId));
    }

    function test_CreateAgentRaise_StoresExecutor() public {
        uint256 launchTime = block.timestamp + 1 days;
        vm.prank(agent1);
        uint256 projectId = factory.createAgentRaise(
            1,
            "Agent Project",
            "Momentum strategy",
            "defi,trading",
            agentAddr,
            USDM,
            SALE_DURATION,
            launchTime,
            "AgentToken",
            "AGT"
        );

        AgentRaiseFactory.AgentProject memory p = factory.getProject(projectId);
        assertTrue(p.agentExecutor != address(0));
        assertEq(AgentExecutor(p.agentExecutor).AGENT(), agentAddr);
        assertEq(AgentExecutor(p.agentExecutor).ADMIN(), address(this));
        assertEq(p.collateral, USDM);
        assertEq(p.description, "Momentum strategy");
        assertEq(p.categories, "defi,trading");
        assertEq(p.operationalStatus, factory.STATUS_RAISING());
    }

    function test_MaxRaise_IsConstant() public view {
        assertEq(factory.maxRaise(), DEFAULT_MAX_RAISE);
    }

    function test_DefaultConfig_MaxRaiseScalesToCollateralDecimals() public {
        MockERC20 usdm6 = new MockERC20("USDM", "USDM", 6);
        vm.etch(USDM, address(usdm6).code);

        AgentRaiseFactory scaledFactory = new AgentRaiseFactory(
            address(identityRegistry),
            address(safeProxyFactory),
            safeSingleton,
            safeFallbackHandler,
            safeModuleSetup,
            address(this),
            address(allowlist),
            USDM
        );

        (uint256 minRaise, uint256 maxRaise,,,,,,) = scaledFactory.globalConfig();
        assertEq(minRaise, DEFAULT_MIN_RAISE);
        assertEq(maxRaise, DEFAULT_MAX_RAISE);
        assertEq(scaledFactory.minRaiseForCollateral(USDM), 2_500e6);
        assertEq(scaledFactory.maxRaiseForCollateral(USDM), 10_000e6);
    }

    function test_ApproveProject() public {
        uint256 launchTime = block.timestamp + 1 days;
        vm.prank(agent1);
        uint256 projectId = factory.createAgentRaise(
            1,
            "Agent Project",
            "Momentum strategy",
            "defi,trading",
            agentAddr,
            USDM,
            SALE_DURATION,
            launchTime,
            "AgentToken",
            "AGT"
        );

        assertFalse(factory.isProjectApproved(projectId));
        factory.approveProject(projectId);
        assertTrue(factory.isProjectApproved(projectId));
    }

    function test_RevokeProject() public {
        uint256 launchTime = block.timestamp + 1 days;
        vm.prank(agent1);
        uint256 projectId = factory.createAgentRaise(
            1,
            "Agent Project",
            "Momentum strategy",
            "defi,trading",
            agentAddr,
            USDM,
            SALE_DURATION,
            launchTime,
            "AgentToken",
            "AGT"
        );

        factory.approveProject(projectId);
        factory.revokeProject(projectId);
        assertFalse(factory.isProjectApproved(projectId));
    }

    function test_RevokeProject_RevertNotAdmin() public {
        uint256 launchTime = block.timestamp + 1 days;
        vm.prank(agent1);
        uint256 projectId = factory.createAgentRaise(
            1,
            "Agent Project",
            "Momentum strategy",
            "defi,trading",
            agentAddr,
            USDM,
            SALE_DURATION,
            launchTime,
            "AgentToken",
            "AGT"
        );
        factory.approveProject(projectId);

        vm.prank(attacker);
        vm.expectRevert(AgentRaiseFactory.Unauthorized.selector);
        factory.revokeProject(projectId);
    }

    function test_RevokeProject_RevertNotApproved() public {
        uint256 launchTime = block.timestamp + 1 days;
        vm.prank(agent1);
        uint256 projectId = factory.createAgentRaise(
            1,
            "Agent Project",
            "Momentum strategy",
            "defi,trading",
            agentAddr,
            USDM,
            SALE_DURATION,
            launchTime,
            "AgentToken",
            "AGT"
        );

        vm.expectRevert(AgentRaiseFactory.ProjectNotApprovedError.selector);
        factory.revokeProject(projectId);
    }

    function test_ApproveProject_RevertNotAdmin() public {
        uint256 launchTime = block.timestamp + 1 days;
        vm.prank(agent1);
        uint256 projectId = factory.createAgentRaise(
            1,
            "Agent Project",
            "Momentum strategy",
            "defi,trading",
            agentAddr,
            USDM,
            SALE_DURATION,
            launchTime,
            "AgentToken",
            "AGT"
        );

        vm.prank(attacker);
        vm.expectRevert(AgentRaiseFactory.Unauthorized.selector);
        factory.approveProject(projectId);
    }

    function test_ApproveProject_RevertAlreadyApproved() public {
        uint256 launchTime = block.timestamp + 1 days;
        vm.prank(agent1);
        uint256 projectId = factory.createAgentRaise(
            1,
            "Agent Project",
            "Momentum strategy",
            "defi,trading",
            agentAddr,
            USDM,
            SALE_DURATION,
            launchTime,
            "AgentToken",
            "AGT"
        );

        factory.approveProject(projectId);
        vm.expectRevert(AgentRaiseFactory.ProjectAlreadyApproved.selector);
        factory.approveProject(projectId);
    }

    function test_CreateAgentRaise_RevertNotOwner() public {
        uint256 launchTime = block.timestamp + 1 days;
        vm.prank(attacker);
        vm.expectRevert(AgentRaiseFactory.NotAgentOwner.selector);
        factory.createAgentRaise(
            1,
            "Agent Project",
            "Momentum strategy",
            "defi,trading",
            agentAddr,
            USDM,
            SALE_DURATION,
            launchTime,
            "AgentToken",
            "AGT"
        );
    }

    function test_CreateAgentRaise_RevertInvalidParams() public {
        uint256 launchTime = block.timestamp + 1 days;
        vm.prank(agent1);
        vm.expectRevert(AgentRaiseFactory.InvalidParams.selector);
        factory.createAgentRaise(
            1,
            "",
            "Momentum strategy",
            "defi,trading",
            agentAddr,
            USDM,
            SALE_DURATION,
            launchTime,
            "AgentToken",
            "AGT"
        );
    }

    function test_CreateAgentRaise_RevertZeroAgentAddress() public {
        uint256 launchTime = block.timestamp + 1 days;
        vm.prank(agent1);
        vm.expectRevert(AgentRaiseFactory.InvalidAddress.selector);
        factory.createAgentRaise(
            1,
            "Agent Project",
            "Momentum strategy",
            "defi,trading",
            address(0),
            USDM,
            SALE_DURATION,
            launchTime,
            "AgentToken",
            "AGT"
        );
    }

    function test_CreateAgentRaise_RevertsUnsupportedCollateral() public {
        uint256 launchTime = block.timestamp + 1 days;
        address otherCollateral = makeAddr("otherCollateral");

        vm.prank(agent1);
        vm.expectRevert(AgentRaiseFactory.UnsupportedCollateral.selector);
        factory.createAgentRaise(
            1,
            "Agent Project",
            "Momentum strategy",
            "defi,trading",
            agentAddr,
            otherCollateral,
            SALE_DURATION,
            launchTime,
            "AgentToken",
            "AGT"
        );
    }

    function test_GetAgentProjects() public {
        uint256 launchTime = block.timestamp + 1 days;
        vm.startPrank(agent1);
        factory.createAgentRaise(
            1,
            "Project A",
            "Project A description",
            "infra,agent",
            agentAddr,
            USDM,
            SALE_DURATION,
            launchTime,
            "TKA",
            "TKA"
        );
        factory.createAgentRaise(
            1,
            "Project B",
            "Project B description",
            "infra,agent",
            agentAddr,
            USDM,
            SALE_DURATION,
            launchTime,
            "TKB",
            "TKB"
        );
        vm.stopPrank();

        uint256[] memory projects = factory.getAgentProjects(1);
        assertEq(projects.length, 2);
        assertEq(projects[0], 0);
        assertEq(projects[1], 1);
    }

    function test_SUPER_ADMIN() public view {
        assertEq(factory.SUPER_ADMIN(), address(this));
    }

    function test_SetGlobalConfig() public {
        AgentRaiseFactory.GlobalConfig memory cfg = AgentRaiseFactory.GlobalConfig({
            minRaise: 3_000e18,
            maxRaise: 20_000e18,
            platformFeeBps: 250,
            platformFeeRecipient: address(0xBEEF),
            minDuration: 0,
            maxDuration: 0,
            minLaunchDelay: 0,
            maxLaunchDelay: 0
        });

        factory.setGlobalConfig(cfg);
        (
            uint256 minRaise,
            uint256 maxRaise,
            uint16 platformFeeBps,
            address feeRecipient,
            uint256 minDuration,
            uint256 maxDuration,
            uint256 minLaunchDelay,
            uint256 maxLaunchDelay
        ) = factory.globalConfig();

        assertEq(minRaise, cfg.minRaise);
        assertEq(maxRaise, cfg.maxRaise);
        assertEq(platformFeeBps, cfg.platformFeeBps);
        assertEq(feeRecipient, cfg.platformFeeRecipient);
        assertEq(minDuration, cfg.minDuration);
        assertEq(maxDuration, cfg.maxDuration);
        assertEq(minLaunchDelay, cfg.minLaunchDelay);
        assertEq(maxLaunchDelay, cfg.maxLaunchDelay);
    }

    function test_SetGlobalConfig_RevertsNotAdmin() public {
        AgentRaiseFactory.GlobalConfig memory cfg = AgentRaiseFactory.GlobalConfig({
            minRaise: DEFAULT_MIN_RAISE,
            maxRaise: DEFAULT_MAX_RAISE,
            platformFeeBps: 500,
            platformFeeRecipient: address(0xBEEF),
            minDuration: 0,
            maxDuration: 0,
            minLaunchDelay: 0,
            maxLaunchDelay: 0
        });

        vm.prank(attacker);
        vm.expectRevert(AgentRaiseFactory.Unauthorized.selector);
        factory.setGlobalConfig(cfg);
    }

    function test_SetGlobalConfig_RevertsFeeAtBps() public {
        AgentRaiseFactory.GlobalConfig memory cfg = AgentRaiseFactory.GlobalConfig({
            minRaise: DEFAULT_MIN_RAISE,
            maxRaise: DEFAULT_MAX_RAISE,
            platformFeeBps: 10_000,
            platformFeeRecipient: address(0xBEEF),
            minDuration: 0,
            maxDuration: 0,
            minLaunchDelay: 0,
            maxLaunchDelay: 0
        });

        vm.expectRevert(AgentRaiseFactory.InvalidConfig.selector);
        factory.setGlobalConfig(cfg);
    }

    function test_CreateAgentRaise_AllowsAnyPositiveDuration() public {
        AgentRaiseFactory.GlobalConfig memory cfg = AgentRaiseFactory.GlobalConfig({
            minRaise: DEFAULT_MIN_RAISE,
            maxRaise: DEFAULT_MAX_RAISE,
            platformFeeBps: 500,
            platformFeeRecipient: address(0xBEEF),
            minDuration: 2 days,
            maxDuration: 30 days,
            minLaunchDelay: 0,
            maxLaunchDelay: 365 days
        });
        factory.setGlobalConfig(cfg);

        uint256 launchTime = block.timestamp + 1 days;
        vm.prank(agent1);
        uint256 projectId = factory.createAgentRaise(
            1,
            "Agent Project",
            "Momentum strategy",
            "defi,trading",
            agentAddr,
            USDM,
            1 days,
            launchTime,
            "AgentToken",
            "AGT"
        );
        assertEq(projectId, 0);
    }

    function test_CreateAgentRaise_AllowsAnyFutureLaunchDelay() public {
        AgentRaiseFactory.GlobalConfig memory cfg = AgentRaiseFactory.GlobalConfig({
            minRaise: DEFAULT_MIN_RAISE,
            maxRaise: DEFAULT_MAX_RAISE,
            platformFeeBps: 500,
            platformFeeRecipient: address(0xBEEF),
            minDuration: 1 hours,
            maxDuration: 30 days,
            minLaunchDelay: 1 days,
            maxLaunchDelay: 365 days
        });
        factory.setGlobalConfig(cfg);

        uint256 launchTime = block.timestamp + 1 hours;
        vm.prank(agent1);
        uint256 projectId = factory.createAgentRaise(
            1,
            "Agent Project",
            "Momentum strategy",
            "defi,trading",
            agentAddr,
            USDM,
            SALE_DURATION,
            launchTime,
            "AgentToken",
            "AGT"
        );
        assertEq(projectId, 0);
    }

    function test_CreateAgentRaise_RevertsLaunchTimeInPast() public {
        vm.warp(100);
        vm.prank(agent1);
        vm.expectRevert(AgentRaiseFactory.InvalidLaunchTime.selector);
        factory.createAgentRaise(
            1,
            "Agent Project",
            "Momentum strategy",
            "defi,trading",
            agentAddr,
            USDM,
            SALE_DURATION,
            99,
            "AgentToken",
            "AGT"
        );
    }

    function test_SetAllowedCollateral_Success() public {
        MockERC20 dai = new MockERC20("DAI", "DAI", 18);
        address daiAddr = address(dai);
        factory.setAllowedCollateral(daiAddr, true);
        assertTrue(factory.allowedCollateral(daiAddr));
    }

    function test_SetAllowedCollateral_RevertsNotAdmin() public {
        MockERC20 dai = new MockERC20("DAI", "DAI", 18);
        vm.prank(attacker);
        vm.expectRevert(AgentRaiseFactory.Unauthorized.selector);
        factory.setAllowedCollateral(address(dai), true);
    }

    function test_SetAllowedCollateral_Disable() public {
        MockERC20 dai = new MockERC20("DAI", "DAI", 18);
        factory.setAllowedCollateral(address(dai), true);
        assertTrue(factory.allowedCollateral(address(dai)));

        factory.setAllowedCollateral(address(dai), false);
        assertFalse(factory.allowedCollateral(address(dai)));
    }

    function test_SetAllowedCollateral_RevertsUnsupportedTokenDecimals() public {
        MockERC20 weird = new MockERC20("WEIRD", "WRD", 37);
        vm.expectRevert(AgentRaiseFactory.UnsupportedTokenDecimals.selector);
        factory.setAllowedCollateral(address(weird), true);
    }

    function test_CreateAgentRaise_SuccessWithConfiguredCollateral() public {
        MockERC20 usdc = new MockERC20("USDC", "USDC", 6);
        address usdcAddr = address(usdc);
        factory.setAllowedCollateral(usdcAddr, true);

        uint256 launchTime = block.timestamp + 1 days;
        vm.prank(agent1);
        uint256 projectId = factory.createAgentRaise(
            1,
            "USDC Project",
            "USDC strategy",
            "stablecoin,defi",
            agentAddr,
            usdcAddr,
            SALE_DURATION,
            launchTime,
            "AgentToken",
            "AGT"
        );

        AgentRaiseFactory.AgentProject memory p = factory.getProject(projectId);
        assertEq(p.collateral, usdcAddr);
    }

    function test_CreateAgentRaise_RevertsIfScaledRaiseBecomesZero() public {
        MockERC20 usdc = new MockERC20("USDC", "USDC", 6);
        address usdcAddr = address(usdc);
        factory.setAllowedCollateral(usdcAddr, true);

        AgentRaiseFactory.GlobalConfig memory cfg = AgentRaiseFactory.GlobalConfig({
            minRaise: 1,
            maxRaise: 2,
            platformFeeBps: 500,
            platformFeeRecipient: address(0xBEEF),
            minDuration: 1 hours,
            maxDuration: 30 days,
            minLaunchDelay: 0,
            maxLaunchDelay: 365 days
        });
        factory.setGlobalConfig(cfg);

        uint256 launchTime = block.timestamp + 1 days;
        vm.prank(agent1);
        vm.expectRevert(AgentRaiseFactory.InvalidConfig.selector);
        factory.createAgentRaise(
            1,
            "USDC Project",
            "USDC strategy",
            "stablecoin,defi",
            agentAddr,
            usdcAddr,
            SALE_DURATION,
            launchTime,
            "AgentToken",
            "AGT"
        );
    }

    function test_UpdateProjectMetadata_Success() public {
        uint256 launchTime = block.timestamp + 1 days;
        vm.prank(agent1);
        uint256 projectId = factory.createAgentRaise(
            1,
            "Agent Project",
            "Initial",
            "defi",
            agentAddr,
            USDM,
            SALE_DURATION,
            launchTime,
            "AgentToken",
            "AGT"
        );

        factory.updateProjectMetadata(
            projectId, "Updated description", "market-making,delta-neutral"
        );
        AgentRaiseFactory.AgentProject memory p = factory.getProject(projectId);
        assertEq(p.description, "Updated description");
        assertEq(p.categories, "market-making,delta-neutral");
        assertEq(p.updatedAt, block.timestamp);
    }

    function test_UpdateProjectMetadata_RevertsNotAdmin() public {
        uint256 launchTime = block.timestamp + 1 days;
        vm.prank(agent1);
        uint256 projectId = factory.createAgentRaise(
            1,
            "Agent Project",
            "Initial",
            "defi",
            agentAddr,
            USDM,
            SALE_DURATION,
            launchTime,
            "AgentToken",
            "AGT"
        );

        vm.prank(attacker);
        vm.expectRevert(AgentRaiseFactory.Unauthorized.selector);
        factory.updateProjectMetadata(projectId, "Updated description", "market-making");
    }

    function test_UpdateProjectOperationalStatus_ByAdminAndAgentOwner() public {
        uint256 launchTime = block.timestamp + 1 days;
        vm.prank(agent1);
        uint256 projectId = factory.createAgentRaise(
            1,
            "Agent Project",
            "Initial",
            "defi",
            agentAddr,
            USDM,
            SALE_DURATION,
            launchTime,
            "AgentToken",
            "AGT"
        );

        vm.prank(agent1);
        factory.updateProjectOperationalStatus(
            projectId, factory.STATUS_OPERATING(), "Running strategy"
        );
        AgentRaiseFactory.AgentProject memory afterAgentUpdate = factory.getProject(projectId);
        assertEq(afterAgentUpdate.operationalStatus, factory.STATUS_OPERATING());
        assertEq(afterAgentUpdate.statusNote, "Running strategy");

        factory.updateProjectOperationalStatus(
            projectId, factory.STATUS_PAUSED(), "Paused for maintenance"
        );
        AgentRaiseFactory.AgentProject memory afterAdminUpdate = factory.getProject(projectId);
        assertEq(afterAdminUpdate.operationalStatus, factory.STATUS_PAUSED());
        assertEq(afterAdminUpdate.statusNote, "Paused for maintenance");
    }

    function test_UpdateProjectOperationalStatus_RevertsInvalidStatus() public {
        uint256 launchTime = block.timestamp + 1 days;
        vm.prank(agent1);
        uint256 projectId = factory.createAgentRaise(
            1,
            "Agent Project",
            "Initial",
            "defi",
            agentAddr,
            USDM,
            SALE_DURATION,
            launchTime,
            "AgentToken",
            "AGT"
        );

        vm.expectRevert(AgentRaiseFactory.InvalidOperationalStatus.selector);
        factory.updateProjectOperationalStatus(projectId, type(uint8).max, "Invalid");
    }

    function test_UpdateProjectOperationalStatus_RevertsUnauthorized() public {
        uint256 launchTime = block.timestamp + 1 days;
        vm.prank(agent1);
        uint256 projectId = factory.createAgentRaise(
            1,
            "Agent Project",
            "Initial",
            "defi",
            agentAddr,
            USDM,
            SALE_DURATION,
            launchTime,
            "AgentToken",
            "AGT"
        );

        uint8 paused = factory.STATUS_PAUSED();
        vm.startPrank(attacker);
        vm.expectRevert(AgentRaiseFactory.Unauthorized.selector);
        factory.updateProjectOperationalStatus(projectId, paused, "blocked");
        vm.stopPrank();
    }

    function test_GetProjectRaiseSnapshot_AndCommitment() public {
        uint256 launchTime = block.timestamp + 1 days;
        vm.prank(agent1);
        uint256 projectId = factory.createAgentRaise(
            1,
            "Agent Project",
            "Initial",
            "defi",
            agentAddr,
            USDM,
            SALE_DURATION,
            launchTime,
            "AgentToken",
            "AGT"
        );
        factory.approveProject(projectId);

        AgentRaiseFactory.AgentProject memory p = factory.getProject(projectId);
        MockERC20(USDM).mint(attacker, 2_000e18);

        vm.warp(launchTime + 1);
        vm.startPrank(attacker);
        MockERC20(USDM).approve(p.sale, 1_000e18);
        Sale(p.sale).commit(1_000e18);
        vm.stopPrank();

        AgentRaiseFactory.ProjectRaiseSnapshot memory snapshot =
            factory.getProjectRaiseSnapshot(projectId);
        assertTrue(snapshot.approved);
        assertEq(snapshot.totalCommitted, 1_000e18);
        assertEq(snapshot.acceptedAmount, 0);
        assertFalse(snapshot.finalized);
        assertTrue(snapshot.active);
        assertEq(factory.getProjectCommitment(projectId, attacker), 1_000e18);
    }

    function test_ProjectViews_RevertProjectNotFound() public {
        vm.expectRevert(AgentRaiseFactory.ProjectNotFound.selector);
        factory.getProject(99);

        vm.expectRevert(AgentRaiseFactory.ProjectNotFound.selector);
        factory.getProjectRaiseSnapshot(99);

        vm.expectRevert(AgentRaiseFactory.ProjectNotFound.selector);
        factory.getProjectCommitment(99, attacker);
    }

    function test_MinMaxRaiseForCollateral_RevertsUnsupportedCollateral() public {
        address noDecimalsToken = makeAddr("noDecimalsToken");

        vm.expectRevert(AgentRaiseFactory.UnsupportedCollateral.selector);
        factory.maxRaiseForCollateral(noDecimalsToken);

        vm.expectRevert(AgentRaiseFactory.UnsupportedCollateral.selector);
        factory.minRaiseForCollateral(noDecimalsToken);
    }
}
