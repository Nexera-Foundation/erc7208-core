// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DataPointRegistry} from "./DataPointRegistry.sol";
import {IDataPointRegistry} from "./interfaces/IDataPointRegistry.sol";
import {DataPoints, DataPoint} from "./utils/DataPoints.sol";
import {Test} from "forge-std/Test.sol";

contract DataPointRegistryTest is Test {
    address private constant ACCOUNT_1 = address(1);
    address private constant ACCOUNT_2 = address(2);

    DataPointRegistry public registry;

    function setUp() public {
        registry = new DataPointRegistry();
    }

    // --- Allocation ---

    function test_Allocate() public {
        DataPoint dp = registry.allocate(address(this));
        require(DataPoint.unwrap(dp) != bytes32(0), "Allocated DataPoint should not be empty");
    }

    function test_AllocateMultipleDataPoints() public {
        DataPoint dp1 = registry.allocate(address(this));
        DataPoint dp2 = registry.allocate(address(this));
        require(DataPoint.unwrap(dp1) != DataPoint.unwrap(dp2), "Two allocated DataPoints should be different");
    }

    function test_AllocateForThirdParty() public {
        DataPoint dp = registry.allocate(ACCOUNT_1);
        require(registry.isAdmin(dp, ACCOUNT_1), "Third party should be admin");
        require(!registry.isAdmin(dp, address(this)), "Caller should NOT be admin of third party DP");
    }

    function test_AllocateRevertsOnZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IDataPointRegistry.InvalidOwnerAddress.selector, address(0)));
        registry.allocate(address(0));
    }

    function test_AllocateRevertsOnNativeCoin() public {
        vm.deal(address(this), 1 ether);
        vm.expectRevert(IDataPointRegistry.NativeCoinDepositIsNotAccepted.selector);
        registry.allocate{value: 1}(address(this));
    }

    function test_AllocateEmitsEvent() public {
        vm.expectEmit(false, false, false, false);
        emit IDataPointRegistry.DataPointAllocated(DataPoint.wrap(bytes32(0)), address(this));
        registry.allocate(address(this));
    }

    // --- Owner is Admin ---

    function test_OwnerIsAdminByDefault() public {
        DataPoint dp1 = registry.allocate(address(this));
        require(registry.isAdmin(dp1, address(this)), "Owner should be admin (caller)");

        DataPoint dp2 = registry.allocate(ACCOUNT_1);
        require(registry.isAdmin(dp2, ACCOUNT_1), "Owner should be admin (third party)");
    }

    // --- Ownership Transfer ---

    function test_TransferOwnership() public {
        DataPoint dp = registry.allocate(address(this));
        registry.transferOwnership(dp, ACCOUNT_1);
        require(registry.isAdmin(dp, ACCOUNT_1), "New owner should be admin");
    }

    function test_TransferOwnershipCleansOldAdmins() public {
        DataPoint dp = registry.allocate(address(this));
        registry.grantAdminRole(dp, ACCOUNT_1);
        require(registry.isAdmin(dp, ACCOUNT_1), "Granted admin should be admin");

        registry.transferOwnership(dp, ACCOUNT_2);
        require(!registry.isAdmin(dp, address(this)), "Old owner should not be admin after transfer");
        require(!registry.isAdmin(dp, ACCOUNT_1), "Old admin should not be admin after transfer");
        require(registry.isAdmin(dp, ACCOUNT_2), "New owner should be admin");
    }

    function test_TransferOwnershipRevertsForNonOwner() public {
        DataPoint dp = registry.allocate(address(this));
        vm.prank(ACCOUNT_1);
        vm.expectRevert(abi.encodeWithSelector(IDataPointRegistry.InvalidDataPointOwner.selector, dp, ACCOUNT_1));
        registry.transferOwnership(dp, ACCOUNT_2);
    }

    function test_TransferOwnershipChain() public {
        DataPoint dp = registry.allocate(address(this));
        registry.transferOwnership(dp, ACCOUNT_1);

        vm.prank(ACCOUNT_1);
        registry.transferOwnership(dp, ACCOUNT_2);
        require(registry.isAdmin(dp, ACCOUNT_2), "Final owner should be admin");
        require(!registry.isAdmin(dp, ACCOUNT_1), "Previous owner should not be admin");
    }

    // --- Admin Management ---

    function test_GrantAdminRole() public {
        DataPoint dp = registry.allocate(address(this));
        bool added = registry.grantAdminRole(dp, ACCOUNT_1);
        require(added, "Should return true for new admin");
        require(registry.isAdmin(dp, ACCOUNT_1), "Granted account should be admin");
    }

    function test_GrantAdminRoleReturnsFalseIfAlreadyAdmin() public {
        DataPoint dp = registry.allocate(address(this));
        registry.grantAdminRole(dp, ACCOUNT_1);
        bool added = registry.grantAdminRole(dp, ACCOUNT_1);
        require(!added, "Should return false for existing admin");
    }

    function test_GrantAdminRoleRevertsForNonOwner() public {
        DataPoint dp = registry.allocate(address(this));
        vm.prank(ACCOUNT_1);
        vm.expectRevert(abi.encodeWithSelector(IDataPointRegistry.InvalidDataPointOwner.selector, dp, ACCOUNT_1));
        registry.grantAdminRole(dp, ACCOUNT_2);
    }

    function test_RevokeAdminRole() public {
        DataPoint dp = registry.allocate(address(this));
        registry.grantAdminRole(dp, ACCOUNT_1);
        bool removed = registry.revokeAdminRole(dp, ACCOUNT_1);
        require(removed, "Should return true");
        require(!registry.isAdmin(dp, ACCOUNT_1), "Revoked account should not be admin");
    }

    function test_RevokeAdminRoleReturnsFalseIfNotAdmin() public {
        DataPoint dp = registry.allocate(address(this));
        bool removed = registry.revokeAdminRole(dp, ACCOUNT_1);
        require(!removed, "Should return false for non-admin");
    }

    function test_OwnerCanRevokeOwnAdminAndReGrant() public {
        DataPoint dp = registry.allocate(address(this));
        registry.revokeAdminRole(dp, address(this));
        require(!registry.isAdmin(dp, address(this)), "Owner should not be admin after self-revoke");
        registry.grantAdminRole(dp, address(this));
        require(registry.isAdmin(dp, address(this)), "Owner should be admin again");
    }

    function test_NonAdminIsNotAdmin() public {
        DataPoint dp = registry.allocate(address(this));
        require(!registry.isAdmin(dp, ACCOUNT_1), "Random account should not be admin");
    }
}
