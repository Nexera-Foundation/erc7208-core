// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DataPoint} from "../../utils/DataPoints.sol";
import {CallbackProcessorDataObject} from "../../utils/CallbackProcessorDataObject.sol";

interface IBeforeCallbackOperations {
    function execute(uint256 task, bytes memory taskData) external;
}

contract BeforeCallbackDataObject is CallbackProcessorDataObject {
    DataPoint public lastDp;
    uint256 public lastTask;
    bytes public lastTaskData;
    address[] public lastHandlers;

    constructor() {}

    function _dispatchWrite(DataPoint dp, bytes4 operation, bytes calldata data) internal override returns (bytes memory) {
        if (operation == IBeforeCallbackOperations.execute.selector) {
            (uint256 task, bytes memory taskData) = abi.decode(data, (uint256, bytes));
            _processCallbacks(dp, task, taskData);
            return "";
        }
        return super._dispatchWrite(dp, operation, data);
    }

    function _beforeProcessCallbacks(DataPoint dp, uint256 task, bytes memory taskData, address[] memory handlers) internal override {
        lastDp = dp;
        lastTask = task;
        lastTaskData = taskData;
        lastHandlers = handlers;
    }

    function getLastHandlers() external view returns (address[] memory) {
        return lastHandlers;
    }
}
