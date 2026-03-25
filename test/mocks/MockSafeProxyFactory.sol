// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {MockSafe} from "./MockSafe.sol";

contract MockSafeProxyFactory {
    uint256 public safeCount;
    mapping(uint256 => address) public safes;

    function createProxyWithNonce(
        address,
        bytes memory,
        uint256
    ) external returns (address proxy) {
        MockSafe safe = new MockSafe();
        safes[safeCount] = address(safe);
        safeCount++;
        return address(safe);
    }
}
