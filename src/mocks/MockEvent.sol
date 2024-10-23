// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract MockEvent {
    event RequestOfframp(bytes32 indexed requestOfframpId, OfframpRequestParams params);
    event FillOfframp(bytes32 indexed requestOfframpId, address receiver, bytes32 proof, bytes32 reclaimProof);

    struct OfframpRequestParams {
        address user;
        uint256 amount;
        uint256 amountRealWorld;
        bytes32 channelAccount;
        bytes32 channelId;
    }

    // Function for mock and testing purposes
    function mockRequestOfframp(
        address user,
        uint256 amount,
        uint256 amountRealWorld,
        string memory channelAccount,
        string memory channelId
    ) public {
        bytes32 requestOfframpId = keccak256(
            abi.encode(
                user, amount, amountRealWorld, keccak256(abi.encode(channelAccount)), keccak256(abi.encode(channelId))
            )
        );
        emit RequestOfframp(
            requestOfframpId,
            OfframpRequestParams(
                user, amount, amountRealWorld, keccak256(abi.encode(channelAccount)), keccak256(abi.encode(channelId))
            )
        );
    }

    function mockFillOfframp(
        bytes32 requestOfframpId,
        address receiver,
        string memory proof,
        string memory reclaimProof
    ) public {
        emit FillOfframp(requestOfframpId, receiver, keccak256(abi.encode(proof)), keccak256(abi.encode(reclaimProof)));
    }
}
