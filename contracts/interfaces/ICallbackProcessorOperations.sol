// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICallbackProcessorOperations {
    /**
     * Registers callback handler within DataObject
     * @param handler contract to call, must implement IDataObjectCallbackHandler
     * @param mask allows to only call this handler for specific tasks. Use `bytes32(type(uint256).max)` (0xFF...FF) for all tasks
     * @param context context to provide with the call
     */
    function registerCallback(address handler, uint256 mask, bytes memory context) external;

    /**
     * Unregisters callback handler
     * @param handler handler ro remove
     */
    function unregisterCallback(address handler) external;
}
