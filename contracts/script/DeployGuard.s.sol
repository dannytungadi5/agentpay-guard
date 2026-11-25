// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AgentPayGuard} from "../src/AgentPayGuard.sol";

/// @notice Deploys AgentPayGuard against the real tUSD8 (Aevum testnet 44005 or `make fork` 440050).
///   forge script script/DeployGuard.s.sol --rpc-url https://rpc-test.qday.info --broadcast --legacy --account <keystore>
contract DeployGuard is Script {
    address constant AEVUM_TUSD8 = 0x456569838f1d43009A91ebA4263147Afd7233483;

    function run() external returns (AgentPayGuard guard) {
        require(AEVUM_TUSD8.code.length > 0, "tUSD8 not found: check the RPC (Aevum testnet is chain 44005)");
        vm.startBroadcast();
        guard = new AgentPayGuard(IERC20(AEVUM_TUSD8));
        vm.stopBroadcast();
        console.log("chainId        ", block.chainid);
        console.log("AgentPayGuard  ", address(guard));
    }
}
