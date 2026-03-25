// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IDataObjectCallbackHandler} from "../../interfaces/IDataObjectCallbackHandler.sol";
import {DataPoint} from "../../utils/DataPoints.sol";

contract FailingCallbackHandler is IDataObjectCallbackHandler, ERC165 {
    error HandlerFailed(string reason);

    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IDataObjectCallbackHandler).interfaceId || super.supportsInterface(interfaceId);
    }

    function handleDataObjectCallback(DataPoint, bytes calldata, bytes calldata) external pure override returns (bytes memory) {
        revert HandlerFailed("intentional failure");
    }
}
