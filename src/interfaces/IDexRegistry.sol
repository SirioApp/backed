// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IDexRegistry {
    struct DexConfig {
        address v3Factory;
        address positionManager;
        address swapRouter;
        bool active;
    }

    error InvalidAddress();
    error DexNotFound();
    error DexNotActive();
    error DexAlreadyInactive();
    error Unauthorized();

    event DexAdded(uint256 indexed dexId, address v3Factory, address positionManager, address swapRouter);
    event DexDeactivated(uint256 indexed dexId);

    function addDex(address v3Factory, address positionManager, address swapRouter) external returns (uint256 dexId);
    function deactivateDex(uint256 dexId) external;
    function getDex(uint256 dexId) external view returns (DexConfig memory);
    function dexCount() external view returns (uint256);
}
