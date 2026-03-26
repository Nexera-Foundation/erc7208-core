// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DataPointRegistry} from "../DataPointRegistry.sol";
import {MinimalisticDataIndex} from "../MinimalisticDataIndex.sol";
import {SampleCallbackDataObjectUpgradeable, ISampleCallbackUpgradeableOperations} from "./helpers/SampleCallbackDataObjectUpgradeable.sol";
import {MockCallbackHandler} from "./helpers/MockCallbackHandler.sol";
import {FailingCallbackHandler} from "./helpers/FailingCallbackHandler.sol";
import {ReentrantCallbackHandler} from "./helpers/ReentrantCallbackHandler.sol";
import {EmptyRevertCallbackHandler} from "./helpers/EmptyRevertCallbackHandler.sol";
import {CallbackProcessorDataObjectUpgradeable} from "../utils/CallbackProcessorDataObjectUpgradeable.sol";
import {ICallbackProcessorOperations} from "../interfaces/ICallbackProcessorOperations.sol";
import {IDataObject} from "../interfaces/IDataObject.sol";
import {DataPoints, DataPoint} from "../utils/DataPoints.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";

contract CallbackProcessorDataObjectUpgradeableTest is Test {
    DataPointRegistry public registry;
    MinimalisticDataIndex public dataIndex;
    SampleCallbackDataObjectUpgradeable public dataObject;
    MockCallbackHandler public mockHandler;
    FailingCallbackHandler public failHandler;

    DataPoint dp;

    function setUp() public {
        registry = new DataPointRegistry();
        dataIndex = new MinimalisticDataIndex();
        SampleCallbackDataObjectUpgradeable impl = new SampleCallbackDataObjectUpgradeable();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(impl.initialize, ())
        );
        dataObject = SampleCallbackDataObjectUpgradeable(address(proxy));
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
        emit CallbackProcessorDataObjectUpgradeable.CallbackHandlerRegistered(dp, address(mockHandler), type(uint256).max);
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(mockHandler), type(uint256).max, "")
        );
    }

    function test_RegisterCallbackRevertsForNonERC165() public {
        vm.expectRevert(abi.encodeWithSelector(CallbackProcessorDataObjectUpgradeable.CallbackHandlerDoesNotSupportCallbackInterface.selector, address(0x1234)));
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
        emit CallbackProcessorDataObjectUpgradeable.CallbackHandlerUpdated(dp, address(mockHandler), uint256(3));
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
        emit CallbackProcessorDataObjectUpgradeable.CallbackHandlerUnregistered(dp, address(mockHandler));
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.unregisterCallback.selector,
            abi.encode(address(mockHandler))
        );
    }

    function test_UnregisterNonExistentHandlerReverts() public {
        vm.expectRevert(abi.encodeWithSelector(CallbackProcessorDataObjectUpgradeable.CallbackHandlerNotRegistered.selector, address(mockHandler)));
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
            ISampleCallbackUpgradeableOperations.execute.selector,
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
            ISampleCallbackUpgradeableOperations.execute.selector,
            abi.encode(uint256(2), abi.encode("hello"))
        );
        assertEq(mockHandler.callCount(), 0, "Handler should not be called for non-matching task");

        // Task bit 1 - handler SHOULD be called
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ISampleCallbackUpgradeableOperations.execute.selector,
            abi.encode(uint256(1), abi.encode("hello"))
        );
        assertEq(mockHandler.callCount(), 1, "Handler should be called for matching task");
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
            ISampleCallbackUpgradeableOperations.execute.selector,
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

        vm.expectRevert(abi.encodeWithSelector(CallbackProcessorDataObjectUpgradeable.CallbackHandlerFailedToProcessCallbackWithoutReason.selector, address(emptyRevertHandler)));
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ISampleCallbackUpgradeableOperations.execute.selector,
            abi.encode(uint256(1), abi.encode("data"))
        );
    }

    // --- No handlers registered ---

    function test_ExecuteWithNoHandlers() public {
        vm.expectEmit(true, true, true, true);
        emit CallbackProcessorDataObjectUpgradeable.CallbacksProcessed(dp, uint256(1), 0, 0);
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ISampleCallbackUpgradeableOperations.execute.selector,
            abi.encode(uint256(1), abi.encode("data"))
        );
    }

    // --- Reentrancy ---

    function test_ReentrantCallbackReverts() public {
        ReentrantCallbackHandler reentrantHandler = new ReentrantCallbackHandler(
            address(dataIndex),
            address(dataObject),
            ISampleCallbackUpgradeableOperations.execute.selector,
            abi.encode(uint256(1), abi.encode("reentrant"))
        );

        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ICallbackProcessorOperations.registerCallback.selector,
            abi.encode(address(reentrantHandler), type(uint256).max, "")
        );

        vm.expectRevert();
        dataIndex.write(
            IDataObject(address(dataObject)), dp,
            ISampleCallbackUpgradeableOperations.execute.selector,
            abi.encode(uint256(1), abi.encode("trigger"))
        );
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
            ISampleCallbackUpgradeableOperations.execute.selector,
            abi.encode(uint256(1), abi.encode("taskdata"))
        );

        (, , bytes memory receivedCtx) = mockHandler.calls(0);
        assertEq(keccak256(receivedCtx), keccak256(ctx), "Context should match");
    }
}
