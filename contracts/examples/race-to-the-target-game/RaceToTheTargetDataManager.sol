// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IDataIndex, IDataObject, DataPoint} from "../../interfaces/IDataIndex.sol";
import {ISampleDataObjectOperations} from "../SampleDataObject.sol";

/**
 * @title Race to the Target
 * @notice A competitive on-chain game of strategy and timing where players
 * pay small fees to manipulate a shared number. The goal is to be the first
 * to set this number to a specific target value and win the entire prize pool.
 *
 * @dev This contract serves as the DataManager in an ERC-7208 architecture. It
 * contains all the game logic and interacts with a separate DataObject contract
 * to store the game's state (the current value).
 *
 * ---
 *
 * ### CONCEPT
 *
 * The objective is simple: be the first player to set a public counter (`value`)
 * to a predetermined `targetValue`.
 *
 * ---
 *
 * ### MECHANICS
 *
 * Every action in the game requires a fee, which is collected in a central
 * `prizePool`. Players have access to three distinct actions, creating strategic depth:
 *
 * 1. **increment() & decrement()**: These are low-cost actions that allow players
 * to move the `value` up or down by one. They are ideal for making steady,
 * predictable progress.
 *
 * 2. **jump(expectedValue, newValue)**: This is a high-cost, high-reward strategic
 * move. It allows a player to attempt to set the `value` to a new number, but
 * the transaction will only succeed if the current `value` on-chain matches the
 * `expectedValue` provided. This atomic `compare-and-set` operation is perfect for:
 * - Making a Winning Move: Instantly setting the value to the `targetValue`.
 * - Strategic Sabotage: Drastically changing the value to throw off opponents.
 *
 * ---
 *
 * ### WINNING
 *
 * The first player whose action results in the `value` matching the `targetValue`
 * wins the game. The winner is then able to withdraw the entire `prizePool`.
 */
