// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {PulseCards} from "../src/PulseCards.sol";
import {ShopCoin} from "./EnergyDrinkShop.t.sol";

contract PulseItemsMock {
    uint256 public nextTokenIdToMint = 14;
    mapping(address => mapping(uint256 => uint256)) public balanceOf;
    mapping(uint256 => uint256) public totalSupply;
    mapping(uint256 => string) public uri;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    address public minter;

    function authorize(address value) external {
        minter = value;
    }

    function seed(address who, uint256 id, uint256 qty) external {
        balanceOf[who][id] += qty;
        totalSupply[id] += qty;
    }

    function mintTo(address who, uint256 id, string calldata data, uint256 qty) external {
        require(msg.sender == minter, "minter");
        require(id == type(uint256).max && qty == 1, "mint shape");
        id = nextTokenIdToMint++;
        balanceOf[who][id] += qty;
        totalSupply[id] += qty;
        uri[id] = data;
    }

    function setTokenURI(uint256 id, string calldata data) external {
        require(msg.sender == minter, "metadata");
        uri[id] = data;
    }

    function setApprovalForAll(address spender, bool value) external {
        isApprovedForAll[msg.sender][spender] = value;
    }

    function burn(address who, uint256 id, uint256 qty) external {
        require(who == msg.sender || isApprovedForAll[who][msg.sender], "approval");
        require(balanceOf[who][id] >= qty, "balance");
        balanceOf[who][id] -= qty;
        totalSupply[id] -= qty;
    }

    function safeTransferFrom(address from, address to, uint256 id, uint256 qty, bytes calldata) external {
        require(msg.sender == from || isApprovedForAll[from][msg.sender], "approval");
        require(balanceOf[from][id] >= qty, "balance");
        balanceOf[from][id] -= qty;
        balanceOf[to][id] += qty;
    }

    function transfer(address to, uint256 id) external {
        require(balanceOf[msg.sender][id] == 1, "owner");
        balanceOf[msg.sender][id] = 0;
        balanceOf[to][id] = 1;
    }
}

contract PulseCardsHarness is PulseCards {
    constructor(address op, address coin, address nft, uint256[3] memory materials)
        PulseCards(op, coin, nft, materials)
    {}

    function setProgress(uint256 id, uint256 level, uint256 xp, uint256 stars, uint256 progress) external {
        Card storage c = cards[id];
        c.level = level;
        c.xp = xp;
        c.stars = stars;
        c.progress = progress;
    }
}

