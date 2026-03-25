// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DataPointRegistry} from "../DataPointRegistry.sol";
import {MinimalisticDataIndex} from "../MinimalisticDataIndex.sol";
import {SampleDataObject} from "../examples/SampleDataObject.sol";
import {ISampleDataObjectOperations} from "../examples/SampleDataObject.sol";
import {DataPoints, DataPoint} from "../utils/DataPoints.sol";
import {BaseDataObject} from "../utils/BaseDataObject.sol";
import {IBaseDataObject} from "../interfaces/IBaseDataObject.sol";
import {IDataIndex} from "../interfaces/IDataIndex.sol";
import {IDataObject} from "../interfaces/IDataObject.sol";
import {Test} from "forge-std/Test.sol";

contract BaseDataObjectTest is Test {
    DataPointRegistry public registry;
    MinimalisticDataIndex public dataIndex;
    SampleDataObject public dataObject;

    DataPoint dp;

    function setUp() public {
        registry = new DataPointRegistry();
        dataIndex = new MinimalisticDataIndex();
        dataObject = new SampleDataObject();

        dp = registry.allocate(address(this));
        dataObject.setDataIndexImplementation(dp, address(dataIndex));
        dataIndex.allowDataManager(dp, address(this), true);
    }

    // --- Dispatch Read ---

    function test_DispatchReadValue() public view {
        bytes memory result = dataObject.read(dp, ISampleDataObjectOperations.value.selector, "");
        require(abi.decode(result, (uint256)) == 0, "Default value should be 0");
    }

    function test_DispatchReadUnsupportedOperation() public {
        vm.expectRevert(abi.encodeWithSelector(BaseDataObject.UnsupportedReadOperation.selector, bytes4(0xdeadbeef)));
        dataObject.read(dp, bytes4(0xdeadbeef), "");
    }

    // --- Dispatch Write ---

    function test_DispatchWriteSet() public {
        dataIndex.write(IDataObject(address(dataObject)), dp, ISampleDataObjectOperations.set.selector, abi.encode(uint256(100)));
        bytes memory result = dataObject.read(dp, ISampleDataObjectOperations.value.selector, "");
        require(abi.decode(result, (uint256)) == 100, "Value should be 100");
    }

    function test_DispatchWriteInc() public {
        dataIndex.write(IDataObject(address(dataObject)), dp, ISampleDataObjectOperations.set.selector, abi.encode(uint256(5)));
        bytes memory result = dataIndex.write(IDataObject(address(dataObject)), dp, ISampleDataObjectOperations.inc.selector, "");
        require(abi.decode(result, (uint256)) == 6, "Inc should return 6");
    }

    function test_DispatchWriteDec() public {
        dataIndex.write(IDataObject(address(dataObject)), dp, ISampleDataObjectOperations.set.selector, abi.encode(uint256(5)));
        bytes memory result = dataIndex.write(IDataObject(address(dataObject)), dp, ISampleDataObjectOperations.dec.selector, "");
        require(abi.decode(result, (uint256)) == 4, "Dec should return 4");
    }

    function test_DispatchWriteCompareAndSet() public {
        dataIndex.write(IDataObject(address(dataObject)), dp, ISampleDataObjectOperations.set.selector, abi.encode(uint256(10)));

        bytes memory result = dataIndex.write(IDataObject(address(dataObject)), dp, ISampleDataObjectOperations.compareAndSet.selector, abi.encode(uint256(10), uint256(20)));
        require(abi.decode(result, (bool)) == true, "CAS should succeed");

        result = dataIndex.write(IDataObject(address(dataObject)), dp, ISampleDataObjectOperations.compareAndSet.selector, abi.encode(uint256(10), uint256(30)));
        require(abi.decode(result, (bool)) == false, "CAS should fail on mismatch");
    }

    function test_DispatchWriteUnsupportedOperation() public {
        vm.prank(address(dataIndex));
        vm.expectRevert(abi.encodeWithSelector(BaseDataObject.UnsupportedWriteOperation.selector, bytes4(0xdeadbeef)));
        dataObject.write(dp, bytes4(0xdeadbeef), "");
    }

    // --- onlyDataIndex modifier ---

    function test_WriteRevertsIfNotCalledByDataIndex() public {
        vm.expectRevert(abi.encodeWithSelector(IBaseDataObject.InvalidCaller.selector, dp, address(this)));
        dataObject.write(dp, ISampleDataObjectOperations.set.selector, abi.encode(uint256(1)));
    }

    // --- Native payment ---

    function test_WriteRevertsOnNativePayment() public {
        vm.deal(address(dataIndex), 1 ether);
        vm.prank(address(dataIndex));
        vm.expectRevert(IBaseDataObject.NativePaymentNotSupported.selector);
        dataObject.write{value: 1}(dp, ISampleDataObjectOperations.set.selector, abi.encode(uint256(1)));
    }

    // --- DataIndex management ---

    function test_SetDefaultDataIndex() public {
        dataObject.setDefaultDataIndexImplementation(address(dataIndex));
        require(dataObject.defaultDataIndex() == address(dataIndex), "Default DI should be set");
    }

    function test_SetDefaultDataIndexToZero() public {
        dataObject.setDefaultDataIndexImplementation(address(dataIndex));
        dataObject.setDefaultDataIndexImplementation(address(0));
        require(dataObject.defaultDataIndex() == address(0), "Default DI should be zero");
    }

    function test_SetDefaultDataIndexRevertsForNonAdmin() public {
        vm.prank(address(0x999));
        vm.expectRevert();
        dataObject.setDefaultDataIndexImplementation(address(dataIndex));
    }

    function test_OverrideDataIndex() public view {
        require(dataObject.overrideDataIndex(dp) == address(dataIndex), "Override DI should be set for dp");
    }

    function test_DataIndexReturnsOverrideWhenSet() public view {
        require(dataObject.dataIndex(dp) == address(dataIndex), "dataIndex() should return override");
    }

    function test_DataIndexFallsBackToDefault() public {
        DataPoint dp2 = registry.allocate(address(this));
        dataObject.setDefaultDataIndexImplementation(address(dataIndex));
        require(dataObject.dataIndex(dp2) == address(dataIndex), "Should fall back to default DI");
    }

    function test_DataIndexRevertsWhenNoneSet() public {
        DataPoint dp2 = registry.allocate(address(this));
        vm.expectRevert(abi.encodeWithSelector(IBaseDataObject.DataIndexImplementationNotSet.selector, dp2));
        dataObject.dataIndex(dp2);
    }

    function test_SetDataIndexByDPAdmin() public {
        DataPoint dp2 = registry.allocate(address(this));
        dataObject.setDataIndexImplementation(dp2, address(dataIndex));
        require(dataObject.overrideDataIndex(dp2) == address(dataIndex), "DI should be set");
    }

    function test_SetDataIndexRevertsForNonIDataIndexAddress() public {
        DataPoint dp2 = registry.allocate(address(this));
        vm.expectRevert();
        dataObject.setDataIndexImplementation(dp2, address(0xBEEF));
    }

    function test_SetDataIndexRevertsForNonAdmin() public {
        DataPoint dp2 = registry.allocate(address(this));
        vm.prank(address(0x999));
        vm.expectRevert(abi.encodeWithSelector(IBaseDataObject.InvalidCaller.selector, dp2, address(0x999)));
        dataObject.setDataIndexImplementation(dp2, address(dataIndex));
    }

    function test_UpdateDataIndexByCurrentDI() public {
        MinimalisticDataIndex dataIndex2 = new MinimalisticDataIndex();
        vm.prank(address(dataIndex));
        dataObject.setDataIndexImplementation(dp, address(dataIndex2));
        require(dataObject.overrideDataIndex(dp) == address(dataIndex2), "DI should be updated");
    }

    function test_IncBoundaryRevert() public {
        dataIndex.write(IDataObject(address(dataObject)), dp, ISampleDataObjectOperations.set.selector, abi.encode(type(uint256).max));
        vm.expectRevert(ISampleDataObjectOperations.ValueCanNotBeIncremented.selector);
        dataIndex.write(IDataObject(address(dataObject)), dp, ISampleDataObjectOperations.inc.selector, "");
    }

    function test_DecBoundaryRevert() public {
        vm.expectRevert(ISampleDataObjectOperations.ValueCanNotBeDecremented.selector);
        dataIndex.write(IDataObject(address(dataObject)), dp, ISampleDataObjectOperations.dec.selector, "");
    }
}
