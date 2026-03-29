// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {MockSafe} from "./MockSafe.sol";

contract MockSafeProxyFactory {
    uint256 public safeCount;
    mapping(uint256 => address) public safes;

    error SafeInitFailed();

    function createProxyWithNonce(address, bytes memory initializer, uint256)
        external
        returns (address proxy)
    {
        MockSafe safe = new MockSafe();
        if (initializer.length > 0) {
            (bool ok,) = address(safe).call(initializer);
            if (!ok) revert SafeInitFailed();
        }
        safes[safeCount] = address(safe);
        safeCount++;
        return address(safe);
    }
}
