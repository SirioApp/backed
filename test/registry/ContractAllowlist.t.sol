// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ContractAllowlist} from "../../src/registry/ContractAllowlist.sol";

contract ContractAllowlistTest is Test {
    ContractAllowlist internal allowlist;
    address internal admin = makeAddr("admin");
    address internal notAdmin = makeAddr("notAdmin");
    address internal target1 = makeAddr("target1");
    address internal target2 = makeAddr("target2");
    address internal target3 = makeAddr("target3");

    function setUp() public {
        allowlist = new ContractAllowlist(admin);
    }

    function test_constructorSetsAdmin() public view {
        assertEq(allowlist.admin(), admin);
    }

    function test_constructorRevertsZeroAdmin() public {
        vm.expectRevert(ContractAllowlist.InvalidAddress.selector);
        new ContractAllowlist(address(0));
    }

    function test_addContract() public {
        vm.prank(admin);
        allowlist.addContract(target1);
        assertTrue(allowlist.isAllowed(target1));
    }

    function test_addContractEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit ContractAllowlist.ContractAdded(target1);
        allowlist.addContract(target1);
    }

    function test_addContractRevertsNotAdmin() public {
        vm.prank(notAdmin);
        vm.expectRevert(ContractAllowlist.Unauthorized.selector);
        allowlist.addContract(target1);
    }

    function test_addContractRevertsZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(ContractAllowlist.InvalidAddress.selector);
        allowlist.addContract(address(0));
    }

    function test_addContractRevertsAlreadyAllowed() public {
        vm.startPrank(admin);
        allowlist.addContract(target1);
        vm.expectRevert(ContractAllowlist.AlreadyAllowed.selector);
        allowlist.addContract(target1);
        vm.stopPrank();
    }

    function test_removeContract() public {
        vm.startPrank(admin);
        allowlist.addContract(target1);
        allowlist.removeContract(target1);
        vm.stopPrank();
        assertFalse(allowlist.isAllowed(target1));
    }

    function test_removeContractRevertsNotAllowed() public {
        vm.prank(admin);
        vm.expectRevert(ContractAllowlist.NotAllowed.selector);
        allowlist.removeContract(target1);
    }

    function test_addContracts() public {
        address[] memory targets = new address[](3);
        targets[0] = target1;
        targets[1] = target2;
        targets[2] = target3;

        vm.prank(admin);
        allowlist.addContracts(targets);

        assertTrue(allowlist.isAllowed(target1));
        assertTrue(allowlist.isAllowed(target2));
        assertTrue(allowlist.isAllowed(target3));
    }

    function test_removeContracts() public {
        address[] memory targets = new address[](2);
        targets[0] = target1;
        targets[1] = target2;

        vm.startPrank(admin);
        allowlist.addContracts(targets);
        allowlist.removeContracts(targets);
        vm.stopPrank();

        assertFalse(allowlist.isAllowed(target1));
        assertFalse(allowlist.isAllowed(target2));
    }

    function test_transferAdmin() public {
        address newAdmin = makeAddr("newAdmin");
        vm.prank(admin);
        allowlist.transferAdmin(newAdmin);
        assertEq(allowlist.admin(), newAdmin);
    }

    function test_transferAdminRevertsZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(ContractAllowlist.InvalidAddress.selector);
        allowlist.transferAdmin(address(0));
    }

    function test_transferAdminRevertsNotAdmin() public {
        vm.prank(notAdmin);
        vm.expectRevert(ContractAllowlist.Unauthorized.selector);
        allowlist.transferAdmin(notAdmin);
    }

    function test_previousAdminLosesAccess() public {
        address newAdmin = makeAddr("newAdmin");
        vm.prank(admin);
        allowlist.transferAdmin(newAdmin);

        vm.prank(admin);
        vm.expectRevert(ContractAllowlist.Unauthorized.selector);
        allowlist.addContract(target1);
    }
}
