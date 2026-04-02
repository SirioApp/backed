// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {AgentVaultToken} from "../../src/token/AgentVaultToken.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract AgentVaultTokenTest is Test {
    AgentVaultToken internal token;
    MockERC20 internal asset;

    address internal sale = makeAddr("sale");
    address internal treasury = makeAddr("treasury");
    address internal platformFeeRecipient = makeAddr("platformFeeRecipient");
    address internal holder1 = makeAddr("holder1");
    address internal holder2 = makeAddr("holder2");
    address internal attacker = makeAddr("attacker");

    uint256 internal constant INITIAL_BALANCE = 1_000_000_000e18;
    uint256 internal lockupEndTime;

    function setUp() public {
        asset = new MockERC20("USDM", "USDM", 18);
        lockupEndTime = block.timestamp + 1 days;
        token = new AgentVaultToken(
            address(asset),
            sale,
            treasury,
            500,
            platformFeeRecipient,
            lockupEndTime,
            "Agent Fund",
            "AGF"
        );

        asset.mint(treasury, INITIAL_BALANCE);
        asset.mint(holder1, INITIAL_BALANCE);
        asset.mint(holder2, INITIAL_BALANCE);
    }

    function test_Bootstrap_MintsFixedSupplyWithoutCustody() public {
        uint256 amount = 5_000e18;

        vm.prank(sale);
        uint256 shares = token.bootstrap(amount, sale);

        assertEq(shares, amount);
        assertEq(token.balanceOf(sale), amount);
        assertEq(token.totalSupply(), amount);
        assertEq(token.totalAssets(), 0);
        assertEq(asset.balanceOf(address(token)), 0);
    }

    function test_Bootstrap_UsesOneToOneInitialPriceForSixDecimalAsset() public {
        MockERC20 sixDecimalAsset = new MockERC20("USDM", "USDM", 6);
        AgentVaultToken sixDecimalToken = new AgentVaultToken(
            address(sixDecimalAsset),
            sale,
            treasury,
            500,
            platformFeeRecipient,
            lockupEndTime,
            "Agent Fund",
            "AGF"
        );

        vm.prank(sale);
        uint256 shares = sixDecimalToken.bootstrap(5_000e6, sale);

        assertEq(shares, 5_000e18);
        assertEq(sixDecimalToken.decimals(), 18);
        assertEq(sixDecimalToken.convertToAssets(1e18), 0);
    }

    function test_Bootstrap_RevertsNotSale() public {
        vm.prank(attacker);
        vm.expectRevert(AgentVaultToken.OnlySale.selector);
        token.bootstrap(1_000e18, attacker);
    }

    function test_Bootstrap_RevertsInvalidAmount() public {
        vm.startPrank(sale);
        vm.expectRevert(AgentVaultToken.InvalidAmount.selector);
        token.bootstrap(0, sale);

        vm.expectRevert(AgentVaultToken.InvalidAmount.selector);
        token.bootstrap(1_000e18, address(0));
        vm.stopPrank();
    }

    function test_Bootstrap_RevertsAlreadyBootstrapped() public {
        vm.startPrank(sale);
        token.bootstrap(1_000e18, sale);
        vm.expectRevert(AgentVaultToken.AlreadyBootstrapped.selector);
        token.bootstrap(1_000e18, sale);
        vm.stopPrank();
    }

    function test_CompleteSale_RevertsNotBootstrapped() public {
        vm.prank(sale);
        vm.expectRevert(AgentVaultToken.NotBootstrapped.selector);
        token.completeSale();
    }

    function test_CompleteSale_RevertsNotSale() public {
        vm.prank(attacker);
        vm.expectRevert(AgentVaultToken.OnlySale.selector);
        token.completeSale();
    }

    function test_CompleteSale_RevertsAlreadyCompleted() public {
        vm.startPrank(sale);
        token.bootstrap(1_000e18, sale);
        token.completeSale();
        vm.expectRevert(AgentVaultToken.SaleAlreadyCompleted.selector);
        token.completeSale();
        vm.stopPrank();
    }

    function test_FinalizeSettlement_RevertsBeforeLockupEnds() public {
        vm.startPrank(sale);
        token.bootstrap(5_000e18, sale);
        token.completeSale();
        vm.stopPrank();

        vm.prank(treasury);
        vm.expectRevert(
            abi.encodeWithSelector(AgentVaultToken.LockupActive.selector, lockupEndTime)
        );
        token.finalizeSettlement();
    }

    function test_FinalizeSettlement_RevertsNotTreasury() public {
        vm.startPrank(sale);
        token.bootstrap(5_000e18, sale);
        token.completeSale();
        vm.stopPrank();

        vm.warp(lockupEndTime);
        vm.prank(attacker);
        vm.expectRevert(AgentVaultToken.OnlyTreasury.selector);
        token.finalizeSettlement();
    }

    function test_FinalizeSettlement_SettlesAssetsAndChargesFeeOnlyOnProfit() public {
        vm.startPrank(sale);
        token.bootstrap(5_000e18, holder1);
        token.completeSale();
        vm.stopPrank();

        asset.mint(address(token), 6_000e18);

        vm.warp(lockupEndTime);
        uint256 feeRecipientBefore = asset.balanceOf(platformFeeRecipient);
        vm.prank(treasury);
        token.finalizeSettlement();

        assertTrue(token.settled());
        assertEq(token.settledShareSupply(), 5_000e18);
        assertEq(token.totalAssets(), 5_950e18);
        assertEq(asset.balanceOf(platformFeeRecipient), feeRecipientBefore + 50e18);
        assertEq(token.convertToAssets(1e18), 1_190_000_000_000_000_000);
    }

    function test_Redeem_SucceedsAfterSettlement() public {
        vm.startPrank(sale);
        token.bootstrap(5_000e18, holder1);
        token.completeSale();
        vm.stopPrank();

        asset.mint(address(token), 5_500e18);

        vm.warp(lockupEndTime);
        vm.prank(treasury);
        token.finalizeSettlement();

        uint256 holderBefore = asset.balanceOf(holder1);
        vm.prank(holder1);
        uint256 assetsOut = token.redeem(5_000e18, holder1, holder1);

        assertEq(assetsOut, 5_475e18);
        assertEq(asset.balanceOf(holder1), holderBefore + 5_475e18);
        assertEq(token.balanceOf(holder1), 0);
        assertEq(token.totalAssets(), 0);
    }

    function test_Redeem_RevertsBeforeSettlement() public {
        vm.startPrank(sale);
        token.bootstrap(5_000e18, holder1);
        token.completeSale();
        vm.stopPrank();

        vm.warp(lockupEndTime);
        vm.prank(holder1);
        vm.expectRevert(AgentVaultToken.SettlementNotFinalized.selector);
        token.redeem(5_000e18, holder1, holder1);
    }

    function test_Withdraw_UsesCeilSharesAndLeavesNoDustForLastRedeemer() public {
        AgentVaultToken feeFreeToken = new AgentVaultToken(
            address(asset),
            sale,
            treasury,
            0,
            platformFeeRecipient,
            lockupEndTime,
            "Fee Free Fund",
            "FFF"
        );

        vm.startPrank(sale);
        feeFreeToken.bootstrap(3_000e18, holder1);
        feeFreeToken.completeSale();
        vm.stopPrank();

        vm.prank(holder1);
        feeFreeToken.transfer(holder2, 1_000e18);

        asset.mint(address(feeFreeToken), 3_333e18);

        vm.warp(lockupEndTime);
        vm.prank(treasury);
        feeFreeToken.finalizeSettlement();

        uint256 holder2Before = asset.balanceOf(holder2);
        vm.prank(holder2);
        uint256 burnedShares = feeFreeToken.withdraw(1_111e18, holder2, holder2);

        assertEq(burnedShares, 1_000e18);
        assertEq(asset.balanceOf(holder2), holder2Before + 1_111e18);
        assertEq(feeFreeToken.balanceOf(holder2), 0);
        assertEq(feeFreeToken.totalAssets(), 2_222e18);

        uint256 holder1Before = asset.balanceOf(holder1);
        uint256 holder1Shares = feeFreeToken.balanceOf(holder1);
        vm.prank(holder1);
        uint256 redeemedAssets = feeFreeToken.redeem(holder1Shares, holder1, holder1);

        assertEq(redeemedAssets, 2_222e18);
        assertEq(asset.balanceOf(holder1), holder1Before + 2_222e18);
        assertEq(feeFreeToken.totalAssets(), 0);
    }

    function test_MaxRedeemAndMaxWithdraw_AreZeroUntilSettlementOpens() public {
        vm.startPrank(sale);
        token.bootstrap(5_000e18, holder1);
        token.completeSale();
        vm.stopPrank();

        assertEq(token.maxRedeem(holder1), 0);
        assertEq(token.maxWithdraw(holder1), 0);

        asset.mint(address(token), 5_000e18);
        vm.warp(lockupEndTime);
        vm.prank(treasury);
        token.finalizeSettlement();

        assertEq(token.maxRedeem(holder1), 5_000e18);
        assertEq(token.maxWithdraw(holder1), 5_000e18);
    }

    function test_Decimals() public view {
        assertEq(token.decimals(), 18);
    }
}
