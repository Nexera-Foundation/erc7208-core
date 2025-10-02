// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IDataObject} from "./IDataObject.sol";
import {DataPoint} from "../utils/DataPoints.sol";


interface IBaseDataObject is IDataObject {
    /**
     * @dev Error thrown when the msg.sender is not the expected caller
     * @param dp The DataPoint identifier
     * @param sender The msg.sender address
     */
    error InvalidCaller(DataPoint dp, address sender);

    /**
     * @dev Error thrown when there is no DataIndex implementation for a DataPoint
     * @param dp The DataPoint identifier
     */
    error DataIndexImplementationNotSet(DataPoint dp);

    /**
     * @dev Error thrown when the proposed address is not the Data Index implementation
     * @param dataIndexImpl The Data Index implementation
     */
    error IncorrectDataIndexImplementationAddress(address dataIndexImpl);

    /// @dev Error thrown when call with native payment is not supported by the DataObject
    error NativePaymentNotSupported();

    /**
     * @notice Event emitted when default Data Index implementation is set
     * @param dataIndexImplementation The Data Index implementation address
     */
    event DefaultDataIndexImplementationSet(address dataIndexImplementation);

    /**
     * @notice Event emitted when the Data Index implementation is set
     * @param dp The DataPoint identifier
     * @param dataIndexImplementation The Data Index implementation address
     */
    event DataIndexImplementationSet(DataPoint dp, address dataIndexImplementation);



    /**
     * Returns DataIndex used by default if no DataIndex is set for a DataPoint
     * @return default DataIndex address
     */
    function defaultDataIndex() external view returns(address);

    /**
     * Returns DataIndex override for a DataPoint
     * @return address of configured DataIndex or zero address (in that case default DataIndex used)
     */
    function overrideDataIndex(DataPoint dp) external view returns(address);

    /**
     * Returns DataIndex currently used for a DataPoint
     * @return address of DataIndex used for a DataPoint
     */
    function dataIndex(DataPoint dp) external view returns(address);    

    /**
     * Set default DataIndex implementation, which should be used if none is set for a DataPoint
     * @param newDataIndex Address DataIndex implementations
     * @dev NOTE: zero address is valid and can be used to disallow usage of DataPoints without DataIndex set for them
     */
    function setDefaultDataIndexImplementation(address newDataIndex) external;

}