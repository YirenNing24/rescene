// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IEventItems {
    function balanceOf(address, uint256) external view returns (uint256);
    function safeTransferFrom(address, address, uint256, uint256, bytes calldata) external;
}

/// @notice Treasury-backed event rewards in existing Starlight Dust (token 11).
/// No mint privilege. Immutable bindings and durable IDs make retries harmless.
contract EventRefinementRewards {
    address public immutable treasury;
    IEventItems public immutable token;
    uint256 public constant tokenId = 11;
    mapping(bytes32 => bytes32) public payouts;
    bool private entered;
    event RewardPaid(bytes32 indexed rewardId, address indexed recipient, uint256 amount);

    constructor(address operator, address collection) {
        require(operator != address(0) && collection.code.length > 0, "invalid config");
        treasury = operator;
        token = IEventItems(collection);
    }

    function pay(bytes32 rewardId, address recipient, uint256 amount) external {
        require(msg.sender == treasury && !entered, "unauthorized");
        require(rewardId != bytes32(0) && recipient != address(0) && recipient != treasury && recipient != address(this) && amount > 0 && amount <= 10, "invalid reward");
        bytes32 digest = keccak256(abi.encode(recipient, amount));
        if (payouts[rewardId] != bytes32(0)) {
            require(payouts[rewardId] == digest, "reward mismatch");
            return;
        }
        entered = true;
        payouts[rewardId] = digest;
        uint256 beforeBalance = token.balanceOf(recipient, tokenId);
        token.safeTransferFrom(treasury, recipient, tokenId, amount, "");
        require(token.balanceOf(recipient, tokenId) == beforeBalance + amount, "delivery failed");
        emit RewardPaid(rewardId, recipient, amount);
        entered = false;
    }
}
