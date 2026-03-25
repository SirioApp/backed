// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";

interface IIdentityRegistry {
    function register(string calldata agentURI) external returns (uint256 agentId);
    function tokenURI(uint256 tokenId) external view returns (string memory);
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract RegisterAgent is Script {
    address constant IDENTITY_REGISTRY = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;
    uint256 private constant MEGAETH_MAINNET_CHAIN_ID = 4326;

    function run() external {
        require(block.chainid == MEGAETH_MAINNET_CHAIN_ID, "Wrong network: mainnet only");
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        string memory agentURI = vm.envString("AGENT_URI");

        console.log("Deployer:", deployer);
        console.log("Registry:", IDENTITY_REGISTRY);
        console.log("URI:", agentURI);

        vm.startBroadcast(deployerKey);

        uint256 agentId = IIdentityRegistry(IDENTITY_REGISTRY).register(agentURI);
        console.log("Agent registered with ID:", agentId);

        vm.stopBroadcast();
    }
}
