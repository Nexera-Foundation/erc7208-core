// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/// @dev Wrapper so Hardhat generates an artifact for TransparentUpgradeableProxy
contract TestTransparentProxy is TransparentUpgradeableProxy {
    constructor(address logic, address admin, bytes memory data)
        TransparentUpgradeableProxy(logic, admin, data) {}
}
