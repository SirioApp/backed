// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {DexRegistry} from "../src/registry/DexRegistry.sol";

/// @title DeployDexRegistry
/// @notice Deploys DexRegistry on MegaETH Mainnet and registers PrismFi + Kumbaya.
contract DeployDexRegistry is Script {
    // ── PrismFi ──
    address constant PRISMFI_V3_FACTORY = 0x1adb8f973373505bB206e0E5D87af8FB1f5514Ef;
    address constant PRISMFI_POSITION_MANAGER = 0xcb91c75a6B29700756d4411495be696c4e9A576E;
    address constant PRISMFI_SWAP_ROUTER = 0xb1f38c36249834D8e3cD582D30101ff4b864f234;

    // ── Kumbaya ──
    address constant KUMBAYA_V3_FACTORY = 0x68b34591f662508076927803c567Cc8006988a09;
    address constant KUMBAYA_POSITION_MANAGER = 0x2b781C57e6358f64864Ff8EC464a03Fdaf9974bA;
    address constant KUMBAYA_SWAP_ROUTER = 0xE5BbEF8De2DB447a7432A47EBa58924d94eE470e;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerKey);

        // 1. Deploy DexRegistry
        DexRegistry registry = new DexRegistry();
        console.log("DexRegistry:", address(registry));

        // 2. Register PrismFi (dexId 0)
        uint256 prismFiId = registry.addDex(PRISMFI_V3_FACTORY, PRISMFI_POSITION_MANAGER, PRISMFI_SWAP_ROUTER);
        console.log("PrismFi dexId:", prismFiId);

        // 3. Register Kumbaya (dexId 1)
        uint256 kumbayaId = registry.addDex(KUMBAYA_V3_FACTORY, KUMBAYA_POSITION_MANAGER, KUMBAYA_SWAP_ROUTER);
        console.log("Kumbaya dexId:", kumbayaId);

        vm.stopBroadcast();

        console.log("");
        console.log("=== DexRegistry Deployed ===");
        console.log("DexRegistry:", address(registry));
        console.log("PrismFi  -> dexId 0");
        console.log("Kumbaya  -> dexId 1");
    }
}
