// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DataPointRegistry} from "../DataPointRegistry.sol";
import {MinimalisticDataIndex} from "../MinimalisticDataIndex.sol";
import {SampleCallbackDataObject, ISampleCallbackOperations} from "./helpers/SampleCallbackDataObject.sol";
import {TolerantCallbackDataObject, ITolerantCallbackOperations} from "./helpers/TolerantCallbackDataObject.sol";
import {MockCallbackHandler} from "./helpers/MockCallbackHandler.sol";
import {FailingCallbackHandler} from "./helpers/FailingCallbackHandler.sol";
import {ReentrantCallbackHandler} from "./helpers/ReentrantCallbackHandler.sol";
import {EmptyRevertCallbackHandler} from "./helpers/EmptyRevertCallbackHandler.sol";
import {BeforeCallbackDataObject, IBeforeCallbackOperations} from "./helpers/BeforeCallbackDataObject.sol";
import {CallbackProcessorDataObject} from "../utils/CallbackProcessorDataObject.sol";
import {ICallbackProcessorOperations} from "../interfaces/ICallbackProcessorOperations.sol";
import {IDataObject} from "../interfaces/IDataObject.sol";
import {DataPoints, DataPoint} from "../utils/DataPoints.sol";
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

        bytes memory newCtx = abi.encode("updated");
        vm.expectEmit(true, true, true, true);
        emit CallbackProcessorDataObject.CallbackHandlerUpdated(dp, address(mockHandler), uint256(3));
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(mockHandler), uint256(3), newCtx)
        );

        // Verify updated mask and context via getCallbackHandlers
        bytes memory result = dataObject.read(dp, ICallbackProcessorOperations.getCallbackHandlers.selector, "");
        (address[] memory handlers, uint256[] memory masks, bytes[] memory contexts) = abi.decode(result, (address[], uint256[], bytes[]));
        assertEq(handlers.length, 1, "Should still have one handler");
        assertEq(masks[0], 3, "Mask should be updated");
        assertEq(keccak256(contexts[0]), keccak256(newCtx), "Context should be updated");
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

        assertEq(mockHandler.callCount(), 1, "Handler should be called once");
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
        assertEq(mockHandler.callCount(), 0, "Handler should not be called for non-matching task");

        // Task bit 1 - handler SHOULD be called
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ISampleCallbackOperations.execute.selector,
            abi.encode(uint256(1), abi.encode("hello"))
        );
        assertEq(mockHandler.callCount(), 1, "Handler should be called for matching task");
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
        assertEq(mockHandler.callCount(), 1, "Should be called when mask overlaps");
    }

    // --- Multiple handlers with mixed bitmasks ---

    function test_MixedBitmaskFiltering() public {
        MockCallbackHandler handlerA = new MockCallbackHandler();
        MockCallbackHandler handlerB = new MockCallbackHandler();
        MockCallbackHandler handlerC = new MockCallbackHandler();

        // handlerA: mask=1 (bit 0 only)
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(handlerA), uint256(1), "")
        );
        // handlerB: mask=2 (bit 1 only)
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(handlerB), uint256(2), "")
        );
        // handlerC: mask=3 (bits 0 and 1)
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(handlerC), uint256(3), "")
        );

        // Task=1 (bit 0) — should call handlerA and handlerC, skip handlerB
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ISampleCallbackOperations.execute.selector,
            abi.encode(uint256(1), abi.encode("data"))
        );
        assertEq(handlerA.callCount(), 1, "handlerA should be called for task=1");
        assertEq(handlerB.callCount(), 0, "handlerB should not be called for task=1");
        assertEq(handlerC.callCount(), 1, "handlerC should be called for task=1");

        // Task=2 (bit 1) — should call handlerB and handlerC, skip handlerA
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ISampleCallbackOperations.execute.selector,
            abi.encode(uint256(2), abi.encode("data"))
        );
        assertEq(handlerA.callCount(), 1, "handlerA should not be called for task=2");
        assertEq(handlerB.callCount(), 1, "handlerB should be called for task=2");
        assertEq(handlerC.callCount(), 2, "handlerC should be called for task=2");
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

    function test_EmptyRevertReasonUsesCustomError() public {
        EmptyRevertCallbackHandler emptyRevertHandler = new EmptyRevertCallbackHandler();
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(emptyRevertHandler), type(uint256).max, "")
        );

        vm.expectRevert(abi.encodeWithSelector(CallbackProcessorDataObject.CallbackHandlerFailedToProcessCallbackWithoutReason.selector, address(emptyRevertHandler)));
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

        assertEq(mockHandler.callCount(), 1, "Mock handler should be called");
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

    // --- Reentrancy ---

    function test_ReentrantCallbackReverts() public {
        ReentrantCallbackHandler reentrantHandler = new ReentrantCallbackHandler(
            address(dataIndex),
            address(dataObject),
            ISampleCallbackOperations.execute.selector,
            abi.encode(uint256(1), abi.encode("reentrant"))
        );

        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(reentrantHandler), type(uint256).max, "")
        );

        // The reentrant handler is not an approved DataManager, so DataIndex rejects it
        // before the reentrancy guard is even reached
        vm.expectRevert();
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ISampleCallbackOperations.execute.selector,
            abi.encode(uint256(1), abi.encode("trigger"))
        );
    }

    // --- Unregister effectiveness ---

    function test_UnregisteredHandlerIsNotCalled() public {
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(mockHandler), type(uint256).max, "")
        );

        // Execute — handler should be called
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ISampleCallbackOperations.execute.selector,
            abi.encode(uint256(1), abi.encode("first"))
        );
        assertEq(mockHandler.callCount(), 1, "Handler should be called before unregister");

        // Unregister
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.unregisterCallback.selector,
            abi.encode(address(mockHandler))
        );

        // Execute again — handler should NOT be called
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ISampleCallbackOperations.execute.selector,
            abi.encode(uint256(1), abi.encode("second"))
        );
        assertEq(mockHandler.callCount(), 1, "Handler should not be called after unregister");
    }

    // --- Read introspection ---

    function test_GetCallbackHandlersEmpty() public view {
        bytes memory result = dataObject.read(
            dp,
            ICallbackProcessorOperations.getCallbackHandlers.selector,
            ""
        );
        (address[] memory handlers, uint256[] memory masks,) = abi.decode(result, (address[], uint256[], bytes[]));
        assertEq(handlers.length, 0, "Should return empty handlers");
        assertEq(masks.length, 0, "Should return empty masks");
    }

    function test_GetCallbackHandlersReturnsRegistered() public {
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(mockHandler), uint256(42), "")
        );

        bytes memory result = dataObject.read(
            dp,
            ICallbackProcessorOperations.getCallbackHandlers.selector,
            ""
        );
        (address[] memory handlers, uint256[] memory masks,) = abi.decode(result, (address[], uint256[], bytes[]));
        assertEq(handlers.length, 1, "Should return one handler");
        assertEq(handlers[0], address(mockHandler), "Handler address should match");
        assertEq(masks[0], 42, "Mask should match");
    }

    function test_GetCallbackHandlersAfterUnregister() public {
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(mockHandler), type(uint256).max, "")
        );
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.unregisterCallback.selector,
            abi.encode(address(mockHandler))
        );

        bytes memory result = dataObject.read(
            dp,
            ICallbackProcessorOperations.getCallbackHandlers.selector,
            ""
        );
        (address[] memory handlers, uint256[] memory masks,) = abi.decode(result, (address[], uint256[], bytes[]));
        assertEq(handlers.length, 0, "Should return empty after unregister");
        assertEq(masks.length, 0, "Should return empty masks after unregister");
    }

    function test_GetCallbackHandlersMultiple() public {
        MockCallbackHandler secondHandler = new MockCallbackHandler();

        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(mockHandler), uint256(1), "")
        );
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(secondHandler), uint256(2), "")
        );

        bytes memory result = dataObject.read(
            dp,
            ICallbackProcessorOperations.getCallbackHandlers.selector,
            ""
        );
        (address[] memory handlers, uint256[] memory masks,) = abi.decode(result, (address[], uint256[], bytes[]));
        assertEq(handlers.length, 2, "Should return two handlers");
        assertEq(masks.length, 2, "Should return two masks");
    }

    // --- updateCallbackMask ---

    function test_UpdateCallbackMask() public {
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(mockHandler), uint256(1), "")
        );

        vm.expectEmit(true, true, true, true);
        emit CallbackProcessorDataObject.CallbackHandlerUpdated(dp, address(mockHandler), uint256(3));
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.updateCallbackMask.selector,
            abi.encode(address(mockHandler), uint256(3))
        );

        // Verify mask was updated via getCallbackHandlers
        bytes memory result = dataObject.read(dp, ICallbackProcessorOperations.getCallbackHandlers.selector, "");
        (address[] memory handlers, uint256[] memory masks,) = abi.decode(result, (address[], uint256[], bytes[]));
        assertEq(handlers.length, 1);
        assertEq(masks[0], 3, "Mask should be updated to 3");
    }

    function test_UpdateCallbackMaskPreservesContext() public {
        bytes memory ctx = abi.encode("preserved");
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(mockHandler), uint256(1), ctx)
        );

        // Update mask only
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.updateCallbackMask.selector,
            abi.encode(address(mockHandler), uint256(7))
        );

        // Verify context is preserved
        bytes memory result = dataObject.read(dp, ICallbackProcessorOperations.getCallbackHandlers.selector, "");
        (,, bytes[] memory contexts) = abi.decode(result, (address[], uint256[], bytes[]));
        assertEq(keccak256(contexts[0]), keccak256(ctx), "Context should be preserved after mask update");
    }

    function test_UpdateCallbackMaskToZeroDisablesHandler() public {
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(mockHandler), type(uint256).max, "")
        );

        // Set mask to 0
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.updateCallbackMask.selector,
            abi.encode(address(mockHandler), uint256(0))
        );

        // Execute — handler should NOT be called since mask is 0
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ISampleCallbackOperations.execute.selector,
            abi.encode(uint256(1), abi.encode("data"))
        );
        assertEq(mockHandler.callCount(), 0, "Handler with mask 0 should not be called");
    }

    function test_UpdateCallbackMaskRevertsForNonRegisteredHandler() public {
        vm.expectRevert(abi.encodeWithSelector(CallbackProcessorDataObject.CallbackHandlerNotRegistered.selector, address(mockHandler)));
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.updateCallbackMask.selector,
            abi.encode(address(mockHandler), uint256(1))
        );
    }

    // --- DataPoint isolation ---

    function test_HandlersAreIsolatedPerDataPoint() public {
        DataPoint dp2 = registry.allocate(address(this));
        dataObject.setDataIndexImplementation(dp2, address(dataIndex));
        dataIndex.allowDataManager(dp2, address(this), true);

        MockCallbackHandler handler2 = new MockCallbackHandler();

        // Register handler on dp1
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(mockHandler), type(uint256).max, "")
        );
        // Register different handler on dp2
        dataIndex.write(
            IDataObject(address(dataObject)), dp2,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(handler2), type(uint256).max, "")
        );

        // Execute on dp1 — only mockHandler should be called
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ISampleCallbackOperations.execute.selector,
            abi.encode(uint256(1), abi.encode("data"))
        );
        assertEq(mockHandler.callCount(), 1, "dp1 handler should be called");
        assertEq(handler2.callCount(), 0, "dp2 handler should not be called for dp1");

        // Verify dp2 handlers don't include dp1's handler
        bytes memory result = dataObject.read(dp2, ICallbackProcessorOperations.getCallbackHandlers.selector, "");
        (address[] memory handlers,,) = abi.decode(result, (address[], uint256[], bytes[]));
        assertEq(handlers.length, 1, "dp2 should have one handler");
        assertEq(handlers[0], address(handler2), "dp2 handler should be handler2");
    }

    // --- Task zero ---

    function test_TaskZeroCallsNoHandlers() public {
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(mockHandler), type(uint256).max, "")
        );

        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ISampleCallbackOperations.execute.selector,
            abi.encode(uint256(0), abi.encode("data"))
        );
        assertEq(mockHandler.callCount(), 0, "No handler should be called for task=0");
    }

    // --- _beforeProcessCallbacks hook ---

    function test_BeforeProcessCallbacksReceivesCorrectArgs() public {
        BeforeCallbackDataObject beforeDO = new BeforeCallbackDataObject();
        beforeDO.setDataIndexImplementation(dp, address(dataIndex));

        // Register two handlers with different masks
        MockCallbackHandler handlerA = new MockCallbackHandler();
        MockCallbackHandler handlerB = new MockCallbackHandler();

        dataIndex.write(
            IDataObject(address(beforeDO)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(handlerA), uint256(1), "")
        );
        dataIndex.write(
            IDataObject(address(beforeDO)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(handlerB), uint256(2), "")
        );

        // Execute with task=1 — only handlerA should be in the filtered list
        bytes memory taskData = abi.encode("test");
        dataIndex.write(
            IDataObject(address(beforeDO)), dp,
            IBeforeCallbackOperations.execute.selector,
            abi.encode(uint256(1), taskData)
        );

        assertEq(DataPoint.unwrap(beforeDO.lastDp()), DataPoint.unwrap(dp), "dp should match");
        assertEq(beforeDO.lastTask(), 1, "task should be 1");
        assertEq(keccak256(beforeDO.lastTaskData()), keccak256(taskData), "taskData should match");

        address[] memory filteredHandlers = beforeDO.getLastHandlers();
        assertEq(filteredHandlers.length, 1, "Only one handler should match task=1");
        assertEq(filteredHandlers[0], address(handlerA), "Filtered handler should be handlerA");
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
        assertEq(keccak256(receivedCtx), keccak256(ctx), "Context should match");
    }
}
