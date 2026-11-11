// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title RESCENE chart leaderboards
/// @notice Stores backend-verified personal bests and a bounded, sorted Top 25.
/// @dev The publisher is trusted to verify replays, account identity and timestamps.
///      This contract enforces publication rules; it does not verify gameplay.
contract ResceneLeaderboard is AccessControlDefaultAdminRules, Pausable {
    bytes32 public constant PUBLISHER_ROLE = keccak256("PUBLISHER_ROLE");
    bytes32 public constant CHART_ADMIN_ROLE = keccak256("CHART_ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    uint256 public constant TOP_LIMIT = 25;
    uint32 public constant MIN_SCORE = 500_000;
    uint32 public constant MAX_SCORE = 1_000_000;

    struct Board {
        uint32 units;
        uint64 players;
        bool enabled;
    }

    struct Entry {
        bytes16 playerId;
        bytes16 runId;
        uint32 score;
        uint32 maxCombo;
        uint64 achievedAt; // UTC Unix milliseconds, as in the Go backend.
    }

    mapping(bytes32 boardId => Board) public boards;
    mapping(bytes32 boardId => mapping(bytes16 playerId => Entry)) public personalBests;
    mapping(bytes32 boardId => bytes16[]) private _top;
    // Run tickets are account scoped, but cannot be reused on another board.
    mapping(bytes16 playerId => mapping(bytes16 runId => bool)) public processedRuns;

    error InvalidChart();
    error BoardAlreadyExists();
    error BoardUnavailable();
    error InvalidEntry();
    error RunAlreadyProcessed();
    error InvalidPublisher();

    event BoardRegistered(bytes32 indexed boardId, string songId, uint8 difficulty, bytes32 revision, uint32 units);
    event BoardEnabled(bytes32 indexed boardId, bool enabled);
    // Emit every accepted run, even when it doesn't replace a best, for relayer reconciliation.
    event ScoreProcessed(
        bytes32 indexed boardId,
        bytes16 indexed playerId,
        bytes16 indexed runId,
        uint32 score,
        uint32 maxCombo,
        uint64 achievedAt,
        bool improved
    );

    constructor(address admin, address publisher, uint48 adminDelay) AccessControlDefaultAdminRules(adminDelay, admin) {
        if (publisher == address(0)) revert InvalidPublisher();
        _grantRole(PUBLISHER_ROLE, publisher);
        _grantRole(CHART_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    /// @param difficulty Easy=0, Normal=1, Hard=2, Ultra Hard=3.
    /// @param revision Raw 32-byte SHA-256 revision from the game's chart catalog.
    function boardKey(string memory songId, uint8 difficulty, bytes32 revision) public pure returns (bytes32) {
        return keccak256(abi.encode(songId, difficulty, revision));
    }

    /// @notice Register once. Chart changes require a new revision and a new board.
    function registerBoard(string calldata songId, uint8 difficulty, bytes32 revision, uint32 units)
        external
        onlyRole(CHART_ADMIN_ROLE)
        returns (bytes32 boardId)
    {
        if (
            bytes(songId).length == 0 || bytes(songId).length > 128 || difficulty > 3 || revision == bytes32(0)
                || units == 0
        ) {
            revert InvalidChart();
        }
        boardId = boardKey(songId, difficulty, revision);
        if (boards[boardId].units != 0) revert BoardAlreadyExists();
        boards[boardId] = Board({units: units, players: 0, enabled: true});
        emit BoardRegistered(boardId, songId, difficulty, revision, units);
    }

    /// @notice Stop writes to an old revision without deleting its history.
    function setBoardEnabled(bytes32 boardId, bool enabled) external onlyRole(CHART_ADMIN_ROLE) {
        if (boards[boardId].units == 0) revert BoardUnavailable();
        boards[boardId].enabled = enabled;
        emit BoardEnabled(boardId, enabled);
    }

    /// @notice Publish one completed, validated, unpaused online Free Play run.
    /// @dev An exact score/combo tie retains the original achievement time, matching the backend.
    ///      Failed calls do not consume the run ID; accepted non-improvements do.
    function submitScore(bytes32 boardId, Entry calldata entry) external onlyRole(PUBLISHER_ROLE) whenNotPaused {
        Board storage board = boards[boardId];
        if (!board.enabled) revert BoardUnavailable();
        if (
            entry.playerId == bytes16(0) || entry.runId == bytes16(0) || entry.score < MIN_SCORE
                || entry.score > MAX_SCORE || entry.maxCombo == 0 || entry.maxCombo > board.units
                || entry.achievedAt == 0 || uint256(entry.achievedAt) / 1000 > block.timestamp
        ) revert InvalidEntry();
        if (processedRuns[entry.playerId][entry.runId]) revert RunAlreadyProcessed();
        processedRuns[entry.playerId][entry.runId] = true;

        Entry storage prior = personalBests[boardId][entry.playerId];
        bool improved = prior.playerId == bytes16(0) || entry.score > prior.score
            || (entry.score == prior.score && entry.maxCombo > prior.maxCombo);
        if (improved) {
            if (prior.playerId == bytes16(0)) board.players++;
            personalBests[boardId][entry.playerId] = entry;
            _updateTop(boardId, entry.playerId);
        }
        emit ScoreProcessed(
            boardId, entry.playerId, entry.runId, entry.score, entry.maxCombo, entry.achievedAt, improved
        );
    }

    function getTop(bytes32 boardId) external view returns (Entry[] memory entries) {
        bytes16[] storage ids = _top[boardId];
        entries = new Entry[](ids.length);
        for (uint256 i; i < ids.length; ++i) {
            entries[i] = personalBests[boardId][ids[i]];
        }
    }

    /// @return One-based Top 25 position, or zero if outside it / not ranked.
    function topRank(bytes32 boardId, bytes16 playerId) external view returns (uint256) {
        bytes16[] storage ids = _top[boardId];
        for (uint256 i; i < ids.length; ++i) {
            if (ids[i] == playerId) return i + 1;
        }
        return 0;
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    // Unpause requires the default admin, even if a separate emergency pauser is added.
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function _updateTop(bytes32 boardId, bytes16 playerId) private {
        bytes16[] storage ids = _top[boardId];
        uint256 length = ids.length;
        // Remove an existing entry before reinserting its improved score.
        for (uint256 i; i < length; ++i) {
            if (ids[i] == playerId) {
                for (uint256 j = i; j + 1 < length; ++j) {
                    ids[j] = ids[j + 1];
                }
                ids.pop();
                --length;
                break;
            }
        }
        uint256 position = 0;
        while (position < length && !_ahead(personalBests[boardId][playerId], personalBests[boardId][ids[position]])) {
            ++position;
        }
        if (position >= TOP_LIMIT) return;
        if (length < TOP_LIMIT) ids.push(playerId);
        for (uint256 i = ids.length - 1; i > position; --i) {
            ids[i] = ids[i - 1];
        }
        ids[position] = playerId;
    }

    function _ahead(Entry storage a, Entry storage b) private view returns (bool) {
        if (a.score != b.score) return a.score > b.score;
        if (a.maxCombo != b.maxCombo) return a.maxCombo > b.maxCombo;
        if (a.achievedAt != b.achievedAt) return a.achievedAt < b.achievedAt;
        return a.playerId < b.playerId;
    }
}
