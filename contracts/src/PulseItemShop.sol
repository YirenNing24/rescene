// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IShopToken, IShopItems, IShopMarket} from "./EnergyDrinkShop.sol";

/// @notice PULSE LE cards and enhancement bundles, with fixed item prices.
/// Payment and delivery are atomic; retries use a durable order ID.
contract PulseItemShop {
    address public immutable operator;
    IShopToken public immutable token;
    IShopItems public immutable items;
    IShopMarket public immutable market;
    uint256 public immutable tokenId;
    uint256 public immutable listingId;
    uint256 public constant unitPrice = 450 ether;
    mapping(bytes32 => bytes32) public purchases;
    mapping(bytes32 => bytes32) public gasGrants;
    mapping(bytes32 => bytes32) public enhancements;
    bool private entered;
    event Purchased(bytes32 indexed orderId, address indexed buyer, uint256 quantity, uint256 total);
    event Enhanced(bytes32 indexed orderId,address indexed player,uint256 materialId,uint256 cardId);
    event GasGranted(bytes32 indexed actionId, address indexed player, uint256 amount);
    modifier onlyOperator() { require(msg.sender == operator, "not operator"); _; }
    modifier nonReentrant() { require(!entered, "reentrant"); entered = true; _; entered = false; }

    constructor(address op, address erc20, address erc1155, address marketplace, uint256 firstItem, uint256 firstListing) {
        require(op != address(0) && erc20.code.length > 0 && erc1155.code.length > 0 && marketplace.code.length > 0, "invalid config");
        operator = op; token = IShopToken(erc20); items = IShopItems(erc1155); market = IShopMarket(marketplace);
        require(firstItem==6 && firstListing==6,"invalid item range");
        tokenId = firstItem; listingId = firstListing;
    }

    function purchaseItem(bytes32 orderId, address buyer, uint256 quantity, uint256 itemId) external onlyOperator nonReentrant {
        require(orderId != bytes32(0) && buyer != address(0) && buyer != operator && quantity > 0 && quantity <= 10, "invalid order");
        require(itemId >= tokenId && itemId - tokenId < 8, "invalid item");
        bytes32 digest = keccak256(abi.encode(buyer, quantity, itemId));
        if (purchases[orderId] != bytes32(0)) { require(purchases[orderId] == digest, "order mismatch"); return; }
        uint256 saleId = listingId + itemId - tokenId;
        IShopMarket.Listing memory l = market.getListing(saleId);
        require(l.assetContract == address(items) && l.tokenId == itemId && l.currency == address(token) && l.listingCreator == operator && l.pricePerToken == priceFor(itemId) && l.tokenType == 1 && l.status == 1 && !l.reserved && l.quantity >= quantity && l.startTimestamp <= block.timestamp && l.endTimestamp > block.timestamp, "listing changed");
        purchases[orderId] = digest;
        uint256 total = priceFor(itemId) * quantity;
        uint256 beforeBalance = items.balanceOf(buyer, itemId);
        require(token.transferFrom(buyer, address(this), total), "payment failed");
        require(token.approve(address(market), total), "approval failed");
        market.buyFromListing(saleId, buyer, quantity, address(token), total);
        require(items.balanceOf(buyer, itemId) == beforeBalance + quantity, "delivery failed");
        emit Purchased(orderId, buyer, quantity, total);
    }

    function priceFor(uint256 itemId) public pure returns(uint256) {
        require(itemId>=6 && itemId<=13,"invalid item");
        if(itemId<=10) return 450 ether;
        if(itemId==11) return 150 ether;
        if(itemId==12) return 300 ether;
        return 550 ether;
    }
    function enhance(bytes32 orderId,address player,uint256 materialId,uint256 cardId) external onlyOperator nonReentrant {
        require(orderId!=bytes32(0) && player!=address(0) && player!=operator,"invalid enhancement");
        require(materialId>=11 && materialId<=13 && cardId>=6 && cardId<=10,"invalid items");
        bytes32 digest=keccak256(abi.encode(player,materialId,cardId));
        if(enhancements[orderId]!=bytes32(0)){require(enhancements[orderId]==digest,"enhancement mismatch");return;}
        require(items.balanceOf(player,cardId)>0,"card not owned");
        enhancements[orderId]=digest;
        items.burn(player,materialId,1);
        emit Enhanced(orderId,player,materialId,cardId);
    }

    function fundGas(bytes32 actionId, address player) external payable onlyOperator nonReentrant {
        require(actionId != bytes32(0) && player != address(0) && player != operator && msg.value > 0 && msg.value <= 0.0001 ether, "invalid gas grant");
        bytes32 digest = keccak256(abi.encode(player, msg.value));
        if (gasGrants[actionId] != bytes32(0)) {
            require(gasGrants[actionId] == digest, "gas mismatch");
            (bool refund,) = payable(operator).call{value: msg.value}(""); require(refund, "refund failed"); return;
        }
        gasGrants[actionId] = digest;
        (bool sent,) = payable(player).call{value: msg.value}(""); require(sent, "gas failed");
        emit GasGranted(actionId, player, msg.value);
    }
}
