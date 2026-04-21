// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

contract MegaEthTestnetIntegrationTest is Test {
    uint256 internal constant MEGAETH_TESTNET_CHAIN_ID = 6343;

    address internal constant ERC8004_IDENTITY_REGISTRY =
        0x8004A818BFB912233c491871b3d84c89A494BD9e;
    address internal constant SAFE_PROXY_FACTORY = 0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67;
    address internal constant SAFE_SINGLETON = 0x29fcB43b46531BcA003ddC8FCB67FFE91900C762;
    address internal constant SAFE_FALLBACK_HANDLER = 0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99;
    address internal constant USDM = 0x9f5A17BD53310D012544966b8e3cF7863fc8F05f;

    function testFork_TestnetContracts_AreDeployedAndReachable() public {
        vm.createSelectFork(vm.rpcUrl("megaeth-testnet"));

        assertEq(block.chainid, MEGAETH_TESTNET_CHAIN_ID);
        assertGt(ERC8004_IDENTITY_REGISTRY.code.length, 0);
        assertGt(SAFE_PROXY_FACTORY.code.length, 0);
        assertGt(SAFE_SINGLETON.code.length, 0);
        assertGt(SAFE_FALLBACK_HANDLER.code.length, 0);
        assertGt(USDM.code.length, 0);
    }
}
