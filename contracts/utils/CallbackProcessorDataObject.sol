// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {Arrays} from "@openzeppelin/contracts/utils/Arrays.sol";
import {DataPoint} from "./DataPoints.sol";
import {BaseDataObject} from "./BaseDataObject.sol";
import {IDataObjectCallbackHandler} from "../interfaces/IDataObjectCallbackHandler.sol";
import {ICallbackProcessorOperations} from "../interfaces/ICallbackProcessorOperations.sol";

abstract contract CallbackProcessorDataObject is BaseDataObject, ReentrancyGuardTransient {
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

    mapping(DataPoint => CallbackProcessorDpData) private _callbackProcessorData;
    
    function _dispatchWrite(DataPoint dp, bytes4 operation, bytes calldata data) internal virtual override returns (bytes memory) {        
        if (operation == ICallbackProcessorOperations.registerCallback.selector) {
            (address handler, uint256 mask, bytes memory context) = abi.decode(data, (address, uint256, bytes));
            _registerCallback(dp, handler, mask, context);
            return "";
        } else if(operation == ICallbackProcessorOperations.unregisterCallback.selector) {
            (address handler) = abi.decode(data, (address));
            _unregisterCallback(dp, handler);            
            return "";
        }
        return super._dispatchWrite(dp, operation, data);
    }    

    function _processCallbacks(DataPoint dp, uint256 task, bytes memory taskData) internal nonReentrant {
        CallbackProcessorDpData storage cpData = _callbackProcessorData[dp];
        address[] memory handlers = _filterCallbackHandlers(cpData, task);
        _beforeProcessCallbacks(dp, task, taskData, handlers);
        uint256 failedHandlersCount;
        for(uint256 i; i < handlers.length; i++) {
            address handler = handlers[i];
            bytes memory context = cpData.properties[handler].context;
            try IDataObjectCallbackHandler(handler).handleDataObjectCallback(dp, taskData, context) returns(bytes memory result){
                _onCallbackHandlerSuccess(dp, task, handler, result);
            } catch(bytes memory reason)  {
                failedHandlersCount++;
                _onCallbackHandlerFailure(dp, task, handler, reason);
            }
        }
        _afterProcessCallbacks(dp, task, handlers.length - failedHandlersCount, failedHandlersCount);
    }

    /**
     * Extension point to allow validate requirements befrore processing task via handlers
     * param dp DataPoint to work with
     * param task task to handle
     * param taskData task data
     * param handlers list of handlers which will be called to process the task (filtered)
     * @dev Can be overriden to do required verification
     */
    function _beforeProcessCallbacks(DataPoint /*dp*/, uint256 /*task*/, bytes memory /*taskData*/, address[] memory /*handlers*/) internal virtual {}

    /**
     * Extension point to allow validate requirements after processing task via handlers
     * @param dp DataPoint to work with
     * @param task task to handle
     * @param successfulHandlers count of failed handler calls
     * @param failedHandlers count of failed handler calls
     * @dev Can be overriden if extra processing is needed.
     * Overriding contract should emit the CallbacksProcessed event itslef or call `super._afterProcessCallbacks()`
     */
    function _afterProcessCallbacks(DataPoint dp, uint256 task, uint256 successfulHandlers, uint256 failedHandlers) internal virtual {
        emit CallbacksProcessed(dp, task, successfulHandlers, failedHandlers);
    }

    /**
     * Extension point to allow customize callback result processing
     * param dp DataPoint to work with
     * param task task to handle
     * param handler address of failed handler
     * param result data returned by the callback
     */
    function _onCallbackHandlerSuccess(DataPoint /*dp*/, uint256 /*task*/, address /*handler*/, bytes memory /*result*/) internal virtual {
    }

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

    function _registerCallback(DataPoint dp, address handler, uint256 mask, bytes memory context) private {
        require(IERC165(handler).supportsInterface(type(IDataObjectCallbackHandler).interfaceId), CallbackHandlerDoesNotSupportCallbackInterface(handler));
        CallbackProcessorDpData storage cpData = _callbackProcessorData[dp];
        bool added = cpData.handlers.add(handler);
        require(added, CallbackHandlerAlreadyRegistered(handler));
        cpData.properties[handler] = CallbackHandlerProperties({
            mask: mask,
            context: context
        });
        emit CallbackHandlerRegistered(dp, handler, mask);
    }

    function _unregisterCallback(DataPoint dp, address handler) private {
        CallbackProcessorDpData storage cpData = _callbackProcessorData[dp];
        bool removed = cpData.handlers.remove(handler);
        require(removed, CallbackHandlerNotRegistered(handler));
        delete cpData.properties[handler];
        emit CallbackHandlerUnregistered(dp, handler);
    }

    function _filterCallbackHandlers(CallbackProcessorDpData storage cpData, uint256 task) private view returns(address[] memory) {
        // Here we are filtering the handlers array, moving all handlers of requested task to the begining of the array
        address[] memory handlers = cpData.handlers.values();
        uint256 nextFreeIndex; // This variable points to a slot available for next suitable handler
        for(uint256 i; i < handlers.length; i++) {
            address handler = handlers[i];
            uint256 mask = cpData.properties[handler].mask;
            if((mask & task) != 0) {
                if(nextFreeIndex < i) {
                    handlers[nextFreeIndex] = handlers[i];
                }
                nextFreeIndex++;
            }
        }
        return handlers.slice(0,nextFreeIndex);
    }
}