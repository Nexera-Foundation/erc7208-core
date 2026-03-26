// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DataPoint} from "../../utils/DataPoints.sol";
import {IDataObject} from "../../interfaces/IDataObject.sol";

/**
 * @title Portability Manager Interface
 * @notice Interface defines functions used to change Data Index implementation used for a DataPoint to another one
 */
interface IPortabilityManager {
    /**
     * @dev Error thrown when incorrect Data Index implementation address is provided
     * @param dataIndexImpl Incorrect Data Index Implementation address
     */
    error IncorrectDataIndexImplementationAddress(address dataIndexImpl);

    /**
     * @notice Emitted when Data Index implementation is set
     * @param dp DataPoint to work with
     * @param dataIndexImpl New Data Index Implementation
     * @param dataObjects DataObjects switched to a new implementation
     */
    event DataIndexImplementationSet(DataPoint dp, address dataIndexImpl, IDataObject[] dataObjects);

    /**
     * @notice This function MUST be called by DataPoint owner
     * @param dp DataPoint to work with
     * @param newImpl New Data Index Implementation
     * @param dataObjects DataObjects switched to a new implementation
     * @dev After this call current implementation will not be able to work with this DataPoint on specified DataObjects
     *      Great care should be taken to not make DataObject unusable because of this change
     */
    function setDataIndexImplementation(DataPoint dp, address newImpl, IDataObject[] calldata dataObjects) external;
}
