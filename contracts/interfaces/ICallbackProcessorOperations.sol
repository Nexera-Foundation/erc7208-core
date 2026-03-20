// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICallbackProcessorOperations {
    /**
     * Registers or updates a callback handler within DataObject.
     * If the handler is already registered, its mask and context are updated.
     * @param handler contract to call, must implement IDataObjectCallbackHandler
     * @param mask allows to only call this handler for specific tasks. Use `type(uint256).max` (0xFF...FF) for all tasks
     * @param context context to provide with the call
     */
    function registerCallback(address handler, uint256 mask, bytes memory context) external;

    /**
     * Unregisters callback handler
     * @param handler handler to remove
     */
    function unregisterCallback(address handler) external;
}
