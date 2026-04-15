// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Sale} from "../../src/launch/Sale.sol";
import {ISale} from "../../src/interfaces/ISale.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {BPS} from "../../src/Constants.sol";

contract MockSaleFactory {
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

    function setMaxRaise(uint256 maxRaise_) external {
        configuredMaxRaise = maxRaise_;
    }

    function SUPER_ADMIN() external view returns (address) {
        return superAdmin;
    }

    function maxRaise() external view returns (uint256) {
        return configuredMaxRaise;
    }
}

contract SaleTest is Test {
    uint256 internal constant INITIAL_BALANCE = 1_000_000_000e18;
    uint256 internal constant SALE_DURATION = 7 days;
    uint256 internal constant MIN_RAISE = 2_500e18;
    uint256 internal constant MAX_RAISE = 10_000e18;
    uint16 internal constant FEE_BPS = 500;

    Sale internal sale;
    MockERC20 internal collateral;
    MockSaleFactory internal mockFactory;

    address internal admin;
    address internal founder;
    address internal treasury;
    address internal user1;
    address internal user2;
    address internal user3;
    address internal anyone;
    address internal feeRecipient;

    function setUp() public {
        admin = makeAddr("admin");
        founder = makeAddr("founder");
        treasury = makeAddr("treasury");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        anyone = makeAddr("anyone");
        feeRecipient = makeAddr("feeRecipient");

        collateral = new MockERC20("USDM", "USDM", 18);
        mockFactory = new MockSaleFactory(admin, MAX_RAISE);

        uint256 launchTime = block.timestamp + 1 days;

        sale = new Sale(
            address(collateral),
            treasury,
            founder,
            SALE_DURATION,
            launchTime,
            0,
            "Token",
            "TKN",
            address(mockFactory),
            ISale.SaleConfigSnapshot({
                minRaise: MIN_RAISE,
                maxRaise: MAX_RAISE,
                platformFeeBps: FEE_BPS,
                platformFeeRecipient: feeRecipient
            }),
            0
        );

        mockFactory.setProjectApproved(0, true);

        collateral.mint(user1, INITIAL_BALANCE);
        collateral.mint(user2, INITIAL_BALANCE);
        collateral.mint(user3, INITIAL_BALANCE);
    }

    // ─── commit ─────────────────────────────────────────────────────────

    function test_Commit_Success() public {
        vm.warp(block.timestamp + 1 days);
        uint256 amount = 5_000e18;
        vm.startPrank(user1);
        collateral.approve(address(sale), amount);
        sale.commit(amount);
        vm.stopPrank();

        assertEq(sale.commitments(user1), amount);
        assertEq(sale.totalCommitted(), amount);
    }

    function test_Commit_RevertsBeforeLaunch() public {
        vm.startPrank(user1);
        collateral.approve(address(sale), 1_000e18);
        vm.expectRevert(Sale.NotActive.selector);
        sale.commit(1_000e18);
        vm.stopPrank();
    }

    function test_Commit_RevertsZeroAmount() public {
        vm.warp(block.timestamp + 1 days);
        vm.prank(user1);
        vm.expectRevert(Sale.ZeroAmount.selector);
        sale.commit(0);
    }

    function test_Commit_RevertsNotApproved() public {
        mockFactory.setProjectApproved(0, false);
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(user1);
        collateral.approve(address(sale), 1_000e18);
        vm.expectRevert(Sale.NotApproved.selector);
        sale.commit(1_000e18);
        vm.stopPrank();
    }

    function test_Commit_AllowsOverMaxRaise() public {
        vm.warp(block.timestamp + 1 days);
        // Over-commitment is allowed; excess refunded pro-rata at claim
        uint256 amount = MAX_RAISE + 1_000e18;
        vm.startPrank(user1);
        collateral.approve(address(sale), amount);
        sale.commit(amount);
        vm.stopPrank();
        assertEq(sale.totalCommitted(), amount);
    }

    function test_MultipleCommits() public {
        vm.warp(block.timestamp + 1 days);
        uint256 amount = 1_000e18;
        vm.startPrank(user1);
        collateral.approve(address(sale), amount * 2);
        sale.commit(amount);
        sale.commit(amount);
        vm.stopPrank();
        assertEq(sale.commitments(user1), amount * 2);
        assertEq(sale.totalCommitted(), amount * 2);
    }

    // ─── finalize ────────────────────────────────────────────────────────

    function test_Finalize_FailsIfZeroCommitted() public {
        vm.warp(block.timestamp + 1 days + SALE_DURATION);
        sale.finalize();
        assertTrue(sale.failed());
    }

    function test_Finalize_CallableByAnyone() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(user1);
        collateral.approve(address(sale), 3_000e18);
        sale.commit(3_000e18);
        vm.stopPrank();

        vm.warp(block.timestamp + SALE_DURATION);
        vm.prank(anyone);
        sale.finalize();
        assertTrue(sale.finalized());
        assertFalse(sale.failed());
    }

    function test_Finalize_RevertsBeforeEnd() public {
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(Sale.NotReady.selector);
        sale.finalize();
    }

    function test_Finalize_RevertsAlreadyFinalized() public {
        vm.warp(block.timestamp + 1 days + SALE_DURATION);
        sale.finalize();
        vm.expectRevert(Sale.AlreadyFinalized.selector);
        sale.finalize();
    }

    function test_Finalize_FailsUnderMinRaise() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(user1);
        collateral.approve(address(sale), 1_000e18);
        sale.commit(1_000e18);
        vm.stopPrank();

        vm.warp(block.timestamp + SALE_DURATION);
        sale.finalize();
        assertTrue(sale.finalized());
        assertTrue(sale.failed());
        assertEq(sale.acceptedAmount(), 1_000e18);
    }

    function test_Constructor_RevertsFeeAtBps() public {
        vm.expectRevert(Sale.InvalidConfig.selector);
        new Sale(
            address(collateral),
            treasury,
            founder,
            SALE_DURATION,
            block.timestamp + 1 days,
            0,
            "Token",
            "TKN",
            address(mockFactory),
            ISale.SaleConfigSnapshot({
                minRaise: MIN_RAISE,
                maxRaise: MAX_RAISE,
                platformFeeBps: 10_000,
                platformFeeRecipient: feeRecipient
            }),
            9
        );
    }

    // ─── emergencyRefund ─────────────────────────────────────────────────

    function test_EmergencyRefund() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(user1);
        collateral.approve(address(sale), 1_000e18);
        sale.commit(1_000e18);
        vm.stopPrank();

        vm.warp(block.timestamp + SALE_DURATION);
        vm.prank(admin);
        sale.emergencyRefund();

        assertTrue(sale.finalized());
        assertTrue(sale.failed());
    }

    function test_EmergencyRefund_BeforeEndTime() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(user1);
        collateral.approve(address(sale), 1_000e18);
        sale.commit(1_000e18);
        vm.stopPrank();

        // No extra warp: still before endTime
        vm.prank(admin);
        sale.emergencyRefund();

        assertTrue(sale.finalized());
        assertTrue(sale.failed());
    }

    function test_EmergencyRefund_BlocksFurtherCommits() public {
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        sale.emergencyRefund();

        vm.startPrank(user1);
        collateral.approve(address(sale), 1_000e18);
        vm.expectRevert(Sale.AlreadyFinalized.selector);
        sale.commit(1_000e18);
        vm.stopPrank();
    }

    function test_EmergencyRefund_RevertsNotAdmin() public {
        vm.warp(block.timestamp + 1 days);
        vm.prank(anyone);
        vm.expectRevert(Sale.Unauthorized.selector);
        sale.emergencyRefund();
    }

    // ─── refund ──────────────────────────────────────────────────────────

    function test_Refund_AfterFailed() public {
        vm.warp(block.timestamp + 1 days);
        uint256 amount = 1_000e18;
        vm.startPrank(user1);
        collateral.approve(address(sale), amount);
        sale.commit(amount);
        vm.stopPrank();

        vm.prank(admin);
        sale.emergencyRefund();

        uint256 balBefore = collateral.balanceOf(user1);
        vm.prank(user1);
        sale.refund();
        assertEq(collateral.balanceOf(user1), balBefore + amount);
    }

    function test_Refund_RevertsNoCommitment() public {
        // finalize with zero commits → failed = true; user with no commitment gets NothingToClaim
        vm.warp(block.timestamp + 1 days + SALE_DURATION);
        sale.finalize();
        assertTrue(sale.failed());
        vm.prank(user1);
        vm.expectRevert(Sale.NothingToClaim.selector);
        sale.refund();
    }

    function test_Refund_RevertsNotFinalized() public {
        // Sale not yet finalized → RefundNotAvailable
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(user1);
        collateral.approve(address(sale), 1_000e18);
        sale.commit(1_000e18);
        vm.stopPrank();

        vm.prank(user1);
        vm.expectRevert(Sale.RefundNotAvailable.selector);
        sale.refund();
    }

    function test_Refund_RevertsAlreadyRefunded() public {
        vm.warp(block.timestamp + 1 days);
        uint256 amount = 1_000e18;
        vm.startPrank(user1);
        collateral.approve(address(sale), amount);
        sale.commit(amount);
        vm.stopPrank();

        vm.warp(block.timestamp + SALE_DURATION);
        vm.prank(admin);
        sale.emergencyRefund();

        vm.prank(user1);
        sale.refund();
        vm.prank(user1);
        vm.expectRevert(Sale.AlreadyRefunded.selector);
        sale.refund();
    }

    function test_Finalize_CapsAtMaxRaise() public {
        vm.warp(block.timestamp + 1 days);

        vm.startPrank(user1);
        collateral.approve(address(sale), 7_000e18);
        sale.commit(7_000e18);
        vm.stopPrank();

        vm.startPrank(user2);
        collateral.approve(address(sale), 8_000e18);
        sale.commit(8_000e18);
        vm.stopPrank();

        vm.warp(block.timestamp + SALE_DURATION);
        sale.finalize();

        assertEq(sale.acceptedAmount(), MAX_RAISE);
        assertEq(sale.totalSharesMinted(), MAX_RAISE);
    }

    function test_Claim_DistributesSharesAndRefundsExcess() public {
        vm.warp(block.timestamp + 1 days);

        vm.startPrank(user1);
        collateral.approve(address(sale), 6_000e18);
        sale.commit(6_000e18);
        vm.stopPrank();

        vm.startPrank(user2);
        collateral.approve(address(sale), 8_000e18);
        sale.commit(8_000e18);
        vm.stopPrank();

        vm.warp(block.timestamp + SALE_DURATION);
        sale.finalize();

        (uint256 claimableShares, uint256 refundAmt) = sale.getClaimable(user1);
        uint256 user1UsdmBefore = collateral.balanceOf(user1);
        vm.recordLogs();
        vm.prank(user1);
        sale.claim();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 user1Delta = collateral.balanceOf(user1) - user1UsdmBefore;
        assertEq(user1Delta, refundAmt);
        assertEq(IERC20(sale.token()).balanceOf(user1), claimableShares);

        bytes32 withdrawTopic = keccak256("Withdraw(address,address,address,uint256,uint256)");
        for (uint256 i = 0; i < entries.length; ++i) {
            if (entries[i].emitter == sale.token()) {
                assertTrue(entries[i].topics[0] != withdrawTopic);
            }
        }
    }

    function test_Claim_RevertsAlreadyClaimed() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(user1);
        collateral.approve(address(sale), 3_000e18);
        sale.commit(3_000e18);
        vm.stopPrank();

        vm.warp(block.timestamp + SALE_DURATION);
        sale.finalize();

        vm.prank(user1);
        sale.claim();

        vm.prank(user1);
        vm.expectRevert(Sale.AlreadyClaimed.selector);
        sale.claim();
    }

    function test_Claim_RevertsNothingToClaim() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(user1);
        collateral.approve(address(sale), 3_000e18);
        sale.commit(3_000e18);
        vm.stopPrank();

        vm.warp(block.timestamp + SALE_DURATION);
        sale.finalize();

        vm.prank(user2);
        vm.expectRevert(Sale.NothingToClaim.selector);
        sale.claim();
    }

    function test_GetClaimable_ReturnsSharesAndRefund() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(user1);
        collateral.approve(address(sale), 3_000e18);
        sale.commit(3_000e18);
        vm.stopPrank();

        vm.warp(block.timestamp + SALE_DURATION);
        sale.finalize();

        (uint256 payoutShares, uint256 refundAmt) = sale.getClaimable(user1);
        assertGt(payoutShares, 0);
        assertEq(refundAmt, 0);
    }

    function test_Token_IsZeroBeforeFinalize_ThenSetAfterFinalize() public {
        assertEq(sale.token(), address(0));

        vm.warp(block.timestamp + 1 days);
        vm.startPrank(user1);
        collateral.approve(address(sale), 3_000e18);
        sale.commit(3_000e18);
        vm.stopPrank();

        vm.warp(block.timestamp + SALE_DURATION);
        sale.finalize();

        assertTrue(sale.token() != address(0));
    }

    function test_Finalize_AllowsAfterProjectRevoked() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(user1);
        collateral.approve(address(sale), 3_000e18);
        sale.commit(3_000e18);
        vm.stopPrank();

        mockFactory.setProjectApproved(0, false);
        vm.warp(block.timestamp + SALE_DURATION);
        sale.finalize();
        assertTrue(sale.finalized());
        assertFalse(sale.failed());
    }

    function test_Claim_RefundTotalBoundedByOverflow() public {
        uint256 launchTime = block.timestamp + 1 days;
        Sale smallSale = new Sale(
            address(collateral),
            treasury,
            founder,
            SALE_DURATION,
            launchTime,
            0,
            "Small",
            "SML",
            address(mockFactory),
            ISale.SaleConfigSnapshot({
                minRaise: 1, maxRaise: 5, platformFeeBps: 0, platformFeeRecipient: feeRecipient
            }),
            1
        );
        mockFactory.setProjectApproved(1, true);

        vm.warp(launchTime);

        vm.startPrank(user1);
        collateral.approve(address(smallSale), 2);
        smallSale.commit(2);
        vm.stopPrank();

        vm.startPrank(user2);
        collateral.approve(address(smallSale), 2);
        smallSale.commit(2);
        vm.stopPrank();

        vm.startPrank(user3);
        collateral.approve(address(smallSale), 2);
        smallSale.commit(2);
        vm.stopPrank();

        vm.warp(launchTime + SALE_DURATION);
        smallSale.finalize();

        vm.prank(user1);
        smallSale.claim();
        vm.prank(user2);
        smallSale.claim();
        vm.prank(user3);
        smallSale.claim();

        // overflow = totalCommitted - acceptedAmount = 6 - 5 = 1
        assertEq(smallSale.totalRefundedAmount(), 1);
    }

    // ─── view ────────────────────────────────────────────────────────────

    function test_IsActive() public {
        assertFalse(sale.isActive());
        vm.warp(block.timestamp + 1 days);
        assertTrue(sale.isActive());
        vm.warp(block.timestamp + SALE_DURATION);
        assertFalse(sale.isActive());
    }

    function test_TimeRemaining() public {
        vm.warp(block.timestamp + 1 days);
        assertGt(sale.timeRemaining(), 0);
        vm.warp(block.timestamp + SALE_DURATION);
        assertEq(sale.timeRemaining(), 0);
    }

    function test_GetStatus() public view {
        (uint256 committed, uint256 accepted, bool fin, bool fail) = sale.getStatus();
        assertEq(committed, 0);
        assertEq(accepted, 0);
        assertFalse(fin);
        assertFalse(fail);
    }

    function test_GetRefundable_OnlyWhenFailedAndNotRefunded() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(user1);
        collateral.approve(address(sale), 1_000e18);
        sale.commit(1_000e18);
        vm.stopPrank();

        vm.prank(admin);
        sale.emergencyRefund();

        assertEq(sale.getRefundable(user1), 1_000e18);

        vm.prank(user1);
        sale.refund();
        assertEq(sale.getRefundable(user1), 0);
    }
}