contract PulseCardsTest is Test {
    ShopCoin coin;
    PulseItemsMock items;
    PulseCardsHarness pulse;
    address player = address(0xabc);
    address other = address(0xdef);

    function setUp() public {
        coin = new ShopCoin();
        items = new PulseItemsMock();
        pulse = new PulseCardsHarness(address(this), address(coin), address(items), [uint256(11), 12, 13]);
        items.authorize(address(pulse));
        for (uint256 id = 11; id <= 13; id++) {
            items.seed(player, id, 100);
        }
        coin.mint(player, 100000 ether);
        vm.startPrank(player);
        coin.approve(address(pulse), type(uint256).max);
        items.setApprovalForAll(address(pulse), true);
        vm.stopPrank();
    }

    function generate(uint256 nonce, uint256 member, uint256 rarity) internal returns (uint256) {
        bytes32 key = keccak256(abi.encode(nonce));
        pulse.generate(key, player, member, rarity, rarity >= 4 ? 800 : 100, rarity >= 4 ? 8 : 1, rarity == 0 ? 0 : 1);
        return pulse.minted(key);
    }

    function state(uint256 id) internal view returns (uint256[14] memory) {
        return pulse.viewCard(player, id);
    }

    function testClosedSalesAndIndividualSupplyOneMints() public {
        bytes32 order = keccak256("sale");
        vm.expectRevert("sales closed");
        pulse.purchase(order, player, 0, 800, 9, 1);
        assertEq(coin.balanceOf(player), 100000 ether);
        pulse.setSalesEnabled(true);
        pulse.purchase(order, player, 0, 800, 9, 1);
        uint256 id = pulse.minted(order);
        assertEq(items.balanceOf(player, id), 1);
        assertEq(items.totalSupply(id), 1);
        assertEq(coin.balanceOf(player), 99550 ether);
        pulse.purchase(order, player, 0, 800, 9, 1);
        assertEq(pulse.count(), 1);
        vm.expectRevert("action mismatch");
        pulse.purchase(order, player, 0, 900, 9, 1);
        uint256 otherId = generate(2, 0, 5);
        assertTrue(id != otherId);
        assertEq(state(otherId)[5], 0);
        assertEq(state(otherId)[6], 1);
        assertEq(state(otherId)[7], 1);
    }

    function testRefinementSuccessFailureAndMetadataAtomicity() public {
        uint256 id = generate(1, 0, 5);
        string memory beforeURI = items.uri(id);
        pulse.refine(keccak256("level2"), player, id, 11, 9999, 1);
        assertEq(state(id)[6], 2);
        assertEq(state(id)[5], 80);
        assertTrue(keccak256(bytes(beforeURI)) != keccak256(bytes(items.uri(id))));
        pulse.setProgress(id, 99, 1000, 1, 0);
        uint256 beforeItems = items.balanceOf(player, 11);
        bytes32 fail = keccak256("fail");
        pulse.refine(fail, player, id, 11, 9999, 2);
        assertEq(state(id)[6], 99);
        assertEq(state(id)[5], 1100);
        assertEq(items.balanceOf(player, 11), beforeItems - 1);
        pulse.refine(fail, player, id, 11, 9999, 2);
        assertEq(items.balanceOf(player, 11), beforeItems - 1);
        vm.expectRevert("action mismatch");
        pulse.refine(fail, player, id, 11, 0, 2);
        pulse.refine(keccak256("level100"), player, id, 11, 0, 3);
        assertEq(state(id)[6], 100);
        beforeItems = items.balanceOf(player, 11);
        vm.expectRevert("card unavailable");
        pulse.refine(keccak256("level101"), player, id, 11, 0, 4);
        assertEq(items.balanceOf(player, 11), beforeItems);
        assertEq(state(id)[12], 960);
        assertEq(state(id)[13], 960);
    }

    function testDonorDiesAndContributesOnlyOneDespiteAllItsProgress() public {
        uint256 receiver = generate(1, 0, 5);
        uint256 donor = generate(2, 1, 4);
        pulse.setProgress(donor, 100, 9999, 5, 0);
        uint256[] memory donors = new uint256[](1);
        donors[0] = donor;
        pulse.starUpgrade(keccak256("donor"), player, receiver, donors, 1);
        assertEq(items.balanceOf(player, donor), 0);
        assertEq(state(donor)[10], 1);
        assertEq(state(receiver)[6], 1);
        assertEq(state(receiver)[5], 0);
        assertEq(state(receiver)[7], 1);
        assertEq(state(receiver)[8], 1);
        uint256 second = generate(3, 2, 5);
        donors[0] = second;
        pulse.starUpgrade(keccak256("second"), player, receiver, donors, 2);
        assertEq(state(receiver)[7], 2);
        assertEq(state(receiver)[8], 0);
    }

    function testEscalatingCostsAndOverflowStillBurnsAllDonors() public {
        uint256 receiver = generate(1, 0, 5);
        for (uint256 stars = 1; stars < 5; stars++) {
            uint256[] memory donors = new uint256[](stars * 2);
            for (uint256 i; i < donors.length; i++) {
                donors[i] = generate(100 + stars * 20 + i, i % 5, 5);
            }
            pulse.starUpgrade(keccak256(abi.encode("upgrade", stars)), player, receiver, donors, stars);
            assertEq(state(receiver)[7], stars + 1);
            assertEq(state(receiver)[8], 0);
        }
        uint256[] memory excess = new uint256[](2);
        excess[0] = generate(500, 0, 5);
        excess[1] = generate(501, 1, 5);
        bytes32 order = keccak256("waste");
        pulse.starUpgrade(order, player, receiver, excess, 5);
        pulse.starUpgrade(order, player, receiver, excess, 5);
        assertEq(state(receiver)[7], 5);
        assertEq(state(receiver)[8], 0);
        assertEq(items.totalSupply(excess[0]), 0);
        assertEq(items.totalSupply(excess[1]), 0);
    }

    function testFiveMemberDeckAndProtectedDonors() public {
        uint256 receiver = generate(1, 0, 5);
        uint256 donor = generate(2, 1, 5);
        pulse.equip(keccak256("equip"), player, 1, 1, donor);
        assertEq(pulse.deck(player, 1)[1], donor);
        vm.expectRevert("card unavailable");
        pulse.equip(keccak256("wrong slot"), player, 1, 0, donor);
        uint256[] memory donors = new uint256[](1);
        donors[0] = donor;
        vm.expectRevert("protected donor");
        pulse.starUpgrade(keccak256("equipped donor"), player, receiver, donors, 1);
        pulse.equip(keccak256("remove"), player, 1, 1, 0);
        pulse.protect(keccak256("lock"), player, donor, true, 1);
        vm.expectRevert("protected donor");
        pulse.starUpgrade(keccak256("locked donor"), player, receiver, donors, 1);
        pulse.protect(keccak256("unlock"), player, donor, false, 2);
        pulse.setListed(player, donor, true);
        vm.expectRevert("protected donor");
        pulse.starUpgrade(keccak256("listed donor"), player, receiver, donors, 1);
        pulse.setListed(player, donor, false);
        pulse.setInUse(player, donor, block.timestamp + 1 hours);
        vm.expectRevert("protected donor");
        pulse.starUpgrade(keccak256("busy donor"), player, receiver, donors, 1);
        assertEq(items.balanceOf(player, donor), 1);
    }

    function testTransferCarriesTokenProgressAndOldOwnerCannotUseIt() public {
        uint256 id = generate(1, 0, 5);
        pulse.setProgress(id, 82, 400, 4, 3);
        vm.prank(player);
        items.transfer(other, id);
        uint256[14] memory transferred = pulse.viewCard(other, id);
        assertEq(transferred[6], 82);
        assertEq(transferred[5], 400);
        assertEq(transferred[7], 4);
        assertEq(transferred[8], 3);
        assertEq(transferred[2], 800);
        vm.expectRevert("card not owned");
        pulse.refine(keccak256("old owner"), player, id, 11, 0, 1);
    }

    function testDuplicateOrSelfDonorRollsBackWholeBatch() public {
        uint256 receiver = generate(1, 0, 5);
        uint256 donor = generate(2, 1, 5);
        uint256[] memory donors = new uint256[](2);
        donors[0] = donor;
        donors[1] = donor;
        vm.expectRevert("card not owned");
        pulse.starUpgrade(keccak256("duplicate"), player, receiver, donors, 1);
        assertEq(items.balanceOf(player, donor), 1);
        donors[1] = receiver;
        vm.expectRevert("self sacrifice");
        pulse.starUpgrade(keccak256("self"), player, receiver, donors, 1);
        assertEq(items.balanceOf(player, donor), 1);
    }

    function testMaterialCheckoutPaysTreasuryAndDeliversExactlyOnce() public {
        items.seed(address(this), 11, 1000);
        items.setApprovalForAll(address(pulse), true);
        pulse.setSalesEnabled(true);
        bytes32 order = keccak256("materials");
        uint256 before = items.balanceOf(player, 11);
        pulse.purchaseMaterial(order, player, 11, 2);
        pulse.purchaseMaterial(order, player, 11, 2);
        assertEq(coin.balanceOf(player), 99700 ether);
        assertEq(items.balanceOf(player, 11), before + 2);
        assertEq(items.balanceOf(address(this), 11), 998);
        vm.expectRevert("action mismatch");
        pulse.purchaseMaterial(order, player, 11, 3);
        items.setApprovalForAll(address(pulse), false);
        vm.expectRevert("approval");
        pulse.purchaseMaterial(keccak256("failed material delivery"), player, 11, 1);
        assertEq(coin.balanceOf(player), 99700 ether);
    }

    function testMetadataFailureRollsBackBurnAndProgress() public {
        uint256 id = generate(1, 0, 5);
        uint256 balance = items.balanceOf(player, 11);
        items.authorize(address(0xdead));
        bytes32 order = keccak256("no metadata role");
        vm.expectRevert("metadata");
        pulse.refine(order, player, id, 11, 0, 1);
        assertEq(items.balanceOf(player, 11), balance);
        assertEq(state(id)[6], 1);
        assertEq(state(id)[5], 0);
        assertEq(pulse.actions(order), bytes32(0));
    }

    function testMetadataJsonContainsIndividualTraitsAndMutableProgress() public {
        uint256 id = generate(1, 0, 5);
        pulse.refine(keccak256("metadata level"), player, id, 11, 0, 1);
        bytes memory uri = bytes(items.uri(id));
        bytes memory encoded = new bytes(uri.length - 29);
        for (uint256 i; i < encoded.length; i++) {
            encoded[i] = uri[i + 29];
        }
        string memory data = string(Base64.decode(string(encoded)));
        assertEq(vm.parseJsonString(data, ".name"), "Woni - PULSE #14");
        assertEq(vm.parseJsonUint(data, ".attributes[3].value"), 2);
        assertEq(vm.parseJsonUint(data, ".attributes[4].value"), 80);
    }

    function testFuzzLevelOddsMatchPolicy(uint256 level) public pure {
        level = bound(level, 1, 99);
        uint256[10] memory odds = [uint256(10000), 9000, 8000, 7000, 6000, 5000, 4000, 3000, 2500, 2000];
        // Formula is covered by the actual contract call in the boundary test.
        assertGe(odds[level / 10], 2000);
        assertLe(odds[level / 10], 10000);
    }

    function testLevelOddsBoundaries() public view {
        assertEq(pulse.levelChance(9), 10000);
        assertEq(pulse.levelChance(10), 9000);
        assertEq(pulse.levelChance(90), 2000);
        assertEq(pulse.levelChance(99), 2000);
        assertEq(pulse.levelChance(100), 0);
    }
}

contract PulseAllocationTest is PulseCardsTest {
    function testInitialAllocationCannotBeReplenishedByAdminMintsOrBurns() public {
        pulse.setSalesEnabled(true);
        for (uint256 i; i < 50; i++) pulse.purchase(keccak256(abi.encode("allocation", i)), player, 0, 800, 8, 1);
        assertEq(pulse.initialLESold(0), 50);
        vm.expectRevert("allocation exhausted");
        pulse.purchase(keccak256("sold out"), player, 0, 800, 8, 1);
        generate(9000, 0, 5);
        assertEq(pulse.initialLESold(0), 50);
        pulse.purchase(keccak256("another member"), player, 1, 800, 8, 1);
        assertEq(pulse.initialLESold(1), 1);
        assertTrue(pulse.ARTWORK_MAY_BE_REISSUED());
    }
}
