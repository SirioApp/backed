// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";

import {Sale} from "../../src/launch/Sale.sol";
import {ISale} from "../../src/interfaces/ISale.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract InvariantSaleFactory {
    address public superAdmin;
    mapping(uint256 => bool) public approvedProjects;
    uint256 public configuredMaxRaise;

    constructor(address admin_, uint256 maxRaise_) {
        superAdmin = admin_;
        configuredMaxRaise = maxRaise_;
    }

    function isProjectApproved(uint256 projectId) external view returns (bool) {
        return approvedProjects[projectId];
    }

    function setProjectApproved(uint256 projectId, bool approved) external {
        approvedProjects[projectId] = approved;
    }

    function SUPER_ADMIN() external view returns (address) {
        return superAdmin;
    }

    function maxRaise() external view returns (uint256) {
        return configuredMaxRaise;
    }
}

contract SaleHandler is Test {
    Sale internal sale;
    MockERC20 internal collateral;
    address[] internal users;
    address internal admin;

    constructor(Sale sale_, MockERC20 collateral_, address admin_, address[] memory users_) {
        sale = sale_;
        collateral = collateral_;
        admin = admin_;
        users = users_;
    }

    function commit(uint8 userIndex, uint96 amountRaw) external {
        address user = users[userIndex % users.length];
        uint256 amount = bound(uint256(amountRaw), 1e18, 2_500e18);
        vm.startPrank(user);
        collateral.approve(address(sale), amount);
        try sale.commit(amount) {} catch {}
        vm.stopPrank();
    }

    function finalize() external {
        try sale.finalize() {} catch {}
    }

    function claim(uint8 userIndex) external {
        address user = users[userIndex % users.length];
        vm.prank(user);
        try sale.claim() {} catch {}
    }

    function refund(uint8 userIndex) external {
        address user = users[userIndex % users.length];
        vm.prank(user);
        try sale.refund() {} catch {}
    }

    function emergencyRefund() external {
        vm.prank(admin);
        try sale.emergencyRefund() {} catch {}
    }
}

contract SaleInvariantsTest is StdInvariant, Test {
    uint256 internal constant SALE_DURATION = 7 days;

    Sale internal sale;
    MockERC20 internal collateral;
    InvariantSaleFactory internal factory;
    SaleHandler internal handler;

    address internal admin = makeAddr("admin");
    address internal founder = makeAddr("founder");
    address internal treasury = makeAddr("treasury");
    address internal feeRecipient = makeAddr("feeRecipient");
    address internal user1 = makeAddr("user1");
    address internal user2 = makeAddr("user2");
    address internal user3 = makeAddr("user3");

    function setUp() public {
        collateral = new MockERC20("USDM", "USDM", 18);
        factory = new InvariantSaleFactory(admin, 10_000e18);

        sale = new Sale(
            address(collateral),
            treasury,
            founder,
            SALE_DURATION,
            block.timestamp + 1 days,
            0,
            "Invariant",
            "INV",
            address(factory),
            ISale.SaleConfigSnapshot({
                minRaise: 2_500e18,
                maxRaise: 10_000e18,
                platformFeeBps: 500,
                platformFeeRecipient: feeRecipient
            }),
            0
        );
        factory.setProjectApproved(0, true);

        collateral.mint(user1, 1_000_000e18);
        collateral.mint(user2, 1_000_000e18);
        collateral.mint(user3, 1_000_000e18);
        vm.warp(block.timestamp + 1 days + 1);

        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        handler = new SaleHandler(sale, collateral, admin, users);
        targetContract(address(handler));
    }

    function invariant_AcceptedNeverExceedsCommitted() public view {
        assertLe(sale.acceptedAmount(), sale.totalCommitted());
    }

    function invariant_OverflowRefundNeverExceedsOverflow() public view {
        uint256 committed = sale.totalCommitted();
        uint256 accepted = sale.acceptedAmount();
        if (committed > accepted) {
            assertLe(sale.totalRefundedAmount(), committed - accepted);
        } else {
            assertEq(sale.totalRefundedAmount(), 0);
        }
    }
}
