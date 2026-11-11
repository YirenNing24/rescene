// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {EnergyDrinkShop,IShopMarket} from "../src/EnergyDrinkShop.sol";
contract ShopCoin is ERC20 {constructor() ERC20("Starlight","STARL"){}function mint(address a,uint n)external{_mint(a,n);}}
contract ShopItems {
    mapping(address=>mapping(uint=>uint)) public balanceOf;
    mapping(address=>mapping(address=>bool)) public isApprovedForAll;
    function mint(address a,uint n)external{balanceOf[a][0]+=n;}
    function setApprovalForAll(address a,bool yes)external{isApprovedForAll[msg.sender][a]=yes;}
    function burn(address a,uint id,uint n)external{require(msg.sender==a || isApprovedForAll[a][msg.sender],"not approved");require(balanceOf[a][id]>=n);balanceOf[a][id]-=n;}
    function safeTransferFrom(address from,address to,uint id,uint n,bytes memory)external{require(msg.sender==from || isApprovedForAll[from][msg.sender],"not approved");require(balanceOf[from][id]>=n);balanceOf[from][id]-=n;balanceOf[to][id]+=n;}
}
contract ShopMarket is IShopMarket {
    Listing public listing;
    function set(Listing memory l)external{listing=l;}
    function getListing(uint)external view returns(Listing memory){return listing;}
    function buyFromListing(uint,address buyer,uint n,address currency,uint total)external payable{require(currency==listing.currency && total==n*listing.pricePerToken);ShopCoin(currency).transferFrom(msg.sender,listing.listingCreator,total);ShopItems(listing.assetContract).safeTransferFrom(listing.listingCreator,buyer,listing.tokenId,n,"");listing.quantity-=n;}
}
contract EnergyDrinkShopTest is Test,ERC1155Holder {
    ShopCoin coin;ShopItems items;ShopMarket market;EnergyDrinkShop shop;address buyer=address(0xabc);
    function setUp()public{coin=new ShopCoin();items=new ShopItems();market=new ShopMarket();shop=new EnergyDrinkShop(address(this),address(coin),address(items),address(market),0,0);items.mint(address(this),10000);items.setApprovalForAll(address(market),true);market.set(IShopMarket.Listing(0,0,10000,100 ether,0,type(uint128).max,address(this),address(items),address(coin),1,1,false));coin.mint(buyer,1000 ether);vm.startPrank(buyer);coin.approve(address(shop),1000 ether);items.setApprovalForAll(address(shop),true);vm.stopPrank();}
    function testAtomicPaymentDeliveryAndExactlyOnceBurn()public{bytes32 id=keccak256("buy");shop.purchase(id,buyer,2);shop.purchase(id,buyer,2);assertEq(coin.balanceOf(buyer),800 ether);assertEq(items.balanceOf(buyer,0),2);vm.expectRevert("order mismatch");shop.purchase(id,buyer,1);bytes32 consumeId=keccak256("consume");shop.consume(consumeId,buyer);shop.consume(consumeId,buyer);assertEq(items.balanceOf(buyer,0),1);}
    function testRejectsPriceChangeAndDoesNotCharge()public{IShopMarket.Listing memory l=market.getListing(0);l.pricePerToken=101 ether;market.set(l);vm.expectRevert("listing changed");shop.purchase(keccak256("buy"),buyer,1);assertEq(coin.balanceOf(buyer),1000 ether);assertEq(items.balanceOf(buyer,0),0);}
    function testInsufficientFundsAndMissingApprovalRollback()public{vm.prank(buyer);coin.approve(address(shop),0);vm.expectRevert();shop.purchase(keccak256("buy"),buyer,1);assertEq(shop.purchases(keccak256("buy")),bytes32(0));vm.expectRevert();shop.consume(keccak256("use"),buyer);assertEq(shop.consumptions(keccak256("use")),address(0));}
    function testOnlyOperator()public{vm.deal(buyer,1 ether);vm.startPrank(buyer);vm.expectRevert("not operator");shop.purchase(bytes32(uint256(1)),buyer,1);vm.expectRevert("not operator");shop.consume(bytes32(uint256(1)),buyer);vm.expectRevert("not operator");shop.fundGas{value:1}(bytes32(uint256(1)),buyer);vm.stopPrank();}
    function testGasRetryRefundsInsteadOfFundingTwice()public{vm.deal(address(this),1 ether);bytes32 id=keccak256("gas");shop.fundGas{value:0.00005 ether}(id,buyer);shop.fundGas{value:0.00005 ether}(id,buyer);assertEq(buyer.balance,0.00005 ether);}
    function testFuzzRetriesCannotDuplicate(uint8 quantity,uint8 retries)public{quantity=uint8(bound(quantity,1,10));bytes32 id=keccak256(abi.encode(quantity));for(uint i;i<=retries;i++)shop.purchase(id,buyer,quantity);assertEq(items.balanceOf(buyer,0),quantity);assertEq(coin.balanceOf(buyer),(1000-uint(quantity)*100)*1 ether);}
    receive()external payable{}
}
