// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DataPoint} from "../../utils/DataPoints.sol";

/**
 * @title Data Object Portability Interface
 * @notice Interface defines functions to manage the Data Index implementation of DataObjects
 */
interface IDOPortability {
    /**
     * @notice This function SHOULD be called by the Data Index Implementation OR DataPoint Admin
     * @param dp DataPoint to work with
     * @param newImpl New Data Index Implementation
     * @dev Initializes DataPoint with provided Data Index implementation or changes current implementation to another one
     */
    function setDataIndexImplementation(DataPoint dp, address newImpl) external;
}
