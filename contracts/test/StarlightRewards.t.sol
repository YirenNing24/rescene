// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {StarlightRewards} from "../src/StarlightRewards.sol";
contract TestStarlight is ERC20 {
    constructor() ERC20("RESCENE Starlight", "STARL") { _mint(msg.sender, 100000000 ether); }
}
contract StarlightRewardsTest is Test {
    TestStarlight token;
    StarlightRewards rewards;
    address player = address(0x123);
    function setUp() public {
        token = new TestStarlight();
        rewards = new StarlightRewards(address(token), address(this));
        token.approve(address(rewards), 100000000 ether);
    }
    function testPaysExistingSupplyAndRetriesDoNotPayAgain() public {
        bytes32 id = keccak256("reward");
        rewards.pay(id, player, 60 ether);
        rewards.pay(id, player, 60 ether);
        assertEq(token.balanceOf(player), 60 ether);
        assertEq(token.balanceOf(address(this)), (100000000 - 60) * 1 ether);
        assertEq(token.totalSupply(), 100000000 ether);
        assertEq(rewards.payouts(id), keccak256(abi.encode(player, 60 ether)));
        vm.expectRevert("reward mismatch"); rewards.pay(id, player, 61 ether);
        vm.expectRevert("reward mismatch"); rewards.pay(id, address(0x456), 60 ether);
    }
    function testUnauthorizedAndUnfundedRewardCannotBeRecorded() public {
        bytes32 id = keccak256("reward");
        vm.prank(player);vm.expectRevert("not treasury");rewards.pay(id, player, 60 ether);
        token.approve(address(rewards), 0);
        vm.expectRevert();rewards.pay(id, player, 60 ether);
        assertEq(rewards.payouts(id), bytes32(0));
        token.approve(address(rewards), 60 ether);
        rewards.pay(id, player, 60 ether);
        assertEq(token.balanceOf(player), 60 ether);
    }
    function testFuzzSameRewardIsPaidOnce(uint96 amount, uint8 retries) public {
        amount = uint96(bound(amount, 1, 100000000 ether));
        bytes32 id = keccak256(abi.encode(amount));
        for (uint256 i; i <= uint256(retries); i++) rewards.pay(id, player, amount);
        assertEq(token.balanceOf(player), amount);
        assertEq(token.totalSupply(), 100000000 ether);
    }
}
