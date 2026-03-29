// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {AgentRaiseFactory} from "../src/agents/AgentRaiseFactory.sol";
import {ContractAllowlist} from "../src/registry/ContractAllowlist.sol";

contract DeployNewAgentRaiseFactory is Script {
    address constant ERC8004_IDENTITY_REGISTRY = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;
    address constant SAFE_PROXY_FACTORY = 0xC22834581EbC8527d974F8a1c97E1bEA4EF910BC;
    address constant SAFE_SINGLETON = 0xfb1bffC9d739B8D520DaF37dF666da4C687191EA;
    address constant SAFE_FALLBACK_HANDLER = 0x017062a1dE2FE6b99BE3d9d37841FeD19F573804;
    address constant SAFE_MODULE_SETUP = 0x48Ee6EC061Ec4E5a7708b3fB78f10a66A0Dc11fa;
    address constant INITIAL_COLLATERAL = 0xFAfDdbb3FC7688494971a79cc65DCa3EF82079E7;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerKey);

        ContractAllowlist allowlist = new ContractAllowlist(deployer);
        console.log("ContractAllowlist:", address(allowlist));

        AgentRaiseFactory factory = new AgentRaiseFactory(
            ERC8004_IDENTITY_REGISTRY,
            SAFE_PROXY_FACTORY,
            SAFE_SINGLETON,
            SAFE_FALLBACK_HANDLER,
            SAFE_MODULE_SETUP,
            deployer,
            address(allowlist),
            INITIAL_COLLATERAL
        );
        console.log("AgentRaiseFactory:", address(factory));

        vm.stopBroadcast();
    }
}
