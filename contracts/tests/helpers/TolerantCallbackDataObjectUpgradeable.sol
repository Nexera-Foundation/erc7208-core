// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DataPoint} from "../../utils/DataPoints.sol";
import {CallbackProcessorDataObjectUpgradeable} from "../../utils/CallbackProcessorDataObjectUpgradeable.sol";

interface ITolerantCallbackUpgradeableOperations {
    function execute(uint256 task, bytes memory taskData) external;
}

contract TolerantCallbackDataObjectUpgradeable is CallbackProcessorDataObjectUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __CallbackProcessorDataObject_init();
    }

    function _dispatchWrite(DataPoint dp, bytes4 operation, bytes calldata data) internal override returns (bytes memory) {
        if (operation == ITolerantCallbackUpgradeableOperations.execute.selector) {
            (uint256 task, bytes memory taskData) = abi.decode(data, (uint256, bytes));
            _processCallbacks(dp, task, taskData);
            return "";
        }
        return super._dispatchWrite(dp, operation, data);
    }

    function _onCallbackHandlerFailure(DataPoint, uint256, address, bytes memory) internal override {
        // Swallow failures
    }
}