contract RaceToTheTargetDataManager is Initializable {
    /// @dev Indicates configuration error: target value can not be zero
    error IncorrectTargetValue();
    /// @dev Indicates configuration error: Jump action price should be no less than Step action price
    error JumpPriceLessThanStepPrice();
    /// @dev Indicates that incorrect amount of native currency was sent with the call
    error IncorrectPayment(uint256 actualPayment, uint256 expectedPayment);

    /// @dev Emitted when value is changed
    event ValueChanged(uint256 newValue);
    /// @dev Emitted when Jump action is requested but failed
    event JumpFailed(uint256 expectedValue, uint256 actualValue);
    /// @dev Emitted when target value reached
    event TargetReached(address winner, uint256 prize);
    event PrizeTransferFailed(address winner, uint256 prize);

    /// @dev Type of the action, used to determine correct payment
    enum ActionType {
        STEP,
        JUMP
    }

    /// @dev Address of DataIndex contract
    IDataIndex internal _dataIndex;
    /// @dev DataPoint used in this instance of the game
    DataPoint internal _dataPoint;
    /// @dev Address of DataObject used to store current game value
    IDataObject internal _dataObject;

    /// @notice Price for increment() & decrement() actions
    uint256 public stepPrice;

    /// @notice Price for jump() action
    uint256 public jumpPrice;

    /// @notice Value players have to reach to win the prize
    uint256 public targetValue;

    modifier withPayment(ActionType actionType) {
        _requirePayment(actionType);
        _;
    }

    constructor() {
        // This contract SHOULD be used via Proxy (see how the RaceToTheTargetFactory uses Clones to deploy such proxies)
        // Such proxies can not use constructor for initialization, instead `initialize()` should be called.

        // Here we are disabling initialization of the logic contract: it should not be used directly
        _disableInitializers();
    }

    /**
     * Initialize the game instance (proxy)
     * @param dataIndex_ Address of DataIndex to be used for writing to a DataObject
     * @param dataPoint_ DataPoint to work with
     * @param dataObject_ Address of SampleDataObject
     * @param targetValue_ Value to be reached to win the game
     * @param stepPrice_ Price of increment & decrement actions
     * @param jumpPrice_ Price of jump action
     */
    function initialize(
        IDataIndex dataIndex_,
        DataPoint dataPoint_,
        IDataObject dataObject_,
        uint256 targetValue_,
        uint256 stepPrice_,
        uint256 jumpPrice_
    ) external initializer {
        // Validate game details
        // Note: Zero Jump & Step prices allowed for "just-for-fun" game
        require(targetValue_ > 0, IncorrectTargetValue());
        require(jumpPrice_ >= stepPrice_, JumpPriceLessThanStepPrice());

        // Store configuration
        _dataIndex = dataIndex_;
        _dataPoint = dataPoint_;
        _dataObject = dataObject_;
        targetValue = targetValue_;
        stepPrice = stepPrice_;
        jumpPrice = jumpPrice_;
    }

    /**
     * @return Current prize pool
     */
    function prizePool() public view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @return Current value
     */
    function currentValue() public view returns (uint256) {
        return abi.decode(_dataObject.read(_dataPoint, ISampleDataObjectOperations.value.selector, ""), (uint256));
    }

    /**
     * @notice Increments the value.
     * Sender should pay `stepPrice` to call this
     * If targetValue reached after increment, it will send prize to the sender.
     */
    function increment() external payable withPayment(ActionType.STEP) {
        uint256 newValue = abi.decode(_dataIndex.write(_dataObject, _dataPoint, ISampleDataObjectOperations.inc.selector, ""), (uint256));
        _handleNewValue(newValue);
    }

    /**
     * @notice Decrements the value
     * Sender should pay `stepPrice` to call this
     * If targetValue reached after decrement, it will send prize to the sender.
     * Note: if currentValue is zero, it can not be decremented and will revert.
     */
    function decrement() external payable withPayment(ActionType.STEP) {
        uint256 newValue = abi.decode(_dataIndex.write(_dataObject, _dataPoint, ISampleDataObjectOperations.dec.selector, ""), (uint256));
        _handleNewValue(newValue);
    }

    /**
     * @notice Set the value to a newValue
     * @param expectedValue Current value at a time tx with this call is included to the blockchain
     * @param newValue New value to set
     * Sender should pay `jumpPrice` to call this
     * If newValue is targetValue and execution is successful, the prize will be sent to the sender.
     */
    function jump(uint256 expectedValue, uint256 newValue) external payable withPayment(ActionType.JUMP) {
        bool success = abi.decode(
            _dataIndex.write(_dataObject, _dataPoint, ISampleDataObjectOperations.compareAndSet.selector, abi.encode(expectedValue, newValue)),
            (bool)
        );
        if (success) {
            _handleNewValue(newValue);
        } else {
            emit JumpFailed(expectedValue, currentValue());
        }
    }

    /**
     * @dev Verifies the payment matches action type
     * @param actionType Type of the action being executed
     */
    function _requirePayment(ActionType actionType) internal view {
        uint256 requiredValue = (actionType == ActionType.STEP) ? stepPrice : jumpPrice;
        require(msg.value == requiredValue, IncorrectPayment(msg.value, requiredValue));
    }

    /**
     * @dev Called after newValue is successfully set
     * @param newValue the new value 
     */
    function _handleNewValue(uint256 newValue) internal {
        if (newValue != targetValue) {
            // Target not reached, so do nothing, except emitting event
            emit ValueChanged(newValue);
            return;
        }

        // Target reached
        uint256 prize = prizePool();
        emit TargetReached(msg.sender, prize);

        // Send prize to the winner, if any
        if (prize > 0) {
            // If winner can not accept the payment, funds stay in prize pool for next round
            (bool success, ) = payable(msg.sender).call{value: prize}("");
            if (!success) {
                emit PrizeTransferFailed(msg.sender, prize);
            }
        }

        // Reset game state (0 value is the starting point)
        _dataIndex.write(_dataObject, _dataPoint, ISampleDataObjectOperations.set.selector, abi.encode(0));
        emit ValueChanged(0);
    }
}
