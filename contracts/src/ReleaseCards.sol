// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PulseCards} from "./PulseCards.sol";

/// @notice Nine release-specific decks. Reuses the audited game rules and ABI.
/// Purchase member = (release - 1) * 5 + member; stored members remain 0..4.
/// Existing PULSE identities and invested progression are imported unchanged.
contract ReleaseCards is PulseCards {
    PulseCards public immutable legacy;
    bool public migrationComplete;
    mapping(uint256 => uint256) private releases;
    uint256 public constant RELEASE_COUNT = 9;
    uint256 public constant RELEASE_VERSION = 1;
    event LegacyCardImported(uint256 indexed id, address indexed owner);

    constructor(address op, address erc20, address erc1155, address previous)
        PulseCards(op, erc20, erc1155, [uint256(11), 12, 13])
    {
        legacy = PulseCards(previous);
        require(legacy.operator() == op && address(legacy.items()) == erc1155 && address(legacy.token()) == erc20,
            "legacy binding mismatch");
    }

    function cardSet(uint256 id) external view returns (uint256) { return releases[id]; }

    /// @dev Closed sales and the same trusted operator prevent races with legacy writes.
    /// Deployment also drains old API operations before importing and switching routers.
    function importLegacy(uint256[] calldata tokens, address[] calldata owners) external onlyOperator nonReentrant {
        require(!migrationComplete && !salesEnabled && !legacy.salesEnabled(), "migration closed");
        require(tokens.length == owners.length && tokens.length <= 100, "invalid batch");
        for (uint256 i; i < tokens.length; i++) {
            uint256 id = tokens[i];
            address owner = owners[i];
            require(cards[id].level == 0, "already imported");
            uint256[14] memory v = legacy.viewCard(owner, id);
            require(v[6] > 0 && v[6] <= 100 && v[0] < 5, "unknown legacy card");
            require(v[10] == 1 || owner != address(0) && items.balanceOf(owner, id) == 1, "wrong legacy owner");
            cards[id] = Card(v[0],v[1],v[2],v[3],v[4],v[5],v[6],v[7],v[8],v[9],v[10] != 0);
            releases[id] = 1;
            ids.push(id);
            if (v[10] == 0) {
                locked[owner][id] = legacy.locked(owner,id);
                listed[owner][id] = legacy.listed(owner,id);
                inUseUntil[owner][id] = legacy.inUseUntil(owner,id);
                uint256[5] memory oldDeck = legacy.deck(owner,1);
                if (oldDeck[v[0]] == id) decks[owner][1][v[0]] = id;
            }
            _sync(id);
            emit LegacyCardImported(id,owner);
        }
    }

    function finishMigration() external onlyOperator {
        require(!migrationComplete && !legacy.salesEnabled() && ids.length == legacy.count(), "migration incomplete");
        for (uint256 member; member < 5; member++) initialLESold[member] = legacy.initialLESold(member);
        migrationComplete = true;
    }

    function _generate(address player,uint256 member,uint256 rarity,uint256 scoreBP,uint256 recoveryBP,uint256 skill)
        internal override returns (uint256 id)
    {
        require(migrationComplete && member < 45, "invalid release member");
        id = items.nextTokenIdToMint();
        releases[id] = member / 5 + 1;
        return super._generate(player,member % 5,rarity,scoreBP,recoveryBP,skill);
    }

    function _canOpenSales() internal view override returns (bool) { return migrationComplete; }
    function _setForCard(uint256 id) internal view override returns (uint256) { return releases[id]; }
    function _validSet(uint256 setId) internal pure override returns (bool) { return setId > 0 && setId <= 9; }
    function _validPurchaseMember(uint256 member) internal pure override returns (bool) { return member < 45; }
    function _seriesName(uint256 id) internal view override returns (string memory) {
        string[9] memory names = ["PULSE","Re:Scene","SCENEDROME","Glow Up","Dearest","lip bomb","Pretty Girl","Runaway","Busy Boy"];
        return names[releases[id]-1];
    }
    function _imageURL(uint256 id, string memory member) internal view override returns (string memory) {
        string[9] memory slugs = ["pulse","re-scene","scenedrome","glow-up","dearest","lip-bomb","pretty-girl","runaway","busy-boy"];
        return string.concat("https://rhythm.remineph.online/images/cards/v1/",slugs[releases[id]-1],"/",member,".webp");
    }
}
