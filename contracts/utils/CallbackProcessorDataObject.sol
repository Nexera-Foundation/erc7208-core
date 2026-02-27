// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {DataPoint} from "./DataPoints.sol";
import {BaseDataObject} from "./BaseDataObject.sol";
import {IDataObjectCallbackHandler} from "../interfaces/IDataObjectCallbackHandler.sol";
import {ICallbackProcessorOperations} from "../interfaces/ICallbackProcessorOperations.sol";

abstract contract CallbackProcessorDataObject is BaseDataObject, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 constant public ALL_OPERATIONS = type(uint256).max;    

    error CallbackHandlerDoesNotSupportCallbackInterface(address handler);
    error CallbackHandlerAlreadyRegistered(address handler);
    error CallbackHandlerNotRegistered(address handler);

    event CallbackHandlerRegistered(address handler, uint256 mask);
    event CallbackHandlerUnregistered(address handler);

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
        address[] memory handlers = cpData.handlers.values();
        for(uint256 i; i < handlers.length; i++) {
            address handler = handlers[i];
            // here we first read mask, and only if needed read context
            uint256 mask = cpData.properties[handler].mask;
            if((mask & task) != 0) {
                bytes memory context = cpData.properties[handler].context;
                //TODO Handle errors? Add options to fail on error or skip error? Add another function instead of an option to this one?
                IDataObjectCallbackHandler(handler).handleDataObjectCallback(dp, taskData, context);
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
        emit CallbackHandlerRegistered(handler, mask);
    }

    function _unregisterCallback(DataPoint dp, address handler) private {
        CallbackProcessorDpData storage cpData = _callbackProcessorData[dp];
        bool removed = cpData.handlers.remove(handler);
        require(removed, CallbackHandlerNotRegistered(handler));
        delete cpData.properties[handler];
        emit CallbackHandlerUnregistered(handler);
    }
}