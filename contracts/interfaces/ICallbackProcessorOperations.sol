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

    /**
     * Updates only the bitmask of an already-registered callback handler.
     * Useful for temporarily disabling a handler (mask = 0) without losing its context.
     * @param handler handler whose mask should be updated
     * @param mask new bitmask value
     */
    function updateCallbackMask(address handler, uint256 mask) external;

    /**
     * Returns all registered callback handlers for the DataPoint along with their bitmasks and contexts.
     *
     * WARNING: This operation copies the entire handler set (addresses, masks, and contexts) into
     * memory, which can be quite expensive. This is designed to mostly be used by view accessors
     * that are queried without any gas fees. Developers should keep in mind that this function has
     * an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the handler set grows to a point where copying to memory consumes too much gas
     * to fit in a block.
     *
     * @return handlers array of handler addresses
     * @return masks array of corresponding bitmasks (same order as handlers)
     * @return contexts array of corresponding contexts (same order as handlers)
     */
    function getCallbackHandlers() external view returns (address[] memory handlers, uint256[] memory masks, bytes[] memory contexts);
}
