// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ResceneLeaderboard} from "../src/ResceneLeaderboard.sol";

contract ResceneLeaderboardTest is Test {
    ResceneLeaderboard internal leaderboard;
    address internal admin = makeAddr("admin");
    address internal publisher = makeAddr("publisher");
    address internal stranger = makeAddr("stranger");
    bytes32 internal board;
    uint64 internal constant TIME = 1_800_000_000_000;

    function setUp() public {
        vm.warp(TIME / 1000);
        leaderboard = new ResceneLeaderboard(admin, publisher, 2 days);
        vm.prank(admin);
        board = leaderboard.registerBoard("love-attack", 2, keccak256("revision-one"), 680);
    }

    function entry(uint128 player, uint128 run, uint32 score, uint32 combo, uint64 at)
        internal
        pure
        returns (ResceneLeaderboard.Entry memory)
    {
        return ResceneLeaderboard.Entry(bytes16(player), bytes16(run), score, combo, at);
    }

    function submit(bytes32 boardId, ResceneLeaderboard.Entry memory value) internal {
        vm.prank(publisher);
        leaderboard.submitScore(boardId, value);
    }

    function assertBest(bytes32 boardId, uint128 player, uint128 run, uint32 score, uint32 combo, uint64 at)
        internal
        view
    {
        (bytes16 id, bytes16 actualRun, uint32 actualScore, uint32 actualCombo, uint64 actualTime) =
            leaderboard.personalBests(boardId, bytes16(player));
        assertEq(id, bytes16(player));
        assertEq(actualRun, bytes16(run));
        assertEq(actualScore, score);
        assertEq(actualCombo, combo);
        assertEq(actualTime, at);
    }

    function testStoresBestAndPreservesExactTie() public {
        submit(board, entry(1, 1, 800_000, 90, TIME - 20));
        submit(board, entry(1, 2, 799_999, 100, TIME - 10));
        submit(board, entry(1, 3, 800_000, 90, TIME));
        assertBest(board, 1, 1, 800_000, 90, TIME - 20);
        submit(board, entry(1, 4, 800_000, 91, TIME));
        assertBest(board, 1, 4, 800_000, 91, TIME);
        submit(board, entry(1, 5, 800_001, 1, TIME));
        assertBest(board, 1, 5, 800_001, 1, TIME);
        (, uint64 players,) = leaderboard.boards(board);
        assertEq(players, 1);
        assertEq(leaderboard.getTop(board).length, 1);
        assertTrue(leaderboard.processedRuns(bytes16(uint128(1)), bytes16(uint128(2))));
    }

    function testFullTieBreakOrderIndependentOfPublicationOrder() public {
        submit(board, entry(4, 1, 900_000, 100, TIME));
        submit(board, entry(3, 1, 900_000, 100, TIME - 1));
        submit(board, entry(2, 1, 900_000, 100, TIME - 1));
        submit(board, entry(1, 1, 900_000, 101, TIME));
        submit(board, entry(5, 1, 900_001, 1, TIME));
        uint128[5] memory expected = [uint128(5), 1, 2, 3, 4];
        ResceneLeaderboard.Entry[] memory top = leaderboard.getTop(board);
        for (uint256 i; i < expected.length; ++i) {
            assertEq(top[i].playerId, bytes16(expected[i]));
            assertEq(leaderboard.topRank(board, top[i].playerId), i + 1);
        }
    }

    function testTopIsBoundedAndEvictedPlayersCanReturn() public {
        for (uint128 i = 1; i <= 30; ++i) {
            submit(board, entry(i, 1, 500_000 + uint32(i), 10, TIME));
        }
        ResceneLeaderboard.Entry[] memory top = leaderboard.getTop(board);
        assertEq(top.length, 25);
        assertEq(top[0].playerId, bytes16(uint128(30)));
        assertEq(top[24].playerId, bytes16(uint128(6)));
        assertEq(leaderboard.topRank(board, bytes16(uint128(1))), 0);
        assertBest(board, 1, 1, 500_001, 10, TIME);
        submit(board, entry(1, 2, 1_000_000, 680, TIME));
        assertEq(leaderboard.topRank(board, bytes16(uint128(1))), 1);
        assertEq(leaderboard.topRank(board, bytes16(uint128(6))), 0);
        // Existing leaders must move without duplicating or shrinking the Top 25.
        submit(board, entry(20, 2, 999_999, 10, TIME));
        assertEq(leaderboard.topRank(board, bytes16(uint128(20))), 2);
        assertEq(leaderboard.getTop(board).length, 25);
        (, uint64 players,) = leaderboard.boards(board);
        assertEq(players, 30);
    }

    function testDuplicateRunRejectedAcrossBoardsButScopedToPlayer() public {
        vm.prank(admin);
        bytes32 another = leaderboard.registerBoard("love-attack", 2, keccak256("revision-two"), 680);
        submit(board, entry(1, 1, 800_000, 50, TIME));
        vm.expectRevert(ResceneLeaderboard.RunAlreadyProcessed.selector);
        submit(board, entry(1, 1, 900_000, 60, TIME));
        vm.expectRevert(ResceneLeaderboard.RunAlreadyProcessed.selector);
        submit(another, entry(1, 1, 900_000, 60, TIME));
        submit(another, entry(1, 2, 500_000, 10, TIME));
        submit(board, entry(2, 1, 700_000, 40, TIME));
        assertBest(board, 1, 1, 800_000, 50, TIME);
        assertBest(another, 1, 2, 500_000, 10, TIME);
    }

    function testNonImprovingRunIsAlsoConsumed() public {
        submit(board, entry(1, 1, 800_000, 50, TIME));
        submit(board, entry(1, 2, 700_000, 50, TIME));
        vm.expectRevert(ResceneLeaderboard.RunAlreadyProcessed.selector);
        submit(board, entry(1, 2, 900_000, 50, TIME));
    }

    function testPublicationEventsIncludeNonImprovements() public {
        vm.expectEmit(true, true, true, true, address(leaderboard));
        emit ResceneLeaderboard.ScoreProcessed(board, bytes16(uint128(1)), bytes16(uint128(1)), 800_000, 50, TIME, true);
        submit(board, entry(1, 1, 800_000, 50, TIME));
        vm.expectEmit(true, true, true, true, address(leaderboard));
        emit ResceneLeaderboard.ScoreProcessed(
            board, bytes16(uint128(1)), bytes16(uint128(2)), 700_000, 50, TIME, false
        );
        submit(board, entry(1, 2, 700_000, 50, TIME));
    }

    function testTimestampsRetainMillisecondsWithinBlockSecond() public {
        submit(board, entry(1, 1, 800_000, 50, TIME + 999));
        assertBest(board, 1, 1, 800_000, 50, TIME + 999);
    }

    function testInvalidEntriesDoNotConsumeRun() public {
        ResceneLeaderboard.Entry memory value = entry(1, 1, 800_000, 50, TIME);
        for (uint256 i; i < 8; ++i) {
            ResceneLeaderboard.Entry memory bad = entry(1, 1, 800_000, 50, TIME);
            if (i == 0) bad.playerId = bytes16(0);
            if (i == 1) bad.runId = bytes16(0);
            if (i == 2) bad.score = 499_999;
            if (i == 3) bad.score = 1_000_001;
            if (i == 4) bad.maxCombo = 681;
            if (i == 5) bad.achievedAt = 0;
            if (i == 6) bad.achievedAt = TIME + 1000;
            if (i == 7) bad.maxCombo = 0;
            vm.expectRevert(ResceneLeaderboard.InvalidEntry.selector);
            submit(board, bad);
        }
        assertFalse(leaderboard.processedRuns(value.playerId, value.runId));
        submit(board, value);
    }

    function testRevisionDifficultyAndSongAreIsolated() public {
        bytes32[3] memory others;
        vm.startPrank(admin);
        others[0] = leaderboard.registerBoard("love-attack", 2, keccak256("revision-two"), 680);
        others[1] = leaderboard.registerBoard("love-attack", 3, keccak256("revision-one"), 800);
        others[2] = leaderboard.registerBoard("pinball", 2, keccak256("revision-one"), 500);
        vm.stopPrank();
        submit(board, entry(1, 1, 1_000_000, 680, TIME));
        for (uint128 i; i < others.length; ++i) {
            assertEq(leaderboard.getTop(others[i]).length, 0);
            submit(others[i], entry(1, i + 2, 500_000, 10, TIME));
            assertEq(leaderboard.getTop(others[i])[0].score, 500_000);
        }
        assertEq(leaderboard.getTop(board)[0].score, 1_000_000);
    }

    function testRegistrationIsImmutableAndValidatesMetadata() public {
        vm.startPrank(admin);
        vm.expectRevert(ResceneLeaderboard.BoardAlreadyExists.selector);
        leaderboard.registerBoard("love-attack", 2, keccak256("revision-one"), 1);
        vm.expectRevert(ResceneLeaderboard.InvalidChart.selector);
        leaderboard.registerBoard("", 0, keccak256("r"), 100);
        vm.expectRevert(ResceneLeaderboard.InvalidChart.selector);
        leaderboard.registerBoard("song", 4, keccak256("r"), 100);
        vm.expectRevert(ResceneLeaderboard.InvalidChart.selector);
        leaderboard.registerBoard("song", 0, bytes32(0), 100);
        vm.expectRevert(ResceneLeaderboard.InvalidChart.selector);
        leaderboard.registerBoard("song", 0, keccak256("r"), 0);
        vm.expectRevert(ResceneLeaderboard.InvalidChart.selector);
        leaderboard.registerBoard(string(new bytes(129)), 0, keccak256("r"), 1);
        vm.stopPrank();
    }

    function testDisableAndPausePreserveReadsAndAllowRetry() public {
        submit(board, entry(1, 1, 800_000, 10, TIME));
        vm.prank(admin);
        leaderboard.setBoardEnabled(board, false);
        vm.expectRevert(ResceneLeaderboard.BoardUnavailable.selector);
        submit(board, entry(2, 1, 800_000, 10, TIME));
        assertEq(leaderboard.getTop(board).length, 1);
        vm.prank(admin);
        leaderboard.setBoardEnabled(board, true);
        vm.prank(admin);
        leaderboard.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        submit(board, entry(2, 1, 800_000, 10, TIME));
        assertEq(leaderboard.getTop(board).length, 1);
        vm.prank(admin);
        leaderboard.unpause();
        submit(board, entry(2, 1, 800_000, 10, TIME));
        assertEq(leaderboard.getTop(board).length, 2);
    }

    function unauthorized(address caller, bytes32 role) internal {
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, role));
        vm.prank(caller);
    }

    function testRolesAndPublisherRotation() public {
        unauthorized(stranger, keccak256("PUBLISHER_ROLE"));
        leaderboard.submitScore(board, entry(1, 1, 800_000, 10, TIME));
        unauthorized(publisher, keccak256("CHART_ADMIN_ROLE"));
        leaderboard.registerBoard("song", 0, keccak256("r"), 10);
        unauthorized(publisher, keccak256("PAUSER_ROLE"));
        leaderboard.pause();
        unauthorized(publisher, bytes32(0));
        leaderboard.grantRole(keccak256("PUBLISHER_ROLE"), stranger);
        vm.startPrank(admin);
        leaderboard.grantRole(keccak256("PUBLISHER_ROLE"), stranger);
        leaderboard.revokeRole(keccak256("PUBLISHER_ROLE"), publisher);
        vm.stopPrank();
        unauthorized(publisher, keccak256("PUBLISHER_ROLE"));
        leaderboard.submitScore(board, entry(1, 1, 800_000, 10, TIME));
        vm.prank(stranger);
        leaderboard.submitScore(board, entry(1, 1, 800_000, 10, TIME));
    }

    function testEmergencyPauserCannotUnpauseOrPublish() public {
        vm.prank(admin);
        leaderboard.grantRole(keccak256("PAUSER_ROLE"), stranger);
        vm.prank(stranger);
        leaderboard.pause();
        unauthorized(stranger, bytes32(0));
        leaderboard.unpause();
        assertTrue(leaderboard.paused());
    }

    function testDefaultAdminTransferRequiresDelayAndAcceptance() public {
        vm.prank(admin);
        leaderboard.beginDefaultAdminTransfer(stranger);
        vm.prank(stranger);
        vm.expectRevert();
        leaderboard.acceptDefaultAdminTransfer();
        vm.warp(block.timestamp + 2 days + 1);
        vm.prank(stranger);
        leaderboard.acceptDefaultAdminTransfer();
        assertEq(leaderboard.defaultAdmin(), stranger);
        // Operational roles are separate: the new admin can explicitly rotate them.
        unauthorized(admin, bytes32(0));
        leaderboard.grantRole(keccak256("PUBLISHER_ROLE"), admin);
    }

    function testUnknownBoardAndEmptyReads() public {
        bytes32 unknown = keccak256("unknown");
        assertEq(leaderboard.getTop(unknown).length, 0);
        assertEq(leaderboard.topRank(unknown, bytes16(uint128(1))), 0);
        vm.expectRevert(ResceneLeaderboard.BoardUnavailable.selector);
        submit(unknown, entry(1, 1, 800_000, 10, TIME));
        vm.prank(admin);
        vm.expectRevert(ResceneLeaderboard.BoardUnavailable.selector);
        leaderboard.setBoardEnabled(unknown, false);
    }

    function testConstructorRejectsZeroPublisher() public {
        vm.expectRevert(ResceneLeaderboard.InvalidPublisher.selector);
        new ResceneLeaderboard(admin, address(0), 2 days);
    }

    // Independent model: retain every best, then sort ALL players in memory.
    // This exercises replacements, non-improvements, ties and Top 25 eviction.
    function testFuzzTopMatchesFullSort(uint256 seed) public {
        ResceneLeaderboard.Entry[] memory bests = new ResceneLeaderboard.Entry[](40);
        uint256 players;
        for (uint128 i = 1; i <= 100; ++i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint128 player = uint128(seed % 40) + 1;
            ResceneLeaderboard.Entry memory value = entry(
                player,
                i,
                500_000 + uint32((seed >> 32) % 5) * 100_000,
                1 + uint32((seed >> 64) % 5),
                TIME - uint64((seed >> 96) % 5)
            );
            submit(board, value);
            ResceneLeaderboard.Entry memory old = bests[player - 1];
            if (old.playerId == bytes16(0)) ++players;
            if (
                old.playerId == bytes16(0) || value.score > old.score
                    || (value.score == old.score && value.maxCombo > old.maxCombo)
            ) {
                bests[player - 1] = value;
            }
        }
        for (uint256 i; i < bests.length; ++i) {
            for (uint256 j = i + 1; j < bests.length; ++j) {
                if (ahead(bests[j], bests[i])) (bests[i], bests[j]) = (bests[j], bests[i]);
            }
        }
        ResceneLeaderboard.Entry[] memory top = leaderboard.getTop(board);
        assertEq(top.length, players < 25 ? players : 25);
        for (uint256 i; i < top.length; ++i) {
            assertEq(abi.encode(top[i]), abi.encode(bests[i]));
            assertEq(leaderboard.topRank(board, top[i].playerId), i + 1);
        }
        (, uint64 actualPlayers,) = leaderboard.boards(board);
        assertEq(actualPlayers, players);
    }

    function ahead(ResceneLeaderboard.Entry memory a, ResceneLeaderboard.Entry memory b) internal pure returns (bool) {
        if (a.playerId == bytes16(0)) return false;
        if (b.playerId == bytes16(0)) return true;
        if (a.score != b.score) return a.score > b.score;
        if (a.maxCombo != b.maxCombo) return a.maxCombo > b.maxCombo;
        if (a.achievedAt != b.achievedAt) return a.achievedAt < b.achievedAt;
        return a.playerId < b.playerId;
    }
}
