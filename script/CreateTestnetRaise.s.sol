// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {AgentRaiseFactory} from "../src/agents/AgentRaiseFactory.sol";

/// @notice ERC-8004 identity registry (MegaETH testnet) — matches `frontend/config/deployment.testnet.json`.
interface ITestnetIdentityRegistry {
    function register(string calldata agentURI) external returns (uint256 agentId);
    function ownerOf(uint256 tokenId) external view returns (address);
    function getAgentWallet(uint256 agentId) external view returns (address wallet);
}

/// @dev Creates one approved raise on the **existing** testnet factory (no new deployment).
///      Aligns economic caps via `setGlobalConfig` (requires broadcaster == factory ADMIN).
///
/// Env:
///   PRIVATE_KEY           — required (admin + agent owner if registering / using agent)
///   AGENT_URI             — required when AGENT_ID is 0 (register new agent)
///   AGENT_ID              — optional; 0 = register new agent with AGENT_URI
///   MIN_RAISE_NORM        — optional; min raise in 18-dec normalized units (default 500 ether)
///   MAX_RAISE_NORM        — optional; max raise cap ~stable target (default 10_000 ether = 10k)
///   DURATION_SECONDS      — optional (default 3 days)
///   LAUNCH_DELAY_SECONDS  — optional (default 60 = 1 minute)
///   PROJECT_NAME          — optional
///   TOKEN_NAME / TOKEN_SYMBOL — optional
contract CreateTestnetRaise is Script {
    uint256 private constant MEGAETH_TESTNET_CHAIN_ID = 6343;

    address private constant IDENTITY_REGISTRY = 0x8004A818BFB912233c491871b3d84c89A494BD9e;
    /// Current stack from `frontend/config/deployment.testnet.json` (v31).
    address private constant FACTORY = 0xb4A89Ce1A7Aac4636Ba47615e810Ff1F4d6B8AEA;
    address private constant USDM = 0x9f5A17BD53310D012544966b8e3cF7863fc8F05f;

    /// @dev Sale window length when `DURATION_SECONDS` env is unset (3 days).
    uint256 private constant DEFAULT_DURATION_SECONDS = 3 days;

    function run() external {
        require(block.chainid == MEGAETH_TESTNET_CHAIN_ID, "Wrong network: MegaETH testnet only");

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        uint256 minRaiseNorm = vm.envOr("MIN_RAISE_NORM", uint256(500 ether));
        uint256 maxRaiseNorm = vm.envOr("MAX_RAISE_NORM", uint256(10_000 ether));
        uint256 durationSeconds = vm.envOr("DURATION_SECONDS", DEFAULT_DURATION_SECONDS);
        uint256 launchDelaySeconds = vm.envOr("LAUNCH_DELAY_SECONDS", uint256(60));

        string memory projectName = vm.envOr("PROJECT_NAME", string("Backed testnet raise 10k / 3d"));
        string memory projectDescription = vm.envOr(
            "PROJECT_DESCRIPTION",
            string("Forge script raise: ~10k USDM cap (normalized 18-dec), 3d window, 1m launch delay.")
        );
        string memory projectCategories = vm.envOr("PROJECT_CATEGORIES", string("defi,testing"));
        string memory tokenName = vm.envOr("TOKEN_NAME", string("Backed Test Vault"));
        string memory tokenSymbol = vm.envOr("TOKEN_SYMBOL", string("BTV"));

        AgentRaiseFactory factory = AgentRaiseFactory(FACTORY);
        ITestnetIdentityRegistry registry = ITestnetIdentityRegistry(IDENTITY_REGISTRY);

        require(deployer == factory.ADMIN(), "PRIVATE_KEY must be factory ADMIN for setGlobalConfig + approve");

        vm.startBroadcast(deployerKey);

        (
            ,
            ,
            uint16 platformFeeBps,
            address platformFeeRecipient,
            uint256 minDuration,
            uint256 maxDuration,
            uint256 minLaunchDelay,
            uint256 maxLaunchDelay
        ) = factory.globalConfig();

        AgentRaiseFactory.GlobalConfig memory cfg = AgentRaiseFactory.GlobalConfig({
            minRaise: minRaiseNorm,
            maxRaise: maxRaiseNorm,
            platformFeeBps: platformFeeBps,
            platformFeeRecipient: platformFeeRecipient,
            minDuration: minDuration,
            maxDuration: maxDuration,
            minLaunchDelay: minLaunchDelay,
            maxLaunchDelay: maxLaunchDelay
        });
        factory.setGlobalConfig(cfg);
        console.log("Global min/max raise (18-dec norm):", cfg.minRaise, cfg.maxRaise);

        uint256 agentId = vm.envOr("AGENT_ID", uint256(0));
        if (agentId == 0) {
            string memory agentURI = vm.envOr(
                "AGENT_URI", string.concat("ipfs://backed-forge-", vm.toString(block.timestamp))
            );
            agentId = registry.register(agentURI);
            console.log("Registered new agentId:", agentId);
        } else {
            require(registry.ownerOf(agentId) == deployer, "AGENT_ID not owned by broadcaster");
            console.log("Using existing agentId:", agentId);
        }

        address agentWallet = registry.getAgentWallet(agentId);
        if (agentWallet == address(0)) {
            agentWallet = deployer;
        }

        uint256 launchTime = block.timestamp + launchDelaySeconds;
        uint256 projectId = factory.createAgentRaise(
            agentId,
            projectName,
            projectDescription,
            projectCategories,
            agentWallet,
            USDM,
            durationSeconds,
            launchTime,
            0,
            tokenName,
            tokenSymbol
        );

        factory.approveProject(projectId);

        vm.stopBroadcast();

        AgentRaiseFactory.AgentProject memory project = factory.getProject(projectId);
        console.log("PROJECT_ID=", projectId);
        console.log("AGENT_ID=", agentId);
        console.log("SALE=", project.sale);
        console.log("TREASURY=", project.treasury);
        console.log("LAUNCH_TIME=", launchTime);
        console.log("DURATION_SECONDS=", durationSeconds);
    }
}
