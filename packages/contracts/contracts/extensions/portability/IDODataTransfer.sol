// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DataPoint} from "../../utils/DataPoints.sol";

/**
 * @title Data Object Transfer Interface
 * @notice Interface defines functions to manage the transfer of DataPoints between DIIDs
 */
interface IDODataTransfer {
    /**
     * @notice Transfers data from one id to another
     * @param dp Identifier of the DataPoint
     * @param fromDiid ID to transfer from
     * @param toDiid ID to transfer to
     * @dev Access to this function MUST be protected and allowed only for Data Index Implementation registered for this DataPoint
     *      NOTE: Transfers using this function will skip hook functions on the Data Manager, disable it if required
     */
    function onDataPointTransfer(DataPoint dp, bytes32 fromDiid, bytes32 toDiid) external;
}
