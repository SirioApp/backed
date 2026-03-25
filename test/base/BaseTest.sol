// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockERC20} from "../mocks/MockERC20.sol";
import {MockSafe} from "../mocks/MockSafe.sol";
import {USDM} from "../../src/Constants.sol";

abstract contract BaseTest is Test {
    uint256 internal constant INITIAL_BALANCE = 1_000_000_000e18;

    address internal constant USDM_ADDRESS = USDM;

    MockERC20 internal usdm;
    MockSafe internal treasury;

    address internal admin;
    address internal founder;
    address internal user1;
    address internal user2;
    address internal user3;
    address internal agentAddress;

    function _setupBase() internal virtual {
        admin = makeAddr("admin");
        founder = makeAddr("founder");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        agentAddress = makeAddr("agentAddress");

        usdm = new MockERC20("USDM", "USDM", 18);
        treasury = new MockSafe();

        usdm.mint(admin, INITIAL_BALANCE);
        usdm.mint(founder, INITIAL_BALANCE);
        usdm.mint(user1, INITIAL_BALANCE);
        usdm.mint(user2, INITIAL_BALANCE);
        usdm.mint(user3, INITIAL_BALANCE);
    }

    function _skipTime(uint256 seconds_) internal { vm.warp(block.timestamp + seconds_); }
    function _skipDays(uint256 days_) internal { vm.warp(block.timestamp + days_ * 1 days); }
    function _setTimestamp(uint256 timestamp) internal { vm.warp(timestamp); }

    function _assertBalance(address token, address account, uint256 expected) internal view {
        assertEq(IERC20(token).balanceOf(account), expected, "Balance mismatch");
    }
}
