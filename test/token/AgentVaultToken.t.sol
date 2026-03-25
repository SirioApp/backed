// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {AgentVaultToken} from "../../src/token/AgentVaultToken.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {TOKEN_FIXED_SUPPLY} from "../../src/Constants.sol";

contract AgentVaultTokenTest is Test {
    AgentVaultToken internal vault;
    MockERC20 internal asset;

    address internal sale = makeAddr("sale");
    address internal treasury = makeAddr("treasury");
    address internal platformFeeRecipient = makeAddr("platformFeeRecipient");
    address internal holder1 = makeAddr("holder1");
    address internal holder2 = makeAddr("holder2");
    address internal attacker = makeAddr("attacker");

    uint256 internal constant INITIAL_BALANCE = 1_000_000_000e18;

    function setUp() public {
        asset = new MockERC20("USDM", "USDM", 18);
        vault = new AgentVaultToken(
            address(asset), sale, treasury, 500, platformFeeRecipient, "Agent Token", "AGT"
        );

        asset.mint(sale, INITIAL_BALANCE);
        asset.mint(treasury, INITIAL_BALANCE);
        asset.mint(holder1, INITIAL_BALANCE);
        asset.mint(holder2, INITIAL_BALANCE);
    }

    function test_OnlySaleCanDeposit() public {
        vm.startPrank(holder1);
        asset.approve(address(vault), 1_000e18);
        vm.expectRevert(AgentVaultToken.DepositDisabled.selector);
        vault.deposit(1_000e18, holder1);
        vm.stopPrank();
    }

    function test_Bootstrap_Success() public {
        uint256 amount = 5_000e18;
        vm.startPrank(sale);
        asset.approve(address(vault), amount);
        uint256 shares = vault.bootstrap(amount, sale);
        vm.stopPrank();

        assertEq(shares, TOKEN_FIXED_SUPPLY);
        assertEq(vault.balanceOf(sale), TOKEN_FIXED_SUPPLY);
        assertEq(vault.totalAssets(), amount);
    }

    function test_Bootstrap_RevertsNotSale() public {
        vm.prank(attacker);
        vm.expectRevert(AgentVaultToken.OnlySale.selector);
        vault.bootstrap(1_000e18, attacker);
    }

    function test_Bootstrap_RevertsInvalidAmount() public {
        vm.startPrank(sale);
        vm.expectRevert(AgentVaultToken.InvalidAmount.selector);
        vault.bootstrap(0, sale);

        vm.expectRevert(AgentVaultToken.InvalidAmount.selector);
        vault.bootstrap(1_000e18, address(0));
        vm.stopPrank();
    }

    function test_MintIsDisabled() public {
        vm.prank(sale);
        vm.expectRevert(AgentVaultToken.MintDisabled.selector);
        vault.mint(1_000e18, sale);
    }

    function test_CompleteSale_LocksDeposit() public {
        uint256 amount = 5_000e18;
        vm.startPrank(sale);
        asset.approve(address(vault), amount);
        vault.bootstrap(amount, sale);
        vault.completeSale();
        vm.stopPrank();

        assertTrue(vault.saleCompleted());

        vm.startPrank(sale);
        asset.approve(address(vault), 1_000e18);
        vm.expectRevert(AgentVaultToken.DepositDisabled.selector);
        vault.deposit(1_000e18, sale);
        vm.stopPrank();
    }

    function test_CompleteSale_RevertsNotSale() public {
        vm.prank(attacker);
        vm.expectRevert(AgentVaultToken.OnlySale.selector);
        vault.completeSale();
    }

    function test_CompleteSale_RevertsAlreadyCompleted() public {
        vm.startPrank(sale);
        asset.approve(address(vault), 1_000e18);
        vault.bootstrap(1_000e18, sale);
        vault.completeSale();
        vm.expectRevert(AgentVaultToken.SaleAlreadyCompleted.selector);
        vault.completeSale();
        vm.stopPrank();
    }

    function test_Redeem_Success() public {
        uint256 amount = 5_000e18;
        vm.startPrank(sale);
        asset.approve(address(vault), amount);
        vault.bootstrap(amount, holder1);
        vault.completeSale();
        vm.stopPrank();

        uint256 balBefore = asset.balanceOf(holder1);
        vm.prank(holder1);
        vault.redeem(TOKEN_FIXED_SUPPLY, holder1, holder1);
        assertEq(asset.balanceOf(holder1), balBefore + amount);
    }

    function test_Revenue_IncreasesSharePrice() public {
        uint256 depositAmount = 5_000e18;
        vm.startPrank(sale);
        asset.approve(address(vault), depositAmount);
        vault.bootstrap(depositAmount, holder1);
        vault.completeSale();
        vm.stopPrank();

        assertEq(vault.convertToAssets(TOKEN_FIXED_SUPPLY), depositAmount);

        // Simulate revenue: direct transfer to vault increases totalAssets()
        uint256 revenue = 1_000e18;
        asset.mint(address(vault), revenue);

        assertGt(vault.convertToAssets(TOKEN_FIXED_SUPPLY), depositAmount);
    }

    function test_Bootstrap_RevertsAlreadyBootstrapped() public {
        vm.startPrank(sale);
        asset.approve(address(vault), 2_000e18);
        vault.bootstrap(1_000e18, sale);
        vm.expectRevert(AgentVaultToken.AlreadyBootstrapped.selector);
        vault.bootstrap(1_000e18, sale);
        vm.stopPrank();
    }

    function test_CompleteSale_RevertsNotBootstrapped() public {
        vm.prank(sale);
        vm.expectRevert(AgentVaultToken.NotBootstrapped.selector);
        vault.completeSale();
    }

    function test_Decimals() public view {
        assertEq(vault.decimals(), 18);
    }

    function test_DistributeProfits_RevertsNotTreasury() public {
        vm.prank(attacker);
        vm.expectRevert(AgentVaultToken.OnlyTreasury.selector);
        vault.distributeProfits(1_000e18);
    }

    function test_DistributeProfits_RevertsZeroAmount() public {
        vm.prank(treasury);
        vm.expectRevert(AgentVaultToken.InvalidAmount.selector);
        vault.distributeProfits(0);
    }

    function test_DistributeProfits_Success_WithFee() public {
        uint256 amount = 5_000e18;
        vm.startPrank(sale);
        asset.approve(address(vault), amount);
        vault.bootstrap(amount, holder1);
        vault.completeSale();
        vm.stopPrank();

        uint256 gross = 1_000e18;
        uint256 fee = 50e18;
        uint256 net = 950e18;
        uint256 feeRecipientBefore = asset.balanceOf(platformFeeRecipient);
        uint256 vaultAssetsBefore = vault.totalAssets();

        vm.startPrank(treasury);
        asset.approve(address(vault), gross);
        vault.distributeProfits(gross);
        vm.stopPrank();

        assertEq(asset.balanceOf(platformFeeRecipient), feeRecipientBefore + fee);
        assertEq(vault.totalAssets(), vaultAssetsBefore + net);
    }
}
