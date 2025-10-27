// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DataPoint} from "../utils/DataPoints.sol";

/**
 * @title Data Transfer Manager Interface
 * @notice Interface defines functions to manage the transfer of DataPoints between DIIDs
 */
interface IDataTransferManager {
    /**
     * @notice Event emitted when data is transferred
     * @param dp Identifier of the DataPoint
     * @param dataobjects List of DataObjects to work with
     * @param fromDiid ID to transfer from
     * @param toDiid ID to transfer to
     */
    event DataPointTransferred(DataPoint dp, address[] dataobjects, bytes32 fromDiid, bytes32 toDiid);

    /**
     * @notice Transfers data from one id to another
     * @param dp Identifier of the DataPoint
     * @param dataobjects List of DataObjects to work with
     * @param fromDiid ID to transfer from
     * @param toDiid ID to transfer to
     * @dev Function SHOULD be restricted to allowed DMs only
     */
    function transferDataPoint(DataPoint dp, address[] memory dataobjects, bytes32 fromDiid, bytes32 toDiid) external;
}
