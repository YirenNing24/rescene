// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IShopToken, IShopItems} from "./EnergyDrinkShop.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

interface IPulseItems is IShopItems {
    function mintTo(address, uint256, string calldata, uint256) external;
    function nextTokenIdToMint() external view returns (uint256);
    function setTokenURI(uint256, string calldata) external;
    function totalSupply(uint256) external view returns (uint256);
    function safeTransferFrom(address, address, uint256, uint256, bytes calldata) external;
}

/// @notice Individual, supply-one cards in the existing ERC-1155 collection.
/// Trusted operator supplies cryptographic rolls; this is not a VRF contract.
/// Mint/payment, material burns/refinement and donor burns/star gains are atomic.
contract PulseCards {
    struct Card {
        uint256 member;
        uint256 rarity;
        uint256 scoreBP;
        uint256 recoveryBP;
        uint256 skill;
        uint256 xp;
        uint256 level;
        uint256 stars;
        uint256 progress;
        uint256 revision;
        bool burned;
    }
    address public immutable operator;
    IShopToken public immutable token;
    IPulseItems public immutable items;
    uint256[3] public materialIds;
    uint256 public constant unitPrice = 450 ether;
    uint256 public constant VERSION = 2;
    bool public salesEnabled;
    // Initial public allocation, not a lifetime rarity/artwork cap. Admin generation
    // remains available and does not replenish this allocation, including after burns.
    uint256 public constant INITIAL_LE_ALLOCATION = 50;
    bool public constant ARTWORK_MAY_BE_REISSUED = true;
    mapping(uint256 => uint256) public initialLESold;
    mapping(uint256 => Card) internal cards;
    uint256[] internal ids;
    mapping(bytes32 => bytes32) public actions;
    mapping(bytes32 => uint256) public minted;
    mapping(address => mapping(uint256 => bool)) public locked;
    mapping(address => mapping(uint256 => bool)) public listed;
    mapping(address => mapping(uint256 => uint256)) public inUseUntil;
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) public decks;
    bool private entered;
    event CardAction(
        bytes32 indexed actionId, address indexed player, uint256 indexed cardId, uint256 kind, uint256 result
    );
    event CardGenerated(bytes32 indexed actionId, address indexed player, uint256 indexed cardId);
    event SalesEnabled(bool enabled);
    modifier onlyOperator() {
        require(msg.sender == operator, "not operator");
        _;
    }
    modifier nonReentrant() {
        require(!entered, "reentrant");
        entered = true;
        _;
        entered = false;
    }

    constructor(address op, address erc20, address erc1155, uint256[3] memory materials) {
        require(op != address(0) && erc20.code.length > 0 && erc1155.code.length > 0, "invalid config");
        require(
            materials[0] != materials[1] && materials[0] != materials[2] && materials[1] != materials[2],
            "duplicate materials"
        );
        operator = op;
        token = IShopToken(erc20);
        items = IPulseItems(erc1155);
        materialIds = materials;
    }

    function setSalesEnabled(bool enabled) external onlyOperator {
        require(!enabled || _canOpenSales(), "migration incomplete");
        salesEnabled = enabled;
        emit SalesEnabled(enabled);
    }

    function count() external view returns (uint256) {
        return ids.length;
    }

    function tokenIds(uint256 offset, uint256 limit) external view returns (uint256[] memory out) {
        require(limit <= 1000, "page too large");
        uint256 end = offset >= ids.length ? offset : _min(ids.length, offset + limit);
        out = new uint256[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            out[i - offset] = ids[i];
        }
    }

    function viewCard(address player, uint256 id) external view returns (uint256[14] memory v) {
        Card memory c = cards[id];
        if (c.level == 0) return v;
        v = [
            c.member,
            c.rarity,
            c.scoreBP,
            c.recoveryBP,
            c.skill,
            c.xp,
            c.level,
            c.stars,
            c.progress,
            c.revision,
            (c.burned || items.totalSupply(id) != 1) ? 1 : 0,
            flags(player, id),
            c.scoreBP * (10000 + (c.level - 1) * 2000 / 99) / 10000,
            c.recoveryBP * 100 * (10000 + (c.level - 1) * 2000 / 99) / 10000
        ];
    }

    function flags(address player, uint256 id) public view returns (uint256) {
        return (locked[player][id] ? 1 : 0) | (decks[player][_setForCard(id)][cards[id].member] == id ? 2 : 0)
            | (listed[player][id] ? 4 : 0) | (inUseUntil[player][id] > block.timestamp ? 8 : 0);
    }

    function purchase(
        bytes32 actionId,
        address player,
        uint256 member,
        uint256 scoreBP,
        uint256 recoveryBP,
        uint256 skill
    ) external onlyOperator nonReentrant {
        bytes32 digest = keccak256(abi.encode(uint256(1), player, member, scoreBP, recoveryBP, skill));
        if (_retry(actionId, digest)) return;
        require(salesEnabled, "sales closed");
        require(_validPurchaseMember(member) && initialLESold[member] < INITIAL_LE_ALLOCATION, "allocation exhausted");
        initialLESold[member]++;
        require(token.transferFrom(player, operator, unitPrice), "payment failed");
        uint256 id = _generate(player, member, 5, scoreBP, recoveryBP, skill);
        minted[actionId] = id;
        emit CardAction(actionId, player, id, 1, unitPrice);
    }

    function materialPrice(uint256 id) public view returns (uint256) {
        if (id == materialIds[0]) return 150 ether;
        if (id == materialIds[1]) return 300 ether;
        if (id == materialIds[2]) return 550 ether;
        revert("invalid material");
    }

    function materialStock(uint256 id) external view returns (uint256) {
        materialPrice(id);
        return items.balanceOf(operator, id);
    }

    function purchaseMaterial(bytes32 actionId, address player, uint256 id, uint256 quantity)
        external
        onlyOperator
        nonReentrant
    {
        if (_retry(actionId, keccak256(abi.encode(uint256(7), player, id, quantity)))) return;
        require(salesEnabled && player != address(0) && quantity > 0 && quantity <= 10, "invalid material order");
        require(token.transferFrom(player, operator, materialPrice(id) * quantity), "payment failed");
        uint256 beforeBalance = items.balanceOf(player, id);
        items.safeTransferFrom(operator, player, id, quantity, "");
        require(items.balanceOf(player, id) == beforeBalance + quantity, "delivery failed");
        emit CardAction(actionId, player, id, 7, quantity);
    }

    /// @dev Administrative generation uses the same immutable roll validation.
    function generate(
        bytes32 actionId,
        address player,
        uint256 member,
        uint256 rarity,
        uint256 scoreBP,
        uint256 recoveryBP,
        uint256 skill
    ) external onlyOperator nonReentrant {
        bytes32 digest = keccak256(abi.encode(uint256(2), player, member, rarity, scoreBP, recoveryBP, skill));
        if (_retry(actionId, digest)) return;
        uint256 id = _generate(player, member, rarity, scoreBP, recoveryBP, skill);
        minted[actionId] = id;
        emit CardGenerated(actionId, player, id);
    }

    function _generate(
        address player,
        uint256 member,
        uint256 rarity,
        uint256 scoreBP,
        uint256 recoveryBP,
        uint256 skill
    ) internal virtual returns (uint256 id) {
        require(player != address(0) && member < 5 && rarity <= 5 && skill <= 6, "invalid card");
        uint256[6] memory lo = [uint256(1), 2, 3, 5, 7, 7];
        uint256[6] memory hi = [uint256(2), 3, 5, 7, 10, 10];
        require(
            scoreBP % 100 == 0 && scoreBP >= lo[rarity] * 100 && scoreBP <= hi[rarity] * 100 && recoveryBP >= lo[rarity]
                && recoveryBP <= hi[rarity],
            "invalid stats"
        );
        require((rarity != 5 || skill > 0) && (rarity != 0 || skill == 0), "invalid skill");
        id = items.nextTokenIdToMint();
        for (uint256 i; i < 3; i++) {
            require(id != materialIds[i] && items.totalSupply(materialIds[i]) > 0, "materials not configured");
        }
        require(id > 0 && cards[id].level == 0, "invalid token id");
        cards[id] = Card(member, rarity, scoreBP, recoveryBP, skill, 0, 1, 1, 0, 1, false);
        ids.push(id);
        items.mintTo(player, type(uint256).max, _metadata(id), 1);
        require(items.balanceOf(player, id) == 1 && items.totalSupply(id) == 1, "invalid mint");
    }

    function refine(bytes32 actionId, address player, uint256 id, uint256 materialId, uint256 roll, uint256 revision)
        external
        onlyOperator
        nonReentrant
    {
        bytes32 digest = keccak256(abi.encode(uint256(3), player, id, materialId, roll, revision));
        if (_retry(actionId, digest)) return;
        _owned(player, id);
        Card storage c = cards[id];
        require(
            c.revision == revision && c.level < 100 && roll < 10000 && flags(player, id) & 12 == 0, "card unavailable"
        );
        uint256 xpGrant;
        if (materialId == materialIds[0]) xpGrant = 100;
        else if (materialId == materialIds[1]) xpGrant = 225;
        else if (materialId == materialIds[2]) xpGrant = 450;
        else revert("invalid material");
        items.burn(player, materialId, 1);
        c.xp = _min(1000000, c.xp + xpGrant);
        uint256 cost = 20 + (c.level - 1) * 5;
        uint256 result;
        if (c.xp >= cost) {
            result = 1;
            if (roll < levelChance(c.level)) {
                c.xp -= cost;
                c.level++;
                result = 2;
            }
        }
        c.revision++;
        _sync(id);
        emit CardAction(actionId, player, id, 3, result);
    }

    function levelChance(uint256 level) public pure returns (uint256) {
        if (level < 1 || level >= 100) return 0;
        uint256[10] memory rates = [uint256(10000), 9000, 8000, 7000, 6000, 5000, 4000, 3000, 2500, 2000];
        return rates[level / 10];
    }

    function starCost(uint256 stars) public pure returns (uint256) {
        return stars >= 1 && stars < 5 ? stars * 2 : 0;
    }

    function starUpgrade(bytes32 actionId, address player, uint256 id, uint256[] calldata donors, uint256 revision)
        external
        onlyOperator
        nonReentrant
    {
        bytes32 digest = keccak256(abi.encode(uint256(4), player, id, donors, revision));
        if (_retry(actionId, digest)) return;
        require(donors.length > 0 && donors.length <= 32, "invalid donors");
        _owned(player, id);
        Card storage c = cards[id];
        require(c.revision == revision && flags(player, id) & 12 == 0, "card unavailable");
        for (uint256 i; i < donors.length; i++) {
            uint256 donor = donors[i];
            require(donor != id, "self sacrifice");
            _owned(player, donor);
            require(flags(player, donor) == 0, "protected donor");
            Card storage d = cards[donor];
            require(c.rarity == d.rarity || c.rarity >= 4 && d.rarity >= 4, "rarity mismatch");
            // Each donor is ONE, regardless of its XP, level, stars or progress.
            d.burned = true;
            d.revision++;
            items.burn(player, donor, 1);
            _sync(donor);
        }
        uint256 progress = c.progress + donors.length;
        while (c.stars < 5 && progress >= starCost(c.stars)) {
            progress -= starCost(c.stars);
            c.stars++;
        }
        uint256 wasted = c.stars == 5 ? progress : 0;
        c.progress = c.stars == 5 ? 0 : progress;
        c.revision++;
        _sync(id);
        emit CardAction(actionId, player, id, 4, wasted);
    }

    function protect(bytes32 actionId, address player, uint256 id, bool value, uint256 revision)
        external
        onlyOperator
        nonReentrant
    {
        if (_retry(actionId, keccak256(abi.encode(uint256(5), player, id, value, revision)))) return;
        _owned(player, id);
        Card storage c = cards[id];
        require(c.revision == revision, "card changed");
        locked[player][id] = value;
        c.revision++;
        _sync(id);
        emit CardAction(actionId, player, id, 5, value ? 1 : 0);
    }

    function deck(address player, uint256 setId) external view returns (uint256[5] memory result) {
        for (uint256 member; member < 5; member++) {
            uint256 id = decks[player][setId][member];
            if (id > 0 && !cards[id].burned && items.balanceOf(player, id) == 1 && items.totalSupply(id) == 1) {
                result[member] = id;
            }
        }
    }

    function equip(bytes32 actionId, address player, uint256 setId, uint256 member, uint256 id)
        external
        onlyOperator
        nonReentrant
    {
        if (_retry(actionId, keccak256(abi.encode(uint256(6), player, setId, member, id)))) return;
        require(_validSet(setId) && member < 5, "invalid deck");
        if (id > 0) {
            _owned(player, id);
            require(_setForCard(id) == setId && cards[id].member == member && flags(player, id) & 12 == 0, "card unavailable");
        }
        decks[player][setId][member] = id;
        emit CardAction(actionId, player, id, 6, member);
    }

    /// @notice Hooks for server-authoritative sale/run protection.
    function setListed(address player, uint256 id, bool value) external onlyOperator {
        _owned(player, id);
        listed[player][id] = value;
    }

    function setInUse(address player, uint256 id, uint256 until) external onlyOperator {
        _owned(player, id);
        require(until <= block.timestamp + 2 hours, "invalid lease");
        inUseUntil[player][id] = until;
    }

    function _owned(address player, uint256 id) internal view {
        require(
            cards[id].level > 0 && !cards[id].burned && items.balanceOf(player, id) == 1 && items.totalSupply(id) == 1,
            "card not owned"
        );
    }

    function _retry(bytes32 id, bytes32 digest) internal returns (bool) {
        require(id != bytes32(0), "invalid action");
        if (actions[id] != bytes32(0)) {
            require(actions[id] == digest, "action mismatch");
            return true;
        }
        actions[id] = digest;
        return false;
    }

    function _sync(uint256 id) internal {
        items.setTokenURI(id, _metadata(id));
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _metadata(uint256 id) internal view returns (string memory) {
        Card memory c = cards[id];
        string[5] memory names = ["Woni", "Liv", "Minami", "May", "Zena"];
        string[5] memory files = ["woni", "liv", "minami", "may", "zena"];
        string[6] memory rarities = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "LE"];
        string[7] memory skills = ["None", "Overture", "Spotlight", "Second Wind", "Encore", "Resonance", "Overdrive"];
        string memory attrs = string.concat(
            _text("Member", names[c.member]),
            ",",
            _text("Rarity", rarities[c.rarity]),
            ",",
            _text("Skill", skills[c.skill]),
            ",",
            _number("Level", c.level),
            ",",
            _number("XP", c.xp),
            ",",
            _number("Stars", c.stars),
            ",",
            _number("Star progress", c.progress)
        );
        attrs = string.concat(
            attrs,
            ",",
            _number("Base Perfect Score BP", c.scoreBP),
            ",",
            _number("Base Perfect Recovery BP", c.recoveryBP),
            ",",
            _number("Perfect Score BP", c.scoreBP * (10000 + (c.level - 1) * 2000 / 99) / 10000),
            ",",
            _number("Perfect Recovery PPM", c.recoveryBP * 100 * (10000 + (c.level - 1) * 2000 / 99) / 10000),
            ",",
            _number("Revision", c.revision),
            ",",
            _text("Status", c.burned ? "Sacrificed" : "Active")
        );
        return string.concat(
            "data:application/json;base64,",
            Base64.encode(
                bytes(
                    string.concat(
                        '{"name":"',
                        names[c.member],
                        string.concat(" - ", _seriesName(id), " #"),
                        _decimal(id),
                        '","description":"Individual RESCENE Rhythm member card. Refinement-only XP. Each sacrificed card counts as one donor. Trusted-server random traits. Skill rules v2.","image":"',
                        _imageURL(id, files[c.member]),
                        '","attributes":[',
                        attrs,
                        "]}"
                    )
                )
            )
        );
    }

    // Hooks preserve the PULSE v2 ABI and behavior while allowing a release-aware registry.
    function _setForCard(uint256) internal view virtual returns (uint256) { return 1; }
    function _validSet(uint256 setId) internal view virtual returns (bool) { return setId == 1; }
    function _validPurchaseMember(uint256 member) internal view virtual returns (bool) { return member < 5; }
    function _canOpenSales() internal view virtual returns (bool) { return true; }
    function _seriesName(uint256) internal view virtual returns (string memory) { return "PULSE"; }
    function _imageURL(uint256, string memory member) internal view virtual returns (string memory) {
        return string.concat("https://engine.fluentxverse.com/items/pulse-le/", member, ".png");
    }

    function _decimal(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 copy = value;
        uint256 digits;
        while (copy > 0) {
            digits++;
            copy /= 10;
        }
        bytes memory out = new bytes(digits);
        while (value > 0) {
            out[--digits] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }
        return string(out);
    }

    function _text(string memory key, string memory value) internal pure returns (string memory) {
        return string.concat('{"trait_type":"', key, '","value":"', value, '"}');
    }

    function _number(string memory key, uint256 value) internal pure returns (string memory) {
        return string.concat('{"trait_type":"', key, '","value":', _decimal(value), "}");
    }
}

/// @notice Launch binding for the existing three refinement token IDs.
contract PulseCardsLaunch is PulseCards {
    constructor(address op, address erc20, address erc1155)
        PulseCards(op, erc20, erc1155, [uint256(11), 12, 13]) {}
}
