// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev Default collateral used in deployment scripts and local tooling presets.
address constant USDM = 0x9f5A17BD53310D012544966b8e3cF7863fc8F05f;

uint256 constant BPS = 10_000;

/// @dev Default minimum accepted raise in normalized 18 decimals (scaled per collateral decimals).
uint256 constant DEFAULT_MIN_RAISE = 2_500e18;

/// @dev Default maximum accepted raise in normalized 18 decimals (scaled per collateral decimals).
uint256 constant DEFAULT_MAX_RAISE = 10_000e18;

/// @dev Default platform fee in basis points (5%).
uint16 constant DEFAULT_PLATFORM_FEE_BPS = 500;
