// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {AgentRaiseFactory} from "../src/agents/AgentRaiseFactory.sol";
import {ISale} from "../src/interfaces/ISale.sol";

interface ITestnetIdentityRegistry {
    function register(string calldata agentURI) external returns (uint256 agentId);
}

contract TestnetProductionValidationSetup is Script {
    uint256 private constant MEGAETH_TESTNET_CHAIN_ID = 6343;

    address private constant IDENTITY_REGISTRY = 0x8004A818BFB912233c491871b3d84c89A494BD9e;
    address private constant FACTORY = 0x63Baad87dED7c8e8B8F470a0433554045daEA9A8;
    address private constant USDM = 0x9f5A17BD53310D012544966b8e3cF7863fc8F05f;

    function run() external {
        require(block.chainid == MEGAETH_TESTNET_CHAIN_ID, "Wrong network: testnet only");

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address operator = vm.envAddress("TEST_OPERATOR");

        uint256 launchDelay = vm.envOr("VALIDATION_LAUNCH_DELAY", uint256(30));
        uint256 duration = vm.envOr("VALIDATION_DURATION", uint256(120));
        uint256 settlementLockupMinutes = vm.envOr("VALIDATION_LOCKUP_MINUTES", uint256(1));

        string memory suffix = vm.toString(block.timestamp);
        string memory agentURI = string.concat("ipfs://backed-testnet-validation-", suffix);

        AgentRaiseFactory factory = AgentRaiseFactory(FACTORY);

        vm.startBroadcast(deployerKey);

        uint256 agentId = ITestnetIdentityRegistry(IDENTITY_REGISTRY).register(agentURI);
        uint256 launchTime = vm.envOr("VALIDATION_LAUNCH_TIME", uint256(block.timestamp + launchDelay));

        uint256 smokeProjectId = factory.createAgentRaise(
            agentId,
            string.concat("Validation Smoke ", suffix),
            "Production validation: under-min commit flow",
            "validation,smoke",
            operator,
            USDM,
            duration,
            launchTime,
            string.concat("Validation Smoke Fund ", suffix),
            "VSMK"
        );
        factory.approveProject(smokeProjectId);

        uint256 refundProjectId = factory.createAgentRaise(
            agentId,
            string.concat("Validation Refund ", suffix),
            "Production validation: emergency refund flow",
            "validation,refund",
            operator,
            USDM,
            duration,
            launchTime,
            string.concat("Validation Refund Fund ", suffix),
            "VRFD"
        );
        factory.approveProject(refundProjectId);

        uint256 settlementProjectId = factory.createAgentRaise(
            agentId,
            string.concat("Validation Settlement ", suffix),
            "Production validation: successful raise and final distribution flow",
            "validation,settlement",
            operator,
            USDM,
            duration,
            launchTime,
            settlementLockupMinutes,
            string.concat("Validation Settlement Fund ", suffix),
            "VSET"
        );
        factory.approveProject(settlementProjectId);

        vm.stopBroadcast();

        AgentRaiseFactory.AgentProject memory smokeProject = factory.getProject(smokeProjectId);
        AgentRaiseFactory.AgentProject memory refundProject = factory.getProject(refundProjectId);
        AgentRaiseFactory.AgentProject memory settlementProject =
            factory.getProject(settlementProjectId);

        console.log("VALIDATION_AGENT_ID=%s", agentId);
        console.log("VALIDATION_OPERATOR=%s", operator);
        console.log("VALIDATION_LAUNCH_TIME=%s", launchTime);
        console.log("VALIDATION_DURATION=%s", duration);

        console.log("SMOKE_PROJECT_ID=%s", smokeProjectId);
        console.log("SMOKE_SALE=%s", smokeProject.sale);
        console.log("SMOKE_TREASURY=%s", ISale(smokeProject.sale).TREASURY());
        console.log("SMOKE_EXECUTOR=%s", smokeProject.agentExecutor);

        console.log("REFUND_PROJECT_ID=%s", refundProjectId);
        console.log("REFUND_SALE=%s", refundProject.sale);
        console.log("REFUND_TREASURY=%s", ISale(refundProject.sale).TREASURY());
        console.log("REFUND_EXECUTOR=%s", refundProject.agentExecutor);

        console.log("SETTLEMENT_PROJECT_ID=%s", settlementProjectId);
        console.log("SETTLEMENT_SALE=%s", settlementProject.sale);
        console.log("SETTLEMENT_TREASURY=%s", ISale(settlementProject.sale).TREASURY());
        console.log("SETTLEMENT_EXECUTOR=%s", settlementProject.agentExecutor);
    }
}
