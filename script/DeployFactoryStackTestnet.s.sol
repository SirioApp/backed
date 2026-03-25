// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {SafeModuleSetup} from "../src/safe/SafeModuleSetup.sol";
import {ContractAllowlist} from "../src/registry/ContractAllowlist.sol";
import {AgentRaiseFactory} from "../src/agents/AgentRaiseFactory.sol";

contract DeployFactoryStackTestnet is Script {
    uint256 private constant MEGAETH_TESTNET_CHAIN_ID = 6343;

    address constant ERC8004_IDENTITY_REGISTRY = 0x8004A818BFB912233c491871b3d84c89A494BD9e;
    address constant SAFE_PROXY_FACTORY = 0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67;
    address constant SAFE_SINGLETON = 0x29fcB43b46531BcA003ddC8FCB67FFE91900C762;
    address constant SAFE_FALLBACK_HANDLER = 0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99;
    address constant INITIAL_COLLATERAL = 0x9f5A17BD53310D012544966b8e3cF7863fc8F05f;

    function run() external {
        require(block.chainid == MEGAETH_TESTNET_CHAIN_ID, "Wrong network: testnet only");

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("Deployer:", deployer);
        console.log("IdentityRegistry:", ERC8004_IDENTITY_REGISTRY);

        vm.startBroadcast(deployerKey);

        SafeModuleSetup safeModuleSetup = new SafeModuleSetup();
        console.log("SafeModuleSetup:", address(safeModuleSetup));

        ContractAllowlist allowlist = new ContractAllowlist(deployer);
        console.log("ContractAllowlist:", address(allowlist));

        AgentRaiseFactory factory = new AgentRaiseFactory(
            ERC8004_IDENTITY_REGISTRY,
            SAFE_PROXY_FACTORY,
            SAFE_SINGLETON,
            SAFE_FALLBACK_HANDLER,
            address(safeModuleSetup),
            deployer,
            address(allowlist),
            INITIAL_COLLATERAL
        );
        console.log("AgentRaiseFactory:", address(factory));

        vm.stopBroadcast();
    }
}
