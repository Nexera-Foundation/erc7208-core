// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IDataObjectCallbackHandler} from "../../interfaces/IDataObjectCallbackHandler.sol";
import {DataPoint} from "../../utils/DataPoints.sol";

contract MockCallbackHandler is IDataObjectCallbackHandler, ERC165 {
    struct CallRecord {
        DataPoint dp;
        bytes taskData;
        bytes context;
    }

    CallRecord[] public calls;

    function callCount() external view returns (uint256) {
        return calls.length;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IDataObjectCallbackHandler).interfaceId || super.supportsInterface(interfaceId);
    }

    function handleDataObjectCallback(DataPoint dp, bytes calldata taskData, bytes calldata context) external override returns (bytes memory) {
        calls.push(CallRecord({dp: dp, taskData: taskData, context: context}));
        return abi.encode(calls.length);
    }
}
