// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DataPoint} from "../utils/DataPoints.sol";
import {CallbackProcessorDataObject} from "../utils/CallbackProcessorDataObject.sol";

interface ISampleCallbackOperations {
    function execute(uint256 task, bytes memory taskData) external;
}

contract SampleCallbackDataObject is CallbackProcessorDataObject {
    constructor() {}

    function _dispatchWrite(DataPoint dp, bytes4 operation, bytes calldata data) internal override returns (bytes memory) {
        if (operation == ISampleCallbackOperations.execute.selector) {
            (uint256 task, bytes memory taskData) = abi.decode(data, (uint256, bytes));
            _processCallbacks(dp, task, taskData);
            return "";
        }
        return super._dispatchWrite(dp, operation, data);
    }
}
