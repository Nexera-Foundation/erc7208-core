// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IDataIndex, IDataObject, DataPoint} from "../../interfaces/IDataIndex.sol";
import {IDataPointRegistry} from "../../interfaces/IDataPointRegistry.sol";
import {RaceToTheTargetDataManager} from "./RaceToTheTargetDataManager.sol";

/**
 * Factory allows anyone to create a game instance
 * with configurations he wants.
 */
contract RaceToTheTargetFactory {
    IDataPointRegistry registry;
    IDataIndex dataIndex;
    IDataObject dataObject;
    address gameImplementation;

    constructor(address registry_, address dataIndex_, address dataObject_, address gameImplementation_) {
        dataIndex = IDataIndex(dataIndex_);
        registry = IDataPointRegistry(registry_);
        dataObject = IDataObject(dataObject_);
        gameImplementation = gameImplementation_;
    }

    function deploy(uint256 targetValue, uint256 stepPrice, uint256 jumpPrice) external returns(address gameInstance, DataPoint gameDataPoint){
        // Note: game configuration is validated inside RaceToTheTargetDataManager.initialize(), we do not repeat it here

        // Allocate DataPoint
        gameDataPoint = registry.allocate(address(this));

        // Deploy game instance
        gameInstance = Clones.clone(gameImplementation);

        // Approve game instance to use the DataPoint
        dataIndex.allowDataManager(gameDataPoint, gameInstance, true);
        
        // Initialize game instance
        RaceToTheTargetDataManager(gameInstance).initialize(
            dataIndex,
            gameDataPoint,
            dataObject,
            targetValue,
            stepPrice,
            jumpPrice
        );

        // Note: We DO NOT transferring DataPoint ownership to the deployer
        // because if we do it, he will be able to change the data stored
        // in the DataObject without respecting rules set by DataManager
        // But for other use-cases we may need to make the deployer
        // to be the owner of the DataPoint.
        // Example:
        // registry.transferOwnership(gameDataPoint, msg.sender);
    }

}