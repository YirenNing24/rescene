// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";
import {MemberCardShop} from "../src/MemberCardShop.sol";
import {IShopMarket} from "../src/EnergyDrinkShop.sol";
import {ShopCoin, ShopItems, ShopMarket} from "./EnergyDrinkShop.t.sol";
contract CardItems is ShopItems {
    function mintCard(address owner, uint256 id, uint256 quantity) external { balanceOf[owner][id] += quantity; }
}
contract MemberCardShopTest is Test {
    ShopCoin coin; CardItems items; ShopMarket market; MemberCardShop shop;
    address buyer = address(0xabc);
    function setUp() public {
        coin = new ShopCoin(); items = new CardItems(); market = new ShopMarket();
        shop = new MemberCardShop(address(this), address(coin), address(items), address(market), 1, 1);
        coin.mint(buyer, 10000 ether);
        vm.prank(buyer); coin.approve(address(shop), 10000 ether);
        items.setApprovalForAll(address(market), true);
        for (uint256 id = 1; id <= 5; id++) items.mintCard(address(this), id, 10000);
    }
    function listing(uint256 id) internal {
        market.set(IShopMarket.Listing(id,id,10000,450 ether,0,type(uint128).max,address(this),address(items),address(coin),1,1,false));
    }
    function testAllFiveCardsPayDeliverAndRetryOnce() public {
        for (uint256 id = 1; id <= 5; id++) {
            listing(id); bytes32 order = keccak256(abi.encode(id));
            shop.purchaseCard(order,buyer,1,id); shop.purchaseCard(order,buyer,1,id);
            assertEq(items.balanceOf(buyer,id),1);
        }
        assertEq(coin.balanceOf(buyer),7750 ether);
    }
    function testOrderCannotSwitchCardOrQuantity() public {
        listing(1); bytes32 order = keccak256("order"); shop.purchaseCard(order,buyer,1,1);
        vm.expectRevert("order mismatch"); shop.purchaseCard(order,buyer,1,2);
        vm.expectRevert("order mismatch"); shop.purchaseCard(order,buyer,2,1);
    }
    function testBadItemPriceAndAuthorizationReject() public {
        listing(1);
        vm.expectRevert("invalid card"); shop.purchaseCard(keccak256("drink"),buyer,1,0);
        vm.expectRevert("invalid card"); shop.purchaseCard(keccak256("other"),buyer,1,6);
        IShopMarket.Listing memory l = market.getListing(1); l.pricePerToken = 451 ether; market.set(l);
        vm.expectRevert("listing changed"); shop.purchaseCard(keccak256("price"),buyer,1,1);
        vm.prank(buyer); vm.expectRevert("not operator"); shop.purchaseCard(keccak256("forged"),buyer,1,1);
        assertEq(coin.balanceOf(buyer),10000 ether);
    }
    function testPaymentFailureRollsBackOrderAndInventory() public {
        listing(1); vm.prank(buyer); coin.approve(address(shop),0);
        bytes32 order = keccak256("no approval"); vm.expectRevert(); shop.purchaseCard(order,buyer,1,1);
        assertEq(shop.purchases(order),bytes32(0)); assertEq(items.balanceOf(buyer,1),0);
    }
    function testFuzzCardAndQuantity(uint8 id, uint8 quantity) public {
        id = uint8(bound(id,1,5)); quantity = uint8(bound(quantity,1,10)); listing(id);
        bytes32 order = keccak256(abi.encode(id,quantity));
        shop.purchaseCard(order,buyer,quantity,id); shop.purchaseCard(order,buyer,quantity,id);
        assertEq(items.balanceOf(buyer,id),quantity);
        assertEq(coin.balanceOf(buyer),(10000-uint256(quantity)*450)*1 ether);
    }
}
