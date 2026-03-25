// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ISale} from "../../src/interfaces/ISale.sol";

contract MockSale is ISale {
    bool public override finalized = true;
    bool public override failed = false;
    address public override token;
    address private _treasury;
    address private _founder;
    uint256 private _startTime;
    uint256 private _endTime;
    uint256 public override acceptedAmount;
    uint256 public override totalCommitted;
    bool private _active;
    mapping(address => uint256) public override commitments;

    function setFinalized(bool _finalized) external {
        finalized = _finalized;
    }

    function setFailed(bool _failed) external {
        failed = _failed;
    }

    function setToken(address _token) external {
        token = _token;
    }

    function setTreasury(address treasury_) external {
        _treasury = treasury_;
    }

    function setFounder(address founder_) external {
        _founder = founder_;
    }

    function setStartTime(uint256 startTime_) external {
        _startTime = startTime_;
    }

    function setEndTime(uint256 endTime_) external {
        _endTime = endTime_;
    }

    function setAcceptedAmount(uint256 amount_) external {
        acceptedAmount = amount_;
    }

    function setTotalCommitted(uint256 amount_) external {
        totalCommitted = amount_;
    }

    function setIsActive(bool active_) external {
        _active = active_;
    }

    function setCommitment(address user, uint256 amount) external {
        commitments[user] = amount;
    }

    function TREASURY() external view override returns (address) {
        return _treasury;
    }

    function FOUNDER() external view override returns (address) {
        return _founder;
    }

    function startTime() external view override returns (uint256) {
        return _startTime;
    }

    function endTime() external view override returns (uint256) {
        return _endTime;
    }

    function isActive() external view override returns (bool) {
        return _active;
    }
}
