// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {ResceneLeaderboard} from "../src/ResceneLeaderboard.sol";

contract RegisterCharts is Script {
    // Alphabetical property order, matching Foundry's JSON ABI encoding.
    struct Chart {
        uint8 difficulty;
        bytes32 revision;
        string songId;
        uint32 units;
    }

    function run() external {
        ResceneLeaderboard leaderboard = ResceneLeaderboard(vm.envAddress("LEADERBOARD_ADDRESS"));
        require(address(leaderboard).code.length != 0, "No leaderboard at address");
        string memory path = string.concat(vm.projectRoot(), "/charts.json");
        Chart[] memory charts = abi.decode(vm.parseJson(vm.readFile(path)), (Chart[]));
        uint256 start = vm.envOr("CHART_START", uint256(0));
        uint256 count = vm.envOr("CHART_COUNT", uint256(16));
        require(start < charts.length && count > 0 && count <= charts.length - start, "Invalid chart range");
        vm.startBroadcast();
        for (uint256 i = start; i < start + count; ++i) {
            Chart memory chart = charts[i];
            bytes32 key = leaderboard.boardKey(chart.songId, chart.difficulty, chart.revision);
            (uint32 units,,) = leaderboard.boards(key);
            if (units == 0) {
                leaderboard.registerBoard(chart.songId, chart.difficulty, chart.revision, chart.units);
            } else {
                require(units == chart.units, "Existing board unit mismatch");
            }
        }
        vm.stopBroadcast();
    }
}
