// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
interface IStarlight {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
/// @notice Moves existing treasury tokens once per backend reward ID. No minting.
contract StarlightRewards {
    IStarlight public immutable token;
    address public immutable treasury;
    mapping(bytes32 => bytes32) public payouts;
    event RewardPaid(bytes32 indexed rewardId, address indexed recipient, uint256 amount);
    constructor(address tokenAddress, address treasuryAddress) {
        require(tokenAddress.code.length > 0 && treasuryAddress != address(0), "invalid configuration");
        token = IStarlight(tokenAddress);
        treasury = treasuryAddress;
    }
    function pay(bytes32 rewardId, address recipient, uint256 amount) external {
        require(msg.sender == treasury, "not treasury");
        require(rewardId != bytes32(0) && recipient != address(0) && recipient != treasury && recipient != address(this) && amount > 0, "invalid reward");
        bytes32 digest = keccak256(abi.encode(recipient, amount));
        bytes32 previous = payouts[rewardId];
        if (previous != bytes32(0)) {
            require(previous == digest, "reward mismatch");
            return;
        }
        payouts[rewardId] = digest;
        require(token.transferFrom(treasury, recipient, amount), "transfer failed");
        emit RewardPaid(rewardId, recipient, amount);
    }
}
