// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DataPoint} from "../../utils/DataPoints.sol";

/**
 * @title ID Manager Interface
 * @notice Interface defines functions to build Data Index user identifiers and get information about them
 */
interface IIDManager {
    /**
     * @notice Provides Data Index id for a specific account for a specific DataPoint
     * @param account Address of the user
     * @param dp DataPoint the id should be linked with
     * @return Data Index token id
     * @dev Can be also understood as user Id within the DataIndex
     */
    function diid(address account, DataPoint dp) external view returns (bytes32);

    /**
     * @notice Provides information about owner of specific Data Index id
     * @param diid_ Data Index id to get info for
     * @return chainid of owner's address
     * @return owner's address
     */
    function ownerOf(bytes32 diid_) external view returns (uint32, address);
}