contract FeeOnTransferERC20 is MockERC20 {
    uint16 public immutable FEE_BPS;

    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint16 feeBps_)
        MockERC20(name_, symbol_, decimals_)
    {
        FEE_BPS = feeBps_;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _transferWithFee(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 currentAllowance = allowance(from, msg.sender);
        require(currentAllowance >= amount, "ERC20: insufficient allowance");
        if (currentAllowance != type(uint256).max) {
            _approve(from, msg.sender, currentAllowance - amount);
        }
        _transferWithFee(from, to, amount);
        return true;
    }

    function _transferWithFee(address from, address to, uint256 amount) internal {
        uint256 fee = (amount * FEE_BPS) / BPS;
        uint256 received = amount - fee;
        super._transfer(from, to, received);
        if (fee > 0) {
            super._transfer(from, address(0xdead), fee);
        }
    }
}

contract SaleFeeOnTransferTest is Test {
    uint256 internal constant SALE_DURATION = 7 days;

    Sale internal sale;
    FeeOnTransferERC20 internal collateral;
    MockSaleFactory internal mockFactory;

    address internal admin = makeAddr("admin");
    address internal founder = makeAddr("founder");
    address internal treasury = makeAddr("treasury");
    address internal user = makeAddr("user");
    address internal feeRecipient = makeAddr("feeRecipient");

    function setUp() public {
        collateral = new FeeOnTransferERC20("USDM", "USDM", 18, 100); // 1%
        mockFactory = new MockSaleFactory(admin, 10_000e18);

        sale = new Sale(
            address(collateral),
            treasury,
            founder,
            SALE_DURATION,
            block.timestamp + 1 days,
            0,
            "Token",
            "TKN",
            address(mockFactory),
            ISale.SaleConfigSnapshot({
                minRaise: 100e18,
                maxRaise: 10_000e18,
                platformFeeBps: 500,
                platformFeeRecipient: feeRecipient
            }),
            0
        );
        mockFactory.setProjectApproved(0, true);
        collateral.mint(user, 1_000e18);
    }

    function test_Commit_RevertsOnTransferTaxCollateral() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(user);
        collateral.approve(address(sale), 1_000e18);
        vm.expectRevert(Sale.InvalidCollateralBehavior.selector);
        sale.commit(1_000e18);
        vm.stopPrank();
    }

    function test_Commit_RevertsWhenNetReceivedIsZero() public {
        FeeOnTransferERC20 fullFee = new FeeOnTransferERC20("USDM", "USDM", 18, 10_000);
        Sale zeroNetSale = new Sale(
            address(fullFee),
            treasury,
            founder,
            SALE_DURATION,
            block.timestamp + 1 days,
            0,
            "Token",
            "TKN",
            address(mockFactory),
            ISale.SaleConfigSnapshot({
                minRaise: 100e18,
                maxRaise: 10_000e18,
                platformFeeBps: 500,
                platformFeeRecipient: feeRecipient
            }),
            2
        );
        mockFactory.setProjectApproved(2, true);
        fullFee.mint(user, 1_000e18);

        vm.warp(block.timestamp + 1 days);
        vm.startPrank(user);
        fullFee.approve(address(zeroNetSale), 100e18);
        vm.expectRevert(Sale.InvalidCollateralTransfer.selector);
        zeroNetSale.commit(100e18);
        vm.stopPrank();
    }
}
