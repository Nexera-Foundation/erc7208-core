// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {Arrays} from "@openzeppelin/contracts/utils/Arrays.sol";
import {DataPoint} from "./DataPoints.sol";
import {BaseDataObjectUpgradeable} from "./BaseDataObjectUpgradeable.sol";
import {IDataObjectCallbackHandler} from "../interfaces/IDataObjectCallbackHandler.sol";
import {ICallbackProcessorOperations} from "../interfaces/ICallbackProcessorOperations.sol";

abstract contract CallbackProcessorDataObjectUpgradeable is BaseDataObjectUpgradeable, ReentrancyGuardTransient {
    using Arrays for address[];
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 constant public ALL_OPERATIONS = type(uint256).max;

    error CallbackHandlerDoesNotSupportCallbackInterface(address handler);
    error CallbackHandlerAlreadyRegistered(address handler);
    error CallbackHandlerNotRegistered(address handler);
    error CallbackHandlerFailedToProcessCallbackWithoutReason(address handler);

    event CallbackHandlerRegistered(DataPoint dp, address handler, uint256 mask);
    event CallbackHandlerUnregistered(DataPoint dp, address handler);
    event CallbacksProcessed(DataPoint dp, uint256 task, uint256 successfulHandlers, uint256 failedHandlers);

    struct CallbackHandlerProperties {
        uint256 mask;
        bytes context;
    }

    struct CallbackProcessorDpData {
        EnumerableSet.AddressSet handlers;
        mapping(address handler => CallbackHandlerProperties) properties;
    }

    /// @custom:storage-location erc7201:nexera-foundation.erc7208-core.storage.CallbackProcessorDataObject
    struct CallbackProcessorDataObjectStorage {
        mapping(DataPoint => CallbackProcessorDpData) callbackProcessorData;
    }

    // keccak256(abi.encode(uint256(keccak256("nexera-foundation.erc7208-core.storage.CallbackProcessorDataObject")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant CallbackProcessorDataObjectStorageLocation = 0x3cc66f32b02b117d6a00e1c425cc810c9390786dda368db6c901ff1600579500;

    function _getCallbackProcessorDataObjectStorage() private pure returns (CallbackProcessorDataObjectStorage storage $) {
        assembly {
            $.slot := CallbackProcessorDataObjectStorageLocation
        }
    }

    function __CallbackProcessorDataObject_init() internal onlyInitializing {
        __BaseDataObject_init();
        __CallbackProcessorDataObject_init_unchained();
    }

    function __CallbackProcessorDataObject_init_unchained() internal onlyInitializing {}

    function _dispatchWrite(DataPoint dp, bytes4 operation, bytes calldata data) internal virtual override returns (bytes memory) {
        if (operation == ICallbackProcessorOperations.registerCallback.selector) {
            (address handler, uint256 mask, bytes memory context) = abi.decode(data, (address, uint256, bytes));
            _registerCallback(dp, handler, mask, context);
            return "";
        } else if (operation == ICallbackProcessorOperations.unregisterCallback.selector) {
            (address handler) = abi.decode(data, (address));
            _unregisterCallback(dp, handler);
            return "";
        }
        return super._dispatchWrite(dp, operation, data);
    }

    function _processCallbacks(DataPoint dp, uint256 task, bytes memory taskData) internal nonReentrant {
        CallbackProcessorDataObjectStorage storage $ = _getCallbackProcessorDataObjectStorage();
        CallbackProcessorDpData storage cpData = $.callbackProcessorData[dp];
        address[] memory handlers = _filterCallbackHandlers(cpData, task);
        _beforeProcessCallbacks(dp, task, taskData, handlers);
        uint256 failedHandlersCount;
        for (uint256 i; i < handlers.length; i++) {
            address handler = handlers[i];
            bytes memory context = cpData.properties[handler].context;
            try IDataObjectCallbackHandler(handler).handleDataObjectCallback(dp, taskData, context) returns (bytes memory result) {
                _onCallbackHandlerSuccess(dp, task, handler, result);
            } catch (bytes memory reason) {
                failedHandlersCount++;
                _onCallbackHandlerFailure(dp, task, handler, reason);
            }
        }
        _afterProcessCallbacks(dp, task, handlers.length - failedHandlersCount, failedHandlersCount);
    }

    /**
     * Extension point to allow validate requirements before processing task via handlers
     * param dp DataPoint to work with
     * param task task to handle
     * param taskData task data
     * param handlers list of handlers which will be called to process the task (filtered)
     * @dev Can be overridden to do required verification
     */
    function _beforeProcessCallbacks(DataPoint /*dp*/, uint256 /*task*/, bytes memory /*taskData*/, address[] memory /*handlers*/) internal virtual {}

    /**
     * Extension point to allow validate requirements after processing task via handlers
     * @param dp DataPoint to work with
     * @param task task to handle
     * @param successfulHandlers count of successful handler calls
     * @param failedHandlers count of failed handler calls
     * @dev Can be overridden if extra processing is needed.
     * Overriding contract should emit the CallbacksProcessed event itself or call `super._afterProcessCallbacks()`
     */
    function _afterProcessCallbacks(DataPoint dp, uint256 task, uint256 successfulHandlers, uint256 failedHandlers) internal virtual {
        emit CallbacksProcessed(dp, task, successfulHandlers, failedHandlers);
    }

    /**
     * Extension point to allow customize callback result processing
     * param dp DataPoint to work with
     * param task task to handle
     * param handler address of handler
     * param result data returned by the callback
     */
    function _onCallbackHandlerSuccess(DataPoint /*dp*/, uint256 /*task*/, address /*handler*/, bytes memory /*result*/) internal virtual {}

    /**
     * Extension point to allow customize error processing
     * param dp DataPoint to work with
     * param task task to handle
     * @param handler address of failed handler
     * @param reason revert reason
     */
    function _onCallbackHandlerFailure(DataPoint /*dp*/, uint256 /*task*/, address handler, bytes memory reason) internal virtual {
        if (reason.length == 0) {
            revert CallbackHandlerFailedToProcessCallbackWithoutReason(handler);
        } else {
            // Revert with same reason
            assembly ("memory-safe") {
                revert(add(reason, 0x20), mload(reason))
            }
        }
    }

    function _filterCallbackHandlers(CallbackProcessorDpData storage cpData, uint256 task) private view returns (address[] memory) {
        // Filter the handlers array, moving all handlers of requested task to the beginning of the array
        address[] memory handlers = cpData.handlers.values();
        uint256 nextFreeIndex;
        for (uint256 i; i < handlers.length; i++) {
            address handler = handlers[i];
            uint256 mask = cpData.properties[handler].mask;
            if ((mask & task) != 0) {
                if (nextFreeIndex < i) {
                    handlers[nextFreeIndex] = handlers[i];
                }
                nextFreeIndex++;
            }
        }
        return handlers.slice(0, nextFreeIndex);
    }

    function _registerCallback(DataPoint dp, address handler, uint256 mask, bytes memory context) private {
        require(IERC165(handler).supportsInterface(type(IDataObjectCallbackHandler).interfaceId), CallbackHandlerDoesNotSupportCallbackInterface(handler));
        CallbackProcessorDataObjectStorage storage $ = _getCallbackProcessorDataObjectStorage();
        CallbackProcessorDpData storage cpData = $.callbackProcessorData[dp];
        bool added = cpData.handlers.add(handler);
        require(added, CallbackHandlerAlreadyRegistered(handler));
        cpData.properties[handler] = CallbackHandlerProperties({
            mask: mask,
            context: context
        });
        emit CallbackHandlerRegistered(dp, handler, mask);
    }

    function _unregisterCallback(DataPoint dp, address handler) private {
        CallbackProcessorDataObjectStorage storage $ = _getCallbackProcessorDataObjectStorage();
        CallbackProcessorDpData storage cpData = $.callbackProcessorData[dp];
        bool removed = cpData.handlers.remove(handler);
        require(removed, CallbackHandlerNotRegistered(handler));
        delete cpData.properties[handler];
        emit CallbackHandlerUnregistered(dp, handler);
    }
}
