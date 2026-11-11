// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IShopToken {
    function transferFrom(address,address,uint256) external returns(bool);
    function approve(address,uint256) external returns(bool);
}
interface IShopItems {
    function burn(address,uint256,uint256) external;
    function balanceOf(address,uint256) external view returns(uint256);
}
interface IShopMarket {
    struct Listing { uint256 listingId; uint256 tokenId; uint256 quantity; uint256 pricePerToken; uint128 startTimestamp; uint128 endTimestamp; address listingCreator; address assetContract; address currency; uint8 tokenType; uint8 status; bool reserved; }
    function getListing(uint256) external view returns(Listing memory);
    function buyFromListing(uint256,address,uint256,address,uint256) external payable;
}
/// @notice A single listed consumable. Treasury pays gas; buyer supplies STARL.
/// Engine retries are safe at the chain level for funding, buying and burning.
contract EnergyDrinkShop {
    address public immutable operator;
    IShopToken public immutable token;
    IShopItems public immutable items;
    IShopMarket public immutable market;
    uint256 public immutable tokenId;
    uint256 public immutable listingId;
    uint256 public constant unitPrice = 100 ether;
    mapping(bytes32=>bytes32) public purchases;
    mapping(bytes32=>address) public consumptions;
    mapping(bytes32=>bytes32) public gasGrants;
    bool private entered;
    event Purchased(bytes32 indexed orderId,address indexed buyer,uint256 quantity,uint256 total);
    event Consumed(bytes32 indexed consumeId,address indexed player,uint256 indexed itemId);
    event GasGranted(bytes32 indexed actionId,address indexed player,uint256 amount);
    modifier onlyOperator(){require(msg.sender==operator,"not operator");_;}
    modifier nonReentrant(){require(!entered,"reentrant");entered=true;_;entered=false;}
    constructor(address op,address erc20,address erc1155,address marketplace,uint256 itemId,uint256 saleId){
        require(op!=address(0) && erc20.code.length>0 && erc1155.code.length>0 && marketplace.code.length>0,"invalid config");
        operator=op;token=IShopToken(erc20);items=IShopItems(erc1155);market=IShopMarket(marketplace);tokenId=itemId;listingId=saleId;
    }
    function purchase(bytes32 orderId,address buyer,uint256 quantity) external onlyOperator nonReentrant {
        require(orderId!=bytes32(0) && buyer!=address(0) && buyer!=operator && quantity>0 && quantity<=10,"invalid order");
        bytes32 digest=keccak256(abi.encode(buyer,quantity));
        if(purchases[orderId]!=bytes32(0)){require(purchases[orderId]==digest,"order mismatch");return;}
        IShopMarket.Listing memory l=market.getListing(listingId);
        require(l.assetContract==address(items) && l.tokenId==tokenId && l.currency==address(token) && l.listingCreator==operator && l.pricePerToken==unitPrice && l.tokenType==1 && l.status==1 && !l.reserved && l.quantity>=quantity && l.startTimestamp<=block.timestamp && l.endTimestamp>block.timestamp,"listing changed");
        purchases[orderId]=digest;
        uint256 total=unitPrice*quantity;
        uint256 beforeBalance=items.balanceOf(buyer,tokenId);
        require(token.transferFrom(buyer,address(this),total),"payment failed");
        require(token.approve(address(market),total),"approval failed");
        market.buyFromListing(listingId,buyer,quantity,address(token),total);
        require(items.balanceOf(buyer,tokenId)==beforeBalance+quantity,"delivery failed");
        emit Purchased(orderId,buyer,quantity,total);
    }
    function consume(bytes32 consumeId,address player) external onlyOperator nonReentrant {
        require(consumeId!=bytes32(0) && player!=address(0) && player!=operator,"invalid consume");
        if(consumptions[consumeId]!=address(0)){require(consumptions[consumeId]==player,"consume mismatch");return;}
        consumptions[consumeId]=player;
        items.burn(player,tokenId,1);
        emit Consumed(consumeId,player,tokenId);
    }
    function fundGas(bytes32 actionId,address player) external payable onlyOperator nonReentrant {
        require(actionId!=bytes32(0) && player!=address(0) && player!=operator && msg.value>0 && msg.value<=0.0001 ether,"invalid gas grant");
        bytes32 digest=keccak256(abi.encode(player,msg.value));
        if(gasGrants[actionId]!=bytes32(0)){
            require(gasGrants[actionId]==digest,"gas mismatch");
            (bool refund,)=payable(operator).call{value:msg.value}("");require(refund,"refund failed");return;
        }
        gasGrants[actionId]=digest;
        (bool sent,)=payable(player).call{value:msg.value}("");require(sent,"gas failed");
        emit GasGranted(actionId,player,msg.value);
    }
}
