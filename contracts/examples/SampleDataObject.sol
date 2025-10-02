// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {DataPoint} from "../utils/DataPoints.sol";
import {BaseDataObject} from "../utils/BaseDataObject.sol";

/**
 * Interface of Operations supported by this DataObject
 */
interface ISampleDataObjectOperations {
    /// @dev Error throws when decrement operation can not be executed
    error ValueCanNotBeDecremented();

    /// @dev Error throws when increment operation can not be executed
    error ValueCanNotBeIncremented();

    /// @dev Read current value
    function value() external view returns (uint256);

    /// @dev Set value to a provided newValue
    function set(uint256 newValue) external;

    /// @dev Increment value by one, returns new value
    function inc() external returns (uint256 newValue);

    /// @dev Decrement value by one, returns new value
    function dec() external returns (uint256 newValue);

    /// @dev Sets the value only if current value matches expected value
    function compareAndSet(uint256 expectedValue, uint256 newValue) external returns (bool success);
}

contract SampleDataObject is BaseDataObject {
    error UnknownOperation(bytes4 operation);

    /**
     * Storage structure for data of DataPoint
     * @dev Here we do not verify if storage was initialized.
     * One should add such verification if it's needed for his use-case
     */
    struct DpData {
        uint256 value;
    }

    /// @dev Data for each DataPoint
    mapping(DataPoint => DpData) private _dpDataStructs;

    constructor() {
    }

    /// @inheritdoc BaseDataObject
    function _dispatchRead(DataPoint dp, bytes4 operation, bytes calldata /*data*/) internal view override returns (bytes memory) {
        if (operation == ISampleDataObjectOperations.value.selector) {
            return abi.encode(_value(dp));
        }
        revert UnknownOperation(operation);
    }

    /// @inheritdoc BaseDataObject
    function _dispatchWrite(DataPoint dp, bytes4 operation, bytes calldata data) internal override returns (bytes memory) {
        if (operation == ISampleDataObjectOperations.set.selector) {
            _set(dp, abi.decode(data, (uint256)));
            return "";
        } else if (operation == ISampleDataObjectOperations.inc.selector) {
            return abi.encode(_inc(dp));
        } else if (operation == ISampleDataObjectOperations.dec.selector) {
            return abi.encode(_dec(dp));
        } else if (operation == ISampleDataObjectOperations.compareAndSet.selector) {
            (uint256 expectedValue, uint256 newValue) = abi.decode(data, (uint256, uint256));
            return abi.encode(_compareAndSet(dp, expectedValue, newValue));
        }
        revert UnknownOperation(operation);
    }

    function _value(DataPoint dp) private view returns (uint256) {
        return _dpData(dp).value;
    }

    function _set(DataPoint dp, uint256 newValue) private {
        _dpData(dp).value = newValue;
    }

    function _inc(DataPoint dp) private returns (uint256) {
        uint256 currentValue = _dpData(dp).value;
        require(currentValue < type(uint256).max, ISampleDataObjectOperations.ValueCanNotBeIncremented());
        unchecked {
            _dpData(dp).value = ++currentValue;
        }
        return currentValue;
    }

    function _dec(DataPoint dp) private returns (uint256) {
        uint256 currentValue = _dpData(dp).value;
        require(currentValue > type(uint256).min, ISampleDataObjectOperations.ValueCanNotBeDecremented());
        unchecked {
            _dpData(dp).value = --currentValue;
        }
        return currentValue;
    }

    function _compareAndSet(DataPoint dp, uint256 expectedValue, uint256 newValue) private returns (bool) {
        uint256 currentValue = _dpData(dp).value;
        if (currentValue == expectedValue) {
            _dpData(dp).value = newValue;
            return true;
        } else {
            return false;
        }
    }

    function _dpData(DataPoint dp) internal view returns (DpData storage) {
        return _dpDataStructs[dp];
    }
}
