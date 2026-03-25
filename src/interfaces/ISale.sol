// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ISale {
    struct SaleConfigSnapshot {
        uint256 minRaise;
        uint256 maxRaise;
        uint16 platformFeeBps;
        address platformFeeRecipient;
    }

    function finalized() external view returns (bool);
    function failed() external view returns (bool);
    function token() external view returns (address);
    function TREASURY() external view returns (address);
    function FOUNDER() external view returns (address);
    function startTime() external view returns (uint256);
    function endTime() external view returns (uint256);
    function acceptedAmount() external view returns (uint256);
    function totalCommitted() external view returns (uint256);
    function commitments(address user) external view returns (uint256);
    function isActive() external view returns (bool);
}

interface ISaleFactory {
    function SUPER_ADMIN() external view returns (address);
    function isProjectApproved(uint256 projectId) external view returns (bool);
    function maxRaise() external view returns (uint256);
}
