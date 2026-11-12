// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";
import {ReleaseCards} from "../src/ReleaseCards.sol";
import {PulseCardsHarness,PulseItemsMock} from "./PulseCards.t.sol";
import {ShopCoin} from "./EnergyDrinkShop.t.sol";

contract ReleaseCardsTest is Test {
    ShopCoin coin;
    PulseItemsMock items;
    PulseCardsHarness old;
    ReleaseCards cards;
    address player=address(0xabc);
    uint256 nonce;

    function key() internal returns(bytes32) { return keccak256(abi.encode(++nonce)); }
    function setUp() public {
        coin=new ShopCoin();items=new PulseItemsMock();
        old=new PulseCardsHarness(address(this),address(coin),address(items),[uint256(11),12,13]);
        items.authorize(address(old));
        for(uint256 id=11;id<=13;id++)items.seed(player,id,100);
        coin.mint(player,1000000 ether);
        vm.prank(player);coin.approve(address(old),type(uint256).max);
        old.setSalesEnabled(true);old.purchase(key(),player,0,800,9,1);
        old.setProgress(14,37,123,3,2);
        old.protect(key(),player,14,true,1);
        old.equip(key(),player,1,0,14);
        old.setInUse(player,14,block.timestamp+100);
        old.setSalesEnabled(false);
        cards=new ReleaseCards(address(this),address(coin),address(items),address(old));
        items.authorize(address(cards));
        vm.startPrank(player);coin.approve(address(cards),type(uint256).max);items.setApprovalForAll(address(cards),true);vm.stopPrank();
    }
    function migrate() internal {
        uint256[] memory tokens=new uint256[](1);tokens[0]=14;
        address[] memory owners=new address[](1);owners[0]=player;
        cards.importLegacy(tokens,owners);cards.finishMigration();cards.setSalesEnabled(true);
    }
    function testMigrationPreservesInvestmentAndAllocation() public {
        uint256[14] memory beforeState=old.viewCard(player,14);
        migrate();uint256[14] memory afterState=cards.viewCard(player,14);
        assertEq(abi.encode(beforeState),abi.encode(afterState));
        assertEq(cards.deck(player,1)[0],14);assertEq(cards.cardSet(14),1);
        assertEq(cards.initialLESold(0),1);assertEq(items.totalSupply(14),1);
        assertEq(cards.inUseUntil(player,14),old.inUseUntil(player,14));
    }
    function testCannotOpenIncompleteMigrationOrImportTwice() public {
        vm.expectRevert("migration incomplete");cards.setSalesEnabled(true);
        vm.expectRevert("migration incomplete");cards.finishMigration();
        migrate();uint256[] memory tokens=new uint256[](1);address[] memory owners=new address[](1);
        tokens[0]=14;owners[0]=player;
        vm.expectRevert("migration closed");cards.importLegacy(tokens,owners);
    }
    function testAll45ProductsHaveCorrectSetMemberAndPayment() public {
        migrate();uint256 balance=coin.balanceOf(player);
        for(uint256 member=0;member<45;member++) {
            bytes32 order=key();cards.purchase(order,player,member,900,8,2);
            uint256 token=cards.minted(order);uint256[14] memory state=cards.viewCard(player,token);
            assertEq(cards.cardSet(token),member/5+1);assertEq(state[0],member%5);
            assertEq(items.balanceOf(player,token),1);assertEq(items.totalSupply(token),1);
            cards.equip(key(),player,member/5+1,member%5,token);
            assertEq(cards.deck(player,member/5+1)[member%5],token);
            assertEq(cards.flags(player,token)&2,2);
        }
        assertEq(coin.balanceOf(player),balance-45*450 ether);
    }
    function testWrongReleaseRejectedAndRetryDoesNotRemint() public {
        migrate();bytes32 order=key();cards.purchase(order,player,12,700,10,6);
        uint256 token=cards.minted(order);uint256 balance=coin.balanceOf(player);
        cards.purchase(order,player,12,700,10,6);
        assertEq(coin.balanceOf(player),balance);assertEq(cards.count(),2);
        vm.expectRevert("card unavailable");cards.equip(key(),player,2,2,token);
        cards.equip(key(),player,3,2,token);
        vm.expectRevert("action mismatch");cards.purchase(order,player,17,700,10,6);
    }
    function testAllocationIsPerReleaseMemberAndBurnsDoNotReplenish() public {
        migrate();
        for(uint256 i=0;i<50;i++)cards.purchase(key(),player,44,800,8,1);
        vm.expectRevert("allocation exhausted");cards.purchase(key(),player,44,800,8,1);
        cards.purchase(key(),player,39,800,8,1);
        assertEq(cards.initialLESold(44),50);assertEq(cards.initialLESold(39),1);
    }
    function testCrossReleaseSacrificeKeepsReceiverSetAndDestroysDonors() public {
        migrate();bytes32 k=key();cards.purchase(k,player,5,800,8,1);uint256 receiver=cards.minted(k);
        uint256[] memory donors=new uint256[](2);
        k=key();cards.purchase(k,player,10,800,8,1);donors[0]=cards.minted(k);
        k=key();cards.purchase(k,player,44,800,8,1);donors[1]=cards.minted(k);
        cards.starUpgrade(key(),player,receiver,donors,1);
        assertEq(cards.viewCard(player,receiver)[7],2);assertEq(cards.cardSet(receiver),2);
        for(uint256 i;i<2;i++)assertEq(items.totalSupply(donors[i]),0);
    }
}
