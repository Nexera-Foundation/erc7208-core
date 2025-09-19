// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DataPointRegistry} from "./DataPointRegistry.sol";
import {DataPoints, DataPoint} from "./utils/DataPoints.sol";
import {Test} from "forge-std/Test.sol";

// Solidity tests are compatible with foundry, so they
// use the same syntax and offer the same functionality.

contract DataPointRegistryTest is Test {
    address private constant ACCOUNT_1 = address(1);

    DataPointRegistry public registry;

    function setUp() public {
        registry = new DataPointRegistry();
    }

    function test_Allocate() public {
        DataPoint dp = registry.allocate(address(this));
        require(DataPoint.unwrap(dp) != bytes32(0), "Allocated DataPoint should not be empty");
    }

    function test_OwnerIsAdminByDefault() public {
        // Allocated for caller
        DataPoint dp1 = registry.allocate(address(this));
        require(registry.isAdmin(dp1, address(this)), "Owner of allocated DataPoint should be admin by default (caller)");

        // Allocated for third party
        DataPoint dp2 = registry.allocate(ACCOUNT_1);
        require(registry.isAdmin(dp2, ACCOUNT_1), "Owner of allocated DataPoint should be admin by default (third party)");
    }

    function test_TransferOwnership() public {
        // First transfer
        DataPoint dp = registry.allocate(address(this));
        registry.transferOwnership(dp, ACCOUNT_1);
        require(registry.isAdmin(dp, ACCOUNT_1), "Transferred DataPoint should be owned by new owner");

        // Second transfer
        vm.prank(ACCOUNT_1);
        registry.transferOwnership(dp, address(this));
        require(registry.isAdmin(dp, address(this)), "DataPoint transferred twice should be owned by new owner");
    }

    // TODO Add more tests
}
