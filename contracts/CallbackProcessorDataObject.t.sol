// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DataPointRegistry} from "./DataPointRegistry.sol";
import {MinimalisticDataIndex} from "./MinimalisticDataIndex.sol";
import {SampleCallbackDataObject, ISampleCallbackOperations} from "./test-helpers/SampleCallbackDataObject.sol";
import {TolerantCallbackDataObject, ITolerantCallbackOperations} from "./test-helpers/TolerantCallbackDataObject.sol";
import {MockCallbackHandler} from "./test-helpers/MockCallbackHandler.sol";
import {FailingCallbackHandler} from "./test-helpers/FailingCallbackHandler.sol";
import {CallbackProcessorDataObject} from "./utils/CallbackProcessorDataObject.sol";
import {ICallbackProcessorOperations} from "./interfaces/ICallbackProcessorOperations.sol";
import {IDataObject} from "./interfaces/IDataObject.sol";
import {DataPoints, DataPoint} from "./utils/DataPoints.sol";
import {Test} from "forge-std/Test.sol";

contract CallbackProcessorDataObjectTest is Test {
    DataPointRegistry public registry;
    MinimalisticDataIndex public dataIndex;
    SampleCallbackDataObject public dataObject;
    MockCallbackHandler public mockHandler;
    FailingCallbackHandler public failHandler;

    DataPoint dp;

    function setUp() public {
        registry = new DataPointRegistry();
        dataIndex = new MinimalisticDataIndex();
        dataObject = new SampleCallbackDataObject();
        mockHandler = new MockCallbackHandler();
        failHandler = new FailingCallbackHandler();

        dp = registry.allocate(address(this));
        dataObject.setDataIndexImplementation(dp, address(dataIndex));
        dataIndex.allowDataManager(dp, address(this), true);
    }

    // --- Registration ---

    function test_RegisterCallbackHandler() public {
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(mockHandler), type(uint256).max, "")
        );
    }

    function test_RegisterCallbackEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit CallbackProcessorDataObject.CallbackHandlerRegistered(dp, address(mockHandler), type(uint256).max);
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(mockHandler), type(uint256).max, "")
        );
    }

    function test_RegisterCallbackRevertsForNonERC165() public {
        vm.expectRevert(abi.encodeWithSelector(CallbackProcessorDataObject.CallbackHandlerDoesNotSupportCallbackInterface.selector, address(0x1234)));
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(0x1234), type(uint256).max, "")
        );
    }

    function test_UpdateExistingHandler() public {
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(mockHandler), uint256(1), "")
        );

        vm.expectEmit(true, true, true, true);
        emit CallbackProcessorDataObject.CallbackHandlerUpdated(dp, address(mockHandler), uint256(3));
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(mockHandler), uint256(3), "")
        );
    }

    // --- Unregistration ---

    function test_UnregisterHandler() public {
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(mockHandler), type(uint256).max, "")
        );

        vm.expectEmit(true, true, true, true);
        emit CallbackProcessorDataObject.CallbackHandlerUnregistered(dp, address(mockHandler));
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.unregisterCallback.selector,
            abi.encode(address(mockHandler))
        );
    }

    function test_UnregisterNonExistentHandlerReverts() public {
        vm.expectRevert(abi.encodeWithSelector(CallbackProcessorDataObject.CallbackHandlerNotRegistered.selector, address(mockHandler)));
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.unregisterCallback.selector,
            abi.encode(address(mockHandler))
        );
    }

    // --- Callback Execution ---

    function test_CallbackHandlerIsCalled() public {
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(mockHandler), type(uint256).max, "")
        );

        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ISampleCallbackOperations.execute.selector,
            abi.encode(uint256(1), abi.encode("hello"))
        );

        require(mockHandler.callCount() == 1, "Handler should be called once");
    }

    function test_CallbackBitmaskFiltering() public {
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(mockHandler), uint256(1), "")
        );

        // Task bit 2 - handler should NOT be called
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ISampleCallbackOperations.execute.selector,
            abi.encode(uint256(2), abi.encode("hello"))
        );
        require(mockHandler.callCount() == 0, "Handler should not be called for non-matching task");

        // Task bit 1 - handler SHOULD be called
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ISampleCallbackOperations.execute.selector,
            abi.encode(uint256(1), abi.encode("hello"))
        );
        require(mockHandler.callCount() == 1, "Handler should be called for matching task");
    }

    function test_CallbackBitmaskOverlap() public {
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(mockHandler), uint256(3), "")
        );

        // Task 0x02 (bit 1) - should match because 3 & 2 != 0
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ISampleCallbackOperations.execute.selector,
            abi.encode(uint256(2), abi.encode("data"))
        );
        require(mockHandler.callCount() == 1, "Should be called when mask overlaps");
    }

    // --- Failure Propagation ---

    function test_FailingHandlerRevertsTransaction() public {
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(failHandler), type(uint256).max, "")
        );

        vm.expectRevert(abi.encodeWithSelector(FailingCallbackHandler.HandlerFailed.selector, "intentional failure"));
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ISampleCallbackOperations.execute.selector,
            abi.encode(uint256(1), abi.encode("data"))
        );
    }

    // --- Tolerant Failure Mode ---

    function test_TolerantHandlerSwallowsFailure() public {
        TolerantCallbackDataObject tolerantDO = new TolerantCallbackDataObject();
        tolerantDO.setDataIndexImplementation(dp, address(dataIndex));

        dataIndex.write(
            IDataObject(address(tolerantDO)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(mockHandler), type(uint256).max, "")
        );
        dataIndex.write(
            IDataObject(address(tolerantDO)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(failHandler), type(uint256).max, "")
        );

        vm.expectEmit(true, true, true, true);
        emit CallbackProcessorDataObject.CallbacksProcessed(dp, uint256(1), 1, 1);
        dataIndex.write(
            IDataObject(address(tolerantDO)), dp,
            ITolerantCallbackOperations.execute.selector,
            abi.encode(uint256(1), abi.encode("data"))
        );

        require(mockHandler.callCount() == 1, "Mock handler should be called");
    }

    // --- No handlers registered ---

    function test_ExecuteWithNoHandlers() public {
        vm.expectEmit(true, true, true, true);
        emit CallbackProcessorDataObject.CallbacksProcessed(dp, uint256(1), 0, 0);
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ISampleCallbackOperations.execute.selector,
            abi.encode(uint256(1), abi.encode("data"))
        );
    }

    // --- Context passing ---

    function test_ContextIsPassedToHandler() public {
        bytes memory ctx = abi.encode("myContext");
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(mockHandler), type(uint256).max, ctx)
        );

        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ISampleCallbackOperations.execute.selector,
            abi.encode(uint256(1), abi.encode("taskdata"))
        );

        (, , bytes memory receivedCtx) = mockHandler.calls(0);
        require(keccak256(receivedCtx) == keccak256(ctx), "Context should match");
    }
}
