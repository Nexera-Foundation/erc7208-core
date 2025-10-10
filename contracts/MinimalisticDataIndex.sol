// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC165, ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IDataIndex} from "./interfaces/IDataIndex.sol";
import {IDataObject} from "./interfaces/IDataObject.sol";
import {IDataPointRegistry} from "./interfaces/IDataPointRegistry.sol";
import {ChainidTools} from "./utils/ChainidTools.sol";
import {DataPoints, DataPoint} from "./utils/DataPoints.sol";

/**
 * @title Data Index contract
 * @notice Minimalistic implementation of a Data Index contract
 * Supports only single-chain operations. DataPoints created on other chains are not supported.
 * @dev For security reasons DataManager's approval for a DataPoint is valid only while the
 * DataPoint admin who initiated the approval has his admin permission.
 */
contract MinimalisticDataIndex is IDataIndex, ERC165 {
    /// @dev Error thrown when the sender is not an admin of the DataPoint
    error InvalidDataPointAdmin(DataPoint dp, address sender);

    /// @dev Error thrown when the DataManager is not approved to interact with the DataPoint
    error DataManagerNotApproved(DataPoint dp, address dm);

    /// @dev Error thrown when the dataIndex identifier is incorrect
    error IncorrectIdentifier(bytes32 diid);

    /**
     * @notice Event emitted when DataManager is approved for DataPoint
     * @param dp Identifier of the DataPoint
     * @param dpAdmin Address of the DataPoint admin who executed the approval change
     * @param dm Address of DataManager
     * @param approved if DataManager is approved
     * @dev It's also recommended to listen DataPointRegistry.DataPointAdminRevoked event
     * because when admin is revoked, all DM's he approved lose their approval.
     */
    event ApprovalChanged(DataPoint dp, address dpAdmin, address dm, bool approved);

    /**
     * @dev Mapping of DataPoint to DataManagers allowed to write to this DP (in any DataObject)
     * We also store address of the admin who approved the DataManager, so that later, on write(),
     * we can verify it is not revoked
     */
    mapping(DataPoint => mapping(address dm => address dpAdmin)) private _dmApprovals;

    /**
     * @notice Restricts access to the function, allowing only DataPoint admins
     * @param dp DataPoint to check ownership of
     */
    modifier onlyDPAdmin(DataPoint dp) {
        require(_isDataPointAdmin(dp, msg.sender), InvalidDataPointAdmin(dp, msg.sender));
        _;
    }

    /**
     * @notice Allows access only to DataManagers which was previously approved
     * @param dp DataPoint to check DataManager approval for
     */
    modifier onlyApprovedDM(DataPoint dp) {
        require(isApprovedDataManager(dp, msg.sender), DataManagerNotApproved(dp, msg.sender));
        _;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IDataIndex).interfaceId || super.supportsInterface(interfaceId);
    }

    ///@inheritdoc IDataIndex
    function isApprovedDataManager(DataPoint dp, address dm) public view returns (bool) {
        address dpAdmin = _dmApprovals[dp][dm];
        if (dpAdmin == address(0)) return false;
        // Here we are verifying that address who approved DataManager is still an admin of the DataPoint
        return _isDataPointAdmin(dp, dpAdmin);
    }

    ///@inheritdoc IDataIndex
    function allowDataManager(DataPoint dp, address dm, bool approved) external onlyDPAdmin(dp) {
        if (approved) {
            _dmApprovals[dp][dm] = msg.sender;
        } else {
            delete _dmApprovals[dp][dm];
        }
        emit ApprovalChanged(dp, msg.sender, dm, approved);
    }

    ///@inheritdoc IDataIndex
    function read(IDataObject dobj, DataPoint dp, bytes4 operation, bytes calldata data) external view returns (bytes memory) {
        return dobj.read(dp, operation, data);
    }

    ///@inheritdoc IDataIndex
    function write(IDataObject dobj, DataPoint dp, bytes4 operation, bytes calldata data) external onlyApprovedDM(dp) returns (bytes memory) {
        return dobj.write(dp, operation, data);
    }

    /**
     * Verifies if account is admin of a DataPoint
     * @param dp DataPoint to check
     * @param account Address to verify
     * @dev Requires DataPoint to be created on current chain
     */
    function _isDataPointAdmin(DataPoint dp, address account) internal view returns (bool) {
        (uint32 chainId, address registry, ) = DataPoints.decode(dp);
        ChainidTools.requireCurrentChain(chainId);
        return IDataPointRegistry(registry).isAdmin(dp, account);
    }
}
