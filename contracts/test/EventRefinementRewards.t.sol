// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";
import {EventRefinementRewards} from "../src/EventRefinementRewards.sol";
contract TestDust {
    mapping(address => mapping(uint256 => uint256)) public balanceOf;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    constructor() { balanceOf[msg.sender][11]=100; }
    function setApprovalForAll(address operator, bool value) external { isApprovedForAll[msg.sender][operator]=value; }
    function safeTransferFrom(address from,address to,uint256 id,uint256 amount,bytes calldata) external {
        require(msg.sender==from || isApprovedForAll[from][msg.sender],"not approved");
        balanceOf[from][id]-=amount;balanceOf[to][id]+=amount;
    }
}
contract EventRefinementRewardsTest is Test {
    TestDust token;
    EventRefinementRewards rewards;
    address player = address(0x123);
    function setUp() public {
        token = new TestDust();
        rewards = new EventRefinementRewards(address(this),address(token));
        token.setApprovalForAll(address(rewards),true);
    }
    function testPaysOnceAndBindsRewardParameters() public {
        bytes32 id = keccak256("reward");
        rewards.pay(id,player,3);
        rewards.pay(id,player,3);
        assertEq(token.balanceOf(player,11),3);
        assertEq(token.balanceOf(address(this),11),97);
        assertEq(rewards.payouts(id),keccak256(abi.encode(player,uint256(3))));
        vm.expectRevert("reward mismatch"); rewards.pay(id,player,4);
        vm.expectRevert("reward mismatch"); rewards.pay(id,address(0x456),3);
    }
    function testUnfundedAndUnauthorizedCannotRecordReward() public {
        bytes32 id = keccak256("reward");
        vm.prank(player); vm.expectRevert("unauthorized"); rewards.pay(id,player,1);
        token.setApprovalForAll(address(rewards),false);
        vm.expectRevert(); rewards.pay(id,player,1);
        assertEq(rewards.payouts(id),bytes32(0));
        token.setApprovalForAll(address(rewards),true);
        rewards.pay(id,player,1);
        assertEq(token.balanceOf(player,11),1);
    }
    function testFuzzRetriesPayOnce(uint8 amount, uint8 retries) public {
        amount=uint8(bound(amount,1,10)); retries=uint8(bound(retries,0,20));
        bytes32 id=keccak256(abi.encode(amount));
        for (uint256 i; i<=retries; i++) rewards.pay(id,player,amount);
        assertEq(token.balanceOf(player,11),amount);
    }
}
