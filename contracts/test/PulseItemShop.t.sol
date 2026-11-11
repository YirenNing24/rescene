// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";
import {PulseItemShop} from "../src/PulseItemShop.sol";
import {IShopMarket} from "../src/EnergyDrinkShop.sol";
import {ShopCoin,ShopMarket} from "./EnergyDrinkShop.t.sol";
import {CardItems} from "./MemberCardShop.t.sol";
contract PulseItemShopTest is Test {
    ShopCoin coin;CardItems items;ShopMarket market;PulseItemShop shop;
    address buyer=address(0xabc);
    function setUp() public {
        coin=new ShopCoin();items=new CardItems();market=new ShopMarket();
        shop=new PulseItemShop(address(this),address(coin),address(items),address(market),6,6);
        coin.mint(buyer,10000 ether);vm.prank(buyer);coin.approve(address(shop),10000 ether);
        items.setApprovalForAll(address(market),true);
        for(uint256 id=6;id<=13;id++)items.mintCard(address(this),id,10000);
    }
    function listing(uint256 id) internal {market.set(IShopMarket.Listing(id,id,10000,shop.priceFor(id),0,type(uint128).max,address(this),address(items),address(coin),1,1,false));}
    function testAllProductsExactPaymentAndDelivery() public {
        for(uint256 id=6;id<=13;id++){listing(id);bytes32 order=keccak256(abi.encode(id));shop.purchaseItem(order,buyer,1,id);shop.purchaseItem(order,buyer,1,id);assertEq(items.balanceOf(buyer,id),1);}
        assertEq(coin.balanceOf(buyer),6750 ether);
    }
    function testEnhancementBurnsOnceAndCannotChangeTarget() public {
        items.mintCard(buyer,8,1);items.mintCard(buyer,11,2);vm.prank(buyer);items.setApprovalForAll(address(shop),true);
        bytes32 id=keccak256("enhance");shop.enhance(id,buyer,11,8);shop.enhance(id,buyer,11,8);
        assertEq(items.balanceOf(buyer,11),1);assertEq(items.balanceOf(buyer,8),1);
        vm.expectRevert("enhancement mismatch");shop.enhance(id,buyer,11,9);
    }
    function testMissingCardOrMaterialCannotBurnOrRecord() public {
        items.mintCard(buyer,11,1);vm.prank(buyer);items.setApprovalForAll(address(shop),true);
        bytes32 id=keccak256("missing");vm.expectRevert("card not owned");shop.enhance(id,buyer,11,8);
        assertEq(items.balanceOf(buyer,11),1);assertEq(shop.enhancements(id),bytes32(0));
        items.mintCard(buyer,8,1);vm.expectRevert();shop.enhance(id,buyer,12,8);assertEq(shop.enhancements(id),bytes32(0));
    }
    function testPriceChangeAndUnauthorizedCallsRevert() public {
        listing(11);IShopMarket.Listing memory l=market.getListing(11);l.pricePerToken=151 ether;market.set(l);
        vm.expectRevert("listing changed");shop.purchaseItem(keccak256("bad price"),buyer,1,11);
        vm.prank(buyer);vm.expectRevert("not operator");shop.enhance(keccak256("forged"),buyer,11,8);
        vm.expectRevert("invalid items");shop.enhance(keccak256("card burn"),buyer,8,9);
        assertEq(coin.balanceOf(buyer),10000 ether);
    }
    function testFuzzProductRetries(uint8 id,uint8 quantity) public {
        id=uint8(bound(id,6,13));quantity=uint8(bound(quantity,1,10));listing(id);
        bytes32 order=keccak256(abi.encode(id,quantity));shop.purchaseItem(order,buyer,quantity,id);shop.purchaseItem(order,buyer,quantity,id);
        assertEq(items.balanceOf(buyer,id),quantity);assertEq(coin.balanceOf(buyer),10000 ether-shop.priceFor(id)*quantity);
    }
}
