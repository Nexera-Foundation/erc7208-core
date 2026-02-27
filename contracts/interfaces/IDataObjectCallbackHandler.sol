// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {DataPoint} from "../utils/DataPoints.sol";

interface IDataObjectCallbackHandler is IERC165 {
    /**
     * Called by DataObject to handle extra processing logic after write calls
     * @param dp DataPoint to work with
     * @param taskData Handler-specific data of current call
     * @param context Optional context provided during Handler registration
     * @dev If handler needs to handle multiple tasks, the one requested can be encoded within `taskData`
     */
    function handleDataObjectCallback(DataPoint dp, bytes calldata taskData, bytes calldata context) external;
}
