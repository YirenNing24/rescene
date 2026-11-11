// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {ResceneLeaderboard} from "../src/ResceneLeaderboard.sol";

contract DeployLeaderboard is Script {
    function run() external returns (ResceneLeaderboard leaderboard) {
        address admin = vm.envAddress("LEADERBOARD_ADMIN");
        address publisher = vm.envAddress("LEADERBOARD_PUBLISHER");
        uint256 configuredDelay = vm.envOr("LEADERBOARD_ADMIN_DELAY", uint256(2 days));
        require(configuredDelay <= type(uint48).max, "Admin delay exceeds uint48");
        uint48 delay = uint48(configuredDelay);
        vm.startBroadcast();
        leaderboard = new ResceneLeaderboard(admin, publisher, delay);
        vm.stopBroadcast();
    }
}
