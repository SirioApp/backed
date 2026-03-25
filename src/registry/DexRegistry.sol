// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IDexRegistry} from "../interfaces/IDexRegistry.sol";

contract DexRegistry is IDexRegistry {
    address public immutable ADMIN;
    uint256 public dexCount;
    mapping(uint256 => DexConfig) internal _dexes;

    modifier onlyAdmin() {
        if (msg.sender != ADMIN) revert Unauthorized();
        _;
    }

    constructor() {
        ADMIN = msg.sender;
    }

    function addDex(
        address v3Factory,
        address positionManager,
        address swapRouter
    ) external onlyAdmin returns (uint256 dexId) {
        if (v3Factory == address(0)) revert InvalidAddress();
        if (positionManager == address(0)) revert InvalidAddress();
        if (swapRouter == address(0)) revert InvalidAddress();

        dexId = dexCount++;
        _dexes[dexId] = DexConfig({
            v3Factory: v3Factory,
            positionManager: positionManager,
            swapRouter: swapRouter,
            active: true
        });

        emit DexAdded(dexId, v3Factory, positionManager, swapRouter);
    }

    function deactivateDex(uint256 dexId) external onlyAdmin {
        if (dexId >= dexCount) revert DexNotFound();
        if (!_dexes[dexId].active) revert DexAlreadyInactive();
        _dexes[dexId].active = false;
        emit DexDeactivated(dexId);
    }

    function getDex(uint256 dexId) external view returns (DexConfig memory) {
        if (dexId >= dexCount) revert DexNotFound();
        if (!_dexes[dexId].active) revert DexNotActive();
        return _dexes[dexId];
    }
}
