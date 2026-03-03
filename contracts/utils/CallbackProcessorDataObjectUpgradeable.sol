// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {DataPoint} from "./DataPoints.sol";
import {BaseDataObjectUpgradeable} from "./BaseDataObjectUpgradeable.sol";
import {IDataObjectCallbackHandler} from "../interfaces/IDataObjectCallbackHandler.sol";
import {ICallbackProcessorOperations} from "../interfaces/ICallbackProcessorOperations.sol";

abstract contract CallbackProcessorDataObjectUpgradeable is BaseDataObjectUpgradeable, ReentrancyGuardTransient {
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
        address[] memory handlers = cpData.handlers.values();
        for (uint256 i; i < handlers.length; i++) {
            address handler = handlers[i];
            // here we first read mask, and only if needed read context
            uint256 mask = cpData.properties[handler].mask;
            if ((mask & task) != 0) {
                bytes memory context = cpData.properties[handler].context;
                //TODO Handle errors? Add options to fail on error or skip error? Add another function instead of an option to this one?
                IDataObjectCallbackHandler(handler).handleDataObjectCallback(dp, taskData, context);
            }
        }
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
        emit CallbackHandlerRegistered(handler, mask);
    }

    function _unregisterCallback(DataPoint dp, address handler) private {
        CallbackProcessorDataObjectStorage storage $ = _getCallbackProcessorDataObjectStorage();
        CallbackProcessorDpData storage cpData = $.callbackProcessorData[dp];
        bool removed = cpData.handlers.remove(handler);
        require(removed, CallbackHandlerNotRegistered(handler));
        delete cpData.properties[handler];
        emit CallbackHandlerUnregistered(handler);
    }
}
