// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IDataObject} from "../interfaces/IDataObject.sol";
import {IBaseDataObject} from "../interfaces/IBaseDataObject.sol";
import {IDataIndex} from "../interfaces/IDataIndex.sol";
import {IDataPointRegistry} from "../interfaces/IDataPointRegistry.sol";
import {DataPoint, DataPoints} from "./DataPoints.sol";
import {ChainidTools} from "./ChainidTools.sol";

/**
 * @title Base Data Object
 * @notice Base contract for DataObject implementations
 */
abstract contract BaseDataObjectUpgradeable is IBaseDataObject, AccessControlUpgradeable {
    /**
     * @dev Error thrown when a read operation called is not supported by this DataObject. 
     * Extending DataObject SHOULD override `_dispatchRead()` to handle the operation
     */
    error UnsupportedReadOperation(bytes4 operation);
    /**
     * @dev Error thrown when a write operation called is not supported by this DataObject. 
     * Extending DataObject SHOULD override `_dispatchWrite()` to handle the operation
     */
    error UnsupportedWriteOperation(bytes4 operation);
        
    /// @custom:storage-location erc7201:nexera-foundation.erc7208-core.storage.BaseDataObject
    struct BaseDataObjectStorage {
        /// @dev DataIndex implementation to be used if none is set for DataPoint. Zero address is valid and prevents usage of such DataPoints
        IDataIndex defaultDataIndex;
        /// @dev Mapping of DataIndexes for DataPoints overrides (used instead of default DataIndex)
        mapping(DataPoint => IDataIndex) overrideDataIndexes;
    }

    // keccak256(abi.encode(uint256(keccak256("nexera-foundation.erc7208-core.storage.BaseDataObject")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BaseDataObjectStorageLocation = 0xa443a0a91e31176e5e439a7da326d436b956bf64f73af115662d0397c1357b00;

    function _getBaseDataObjectStorage() private pure returns (BaseDataObjectStorage storage $) {
        assembly {
            $.slot := BaseDataObjectStorageLocation
        }
    }

    /**
     * @notice Modifier to check if the caller is the Data Index implementation which is set for the DataPoint, or the default one.
     * @param dp The DataPoint identifier
     */
    modifier onlyDataIndex(DataPoint dp) {
        IDataIndex dataIndexImpl = _dataIndex(dp);
        if (address(dataIndexImpl) != msg.sender) revert InvalidCaller(dp, msg.sender);
        _;
    }

    function __BaseDataObject_init() internal onlyInitializing {
        __BaseDataObject_init_unchained();
    }

    function __BaseDataObject_init_unchained() internal onlyInitializing {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /**
     * Executes requested read operation
     * Extending DataObject SHOULD override this function and call `super._dispatchRead()`
     * for operations it does not handle.
     * @dev It's recommended to NOT include actual function implementation to this function directly.
     * Instead this one should just chouse the correct internal function with actual implementation
     * param dp DataPoint with the data we should work on
     * @param operation Operation to execute
     * param data Operation arguments. It's recommended to use ABI encoding for this
     * @return Operation result. It's recommended to use ABI encoding for this
     */
    function _dispatchRead(DataPoint /*dp*/, bytes4 operation, bytes calldata /*data*/) internal view virtual returns (bytes memory) {
        revert UnsupportedReadOperation(operation);
    }

    /**
     * Executes requested write operation
     * Extending DataObject SHOULD override this function and call `super._dispatchWrite()`
     * for operations it does not handle.
     * @dev It's recommended to NOT include actual function implementation to this function directly.
     * Instead this one should just chouse the correct internal function with actual implementation
     * param dp DataPoint with the data we should work on
     * @param operation Operation to execute
     * param data Operation arguments. It's recommended to use ABI encoding for this
     * @return Operation result. It's recommended to use ABI encoding for this
     */
    function _dispatchWrite(DataPoint /*dp*/, bytes4 operation, bytes calldata /*data*/) internal virtual returns (bytes memory) {        
        revert UnsupportedWriteOperation(operation);
    }

    /// @inheritdoc IBaseDataObject
    function defaultDataIndex() public view returns (address) {
        return address(_getBaseDataObjectStorage().defaultDataIndex);
    }

    /// @inheritdoc IBaseDataObject
    function overrideDataIndex(DataPoint dp) public view returns (address) {
        return address(_getBaseDataObjectStorage().overrideDataIndexes[dp]);
    }

    /// @inheritdoc IBaseDataObject
    function dataIndex(DataPoint dp) external view returns (address) {
        return address(_dataIndex(dp));
    }

    /// @inheritdoc IDataObject
    function read(DataPoint dp, bytes4 operation, bytes calldata data) external view returns (bytes memory) {
        return _dispatchRead(dp, operation, data);
    }

    /// @inheritdoc IDataObject
    function write(DataPoint dp, bytes4 operation, bytes calldata data) external payable onlyDataIndex(dp) returns (bytes memory) {
        _verifyNativePaymentInWrite();
        return _dispatchWrite(dp, operation, data);
    }

    /// @inheritdoc IDataObject
    function setDataIndexImplementation(DataPoint dp, address newDataIndex) external {
        _requireDataIndexIsValid(newDataIndex);
        BaseDataObjectStorage storage $ = _getBaseDataObjectStorage();

        IDataIndex currentDataIndex = $.overrideDataIndexes[dp];
        if (address(currentDataIndex) == address(0)) {
            // Registering new DataPoint
            // Should be called by DataPoint Admin
            require(_isDataPointAdmin(dp, _msgSender()), InvalidCaller(dp, _msgSender()));
        } else {
            // Updating the DataPoint
            // Should be called by current Data Index or DataPoint Admin
            require(address(currentDataIndex) == _msgSender() || _isDataPointAdmin(dp, _msgSender()), InvalidCaller(dp, _msgSender()));
        }
        _setDataIndexImplementationInternal(dp, newDataIndex);
    }

    /**
     * Set default DataIndex implementation, which should be used if none is set for a DataPoint
     * @param newDataIndex Address DataIndex implementations
     * @dev NOTE: zero address is valid and can be used to disallow usage of DataPoints without DataIndex set for them
     */
    function setDefaultDataIndexImplementation(address newDataIndex) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newDataIndex != address(0)) {
            _requireDataIndexIsValid(newDataIndex);
        }
        BaseDataObjectStorage storage $ = _getBaseDataObjectStorage();
        $.defaultDataIndex = IDataIndex(newDataIndex);
        emit DefaultDataIndexImplementationSet(newDataIndex);
    }

    /**
     * Returns active DataIndex address for the DataPoint
     * @param dp DataPoint to check
     */
    function _dataIndex(DataPoint dp) internal view returns (IDataIndex) {
        BaseDataObjectStorage storage $ = _getBaseDataObjectStorage();
        IDataIndex di = $.overrideDataIndexes[dp];
        if (address(di) == address(0)) {
            di = IDataIndex($.defaultDataIndex);
            if (address(di) == address(0)) revert DataIndexImplementationNotSet(dp);
        }
        return di;
    }

    /**
     * Returns if provided account has admin permissions for DataPoint
     * @param dp DataPoint to check
     */
    function _isDataPointAdmin(DataPoint dp, address account) internal view returns (bool) {
        (uint32 chainId, address registry, ) = DataPoints.decode(dp);
        ChainidTools.requireCurrentChain(chainId);
        return IDataPointRegistry(registry).isAdmin(dp, account);
    }

    /**
     * @dev Override this function to support native coin payment for write() call
     * If native payment should be allowed in the DataObject, one can override
     * this function with an empty one and handle the payment in the _dispatchWrite()
     */
    function _verifyNativePaymentInWrite() internal virtual {
        if (msg.value > 0) revert NativePaymentNotSupported();
    }

    /**
     * Verifies if provided address is valid DataIndex
     * @param newDataIndex Address of supposed DataIndex
     * @dev Reverts if it's not valid address
     */
    function _requireDataIndexIsValid(address newDataIndex) internal view virtual {
        if (!IERC165(newDataIndex).supportsInterface(type(IERC165).interfaceId) || !IERC165(newDataIndex).supportsInterface(type(IDataIndex).interfaceId))
            revert IncorrectDataIndexImplementationAddress(newDataIndex);
    }


    /**
     * Set new DataIndex implementation for a DataPoint WITHOUT VERIFICATIONS
     * Allows extending DataObject to change DataIndex for a DataPoint using alternative ways
     * of DataPoint admin permissions verification
     * @param dp DataPoint to change
     * @param newDataIndexImpl new DataIndex address
     */
    function _setDataIndexImplementationInternal(DataPoint dp, address newDataIndexImpl) internal {
        BaseDataObjectStorage storage $ = _getBaseDataObjectStorage();
        $.overrideDataIndexes[dp] = IDataIndex(newDataIndexImpl);
        emit DataIndexImplementationSet(dp, newDataIndexImpl);
    }    

}
