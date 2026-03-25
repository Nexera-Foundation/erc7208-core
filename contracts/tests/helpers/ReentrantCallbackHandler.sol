// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IDataObjectCallbackHandler} from "../../interfaces/IDataObjectCallbackHandler.sol";
import {IDataIndex} from "../../interfaces/IDataIndex.sol";
import {IDataObject} from "../../interfaces/IDataObject.sol";
import {DataPoint} from "../../utils/DataPoints.sol";

/**
 * @dev Test helper that attempts to re-enter the DataObject via the DataIndex during callback processing.
 */
contract ReentrantCallbackHandler is IDataObjectCallbackHandler, ERC165 {
    IDataIndex public dataIndex;
    IDataObject public dataObject;
    bytes4 public reentrantOperation;
    bytes public reentrantData;

    constructor(address _dataIndex, address _dataObject, bytes4 _operation, bytes memory _data) {
        dataIndex = IDataIndex(_dataIndex);
        dataObject = IDataObject(_dataObject);
        reentrantOperation = _operation;
        reentrantData = _data;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IDataObjectCallbackHandler).interfaceId || super.supportsInterface(interfaceId);
    }

    function handleDataObjectCallback(DataPoint dp, bytes calldata, bytes calldata) external override returns (bytes memory) {
        // Attempt re-entrant call back into the DataObject
        dataIndex.write(dataObject, dp, reentrantOperation, reentrantData);
        return "";
    }
}
