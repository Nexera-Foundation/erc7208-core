// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DataPointRegistry} from "./DataPointRegistry.sol";
import {MinimalisticDataIndex} from "./MinimalisticDataIndex.sol";
import {SampleDataObject} from "./examples/SampleDataObject.sol";
import {ISampleDataObjectOperations} from "./examples/SampleDataObject.sol";
import {DataPoints, DataPoint} from "./utils/DataPoints.sol";
import {IDataIndex} from "./interfaces/IDataIndex.sol";
import {IDataObject} from "./interfaces/IDataObject.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Test} from "forge-std/Test.sol";

contract MinimalisticDataIndexTest is Test {
    DataPointRegistry public registry;
    MinimalisticDataIndex public dataIndex;
    SampleDataObject public dataObject;

    address constant DATA_MANAGER = address(0x1234);
    address constant NON_ADMIN = address(0x5678);

    DataPoint dp;

    function setUp() public {
        registry = new DataPointRegistry();
        dataIndex = new MinimalisticDataIndex();
        dataObject = new SampleDataObject();

        dp = registry.allocate(address(this));
        dataObject.setDataIndexImplementation(dp, address(dataIndex));
    }

    // --- ERC165 ---

    function test_SupportsIDataIndex() public view {
        require(dataIndex.supportsInterface(type(IDataIndex).interfaceId), "Should support IDataIndex");
    }

    function test_SupportsIERC165() public view {
        require(dataIndex.supportsInterface(type(IERC165).interfaceId), "Should support IERC165");
    }

    // --- Approval ---

    function test_AllowDataManager() public {
        dataIndex.allowDataManager(dp, DATA_MANAGER, true);
        require(dataIndex.isApprovedDataManager(dp, DATA_MANAGER), "DM should be approved");
    }

    function test_RevokeDataManager() public {
        dataIndex.allowDataManager(dp, DATA_MANAGER, true);
        dataIndex.allowDataManager(dp, DATA_MANAGER, false);
        require(!dataIndex.isApprovedDataManager(dp, DATA_MANAGER), "DM should not be approved after revocation");
    }

    function test_AllowDataManagerRevertsForNonAdmin() public {
        vm.prank(NON_ADMIN);
        vm.expectRevert(abi.encodeWithSelector(MinimalisticDataIndex.InvalidDataPointAdmin.selector, dp, NON_ADMIN));
        dataIndex.allowDataManager(dp, DATA_MANAGER, true);
    }

    function test_UnapprovedDMIsNotApproved() public view {
        require(!dataIndex.isApprovedDataManager(dp, DATA_MANAGER), "Non-approved DM should not be approved");
    }

    // --- Admin revocation invalidates DM ---

    function test_AdminRevocationInvalidatesDMApproval() public {
        address secondAdmin = address(0xAA);
        registry.grantAdminRole(dp, secondAdmin);

        vm.prank(secondAdmin);
        dataIndex.allowDataManager(dp, DATA_MANAGER, true);
        require(dataIndex.isApprovedDataManager(dp, DATA_MANAGER), "DM should be approved by second admin");

        registry.revokeAdminRole(dp, secondAdmin);
        require(!dataIndex.isApprovedDataManager(dp, DATA_MANAGER), "DM should lose approval when approving admin is revoked");
    }

    // --- Read (passthrough) ---

    function test_ReadPassthrough() public view {
        bytes memory result = dataIndex.read(IDataObject(address(dataObject)), dp, ISampleDataObjectOperations.value.selector, "");
        uint256 val = abi.decode(result, (uint256));
        require(val == 0, "Default value should be 0");
    }

    // --- Write (gated) ---

    function test_WriteAsApprovedDM() public {
        dataIndex.allowDataManager(dp, DATA_MANAGER, true);

        vm.prank(DATA_MANAGER);
        dataIndex.write(IDataObject(address(dataObject)), dp, ISampleDataObjectOperations.set.selector, abi.encode(uint256(42)));

        bytes memory result = dataIndex.read(IDataObject(address(dataObject)), dp, ISampleDataObjectOperations.value.selector, "");
        uint256 val = abi.decode(result, (uint256));
        require(val == 42, "Value should be 42 after write");
    }

    function test_WriteRevertsForUnapprovedDM() public {
        vm.prank(DATA_MANAGER);
        vm.expectRevert(abi.encodeWithSelector(MinimalisticDataIndex.DataManagerNotApproved.selector, dp, DATA_MANAGER));
        dataIndex.write(IDataObject(address(dataObject)), dp, ISampleDataObjectOperations.set.selector, abi.encode(uint256(42)));
    }

    // --- Multiple DMs ---

    function test_MultipleDMsCanBeApproved() public {
        address dm2 = address(0x9999);
        dataIndex.allowDataManager(dp, DATA_MANAGER, true);
        dataIndex.allowDataManager(dp, dm2, true);

        require(dataIndex.isApprovedDataManager(dp, DATA_MANAGER), "DM1 should be approved");
        require(dataIndex.isApprovedDataManager(dp, dm2), "DM2 should be approved");
    }

    // --- Multiple DataPoints ---

    function test_ApprovalsArePerDataPoint() public {
        DataPoint dp2 = registry.allocate(address(this));
        dataIndex.allowDataManager(dp, DATA_MANAGER, true);

        require(dataIndex.isApprovedDataManager(dp, DATA_MANAGER), "DM should be approved for dp");
        require(!dataIndex.isApprovedDataManager(dp2, DATA_MANAGER), "DM should NOT be approved for dp2");
    }
}
