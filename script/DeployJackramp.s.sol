// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Jackramp} from "../src/Jackramp.sol";

contract DeployJackrampScript is Script {
    Jackramp public jackramp;

    address public constant underlyingUSD = 0x8feE246199e162AC1b4969aD7ab32Ae3c4474102;
    address public constant alignedServiceManager = 0x58F280BeBE9B34c9939C3C39e0890C81f163B623;
    address public constant paymentServiceAddr = 0x815aeCA64a974297942D2Bbf034ABEe22a38A003;
    bytes32 public constant elfCommitment = 0x0000000000000000000000000000000000000000000000000000000000000000;
    address public constant reclaimHide = 0x8CDc031d5B7F148ab0435028B16c682c469CEfC3;

    function setUp() public {}

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        // base
        jackramp = new Jackramp(underlyingUSD, alignedServiceManager, paymentServiceAddr, elfCommitment, reclaimHide);

        console.log("Jackramp deployed at", address(jackramp));

        vm.stopBroadcast();
    }
}
