// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ReclaimHide {
    struct CompleteClaimData {
        bytes32 identifier;
        address owner;
        uint32 timestampS;
        uint32 epoch;
    }

    struct SignedClaim {
        CompleteClaimData claim;
        bytes[] signatures;
    }

    struct Proof {
        bytes32 hashedClaimInfo;
        SignedClaim signedClaim;
    }

    function verifyProof(Proof memory proof) external view returns (bool);
}

contract MockJack {
    // Aligned
    error InvalidElf(bytes32 provingSystemAuxDataCommitment);
    error ProofGeneratorAddrMismatch();
    error StaticCallFailed();
    error ProofNotIncludedInBatch();
    error PubInputCommitmentMismatch();

    event FillOfframp(bytes32 indexed requestOfframpId, address receiver, bytes32 proof, bytes32 reclaimProof);

    struct PublicValuesStruct {
        OfframpRequestParams offrampRequestParams;
        ReclaimHide.Proof proof;
    }

    struct OfframpRequestParams {
        address user;
        uint256 amount;
        uint256 amountRealWorld;
        bytes32 channelAccount;
        bytes32 channelId;
    }

    // aligned
    address public constant alignedServiceManager = 0x58F280BeBE9B34c9939C3C39e0890C81f163B623;
    address public constant paymentServiceAddr = 0x815aeCA64a974297942D2Bbf034ABEe22a38A003;
    // bytes32 public immutable elfCommitment;

    constructor() {
        // elfCommitment = _elfCommitment;
    }

    function fillOfframp(
        bytes32 proofCommitment,
        bytes32 pubInputCommitment,
        bytes32 provingSystemAuxDataCommitment,
        bytes20 proofGeneratorAddr,
        bytes32 batchMerkleRoot,
        bytes memory merkleProof,
        uint256 verificationDataBatchIndex,
        bytes memory pubInputBytes
    ) public {
        // verify aligned proof
        // skip elf commitment check for now
        // if (elfCommitment != provingSystemAuxDataCommitment) revert InvalidElf(provingSystemAuxDataCommitment);
        if (address(proofGeneratorAddr) != msg.sender) revert ProofGeneratorAddrMismatch();
        if (pubInputCommitment != keccak256(abi.encodePacked(pubInputBytes))) revert PubInputCommitmentMismatch();

        bytes32 fullHash = keccak256(
            abi.encodePacked(proofCommitment, pubInputCommitment, provingSystemAuxDataCommitment, proofGeneratorAddr)
        );

        // decode publicValuesStruct
        PublicValuesStruct memory publicValues = abi.decode(pubInputBytes, (PublicValuesStruct));

        (bool callWasSuccessfull, bytes memory proofIsIncluded) = alignedServiceManager.staticcall(
            abi.encodeWithSignature(
                "verifyBatchInclusion(bytes32,bytes32,bytes32,bytes20,bytes32,bytes,uint256,address)",
                proofCommitment,
                pubInputCommitment,
                provingSystemAuxDataCommitment,
                proofGeneratorAddr,
                batchMerkleRoot,
                merkleProof,
                verificationDataBatchIndex,
                paymentServiceAddr
            )
        );

        if (!callWasSuccessfull) revert StaticCallFailed();

        bool proofIsIncludedBool = abi.decode(proofIsIncluded, (bool));
        if (!proofIsIncludedBool) revert ProofNotIncludedInBatch();

        bytes32 requestOfframpId = keccak256(abi.encode(publicValues.offrampRequestParams));

        emit FillOfframp(requestOfframpId, msg.sender, fullHash, publicValues.proof.hashedClaimInfo);
    }

    function verifyFillOfframp(
        bytes32 proofCommitment,
        bytes32 pubInputCommitment,
        bytes32 provingSystemAuxDataCommitment,
        bytes20 proofGeneratorAddr,
        bytes32 batchMerkleRoot,
        bytes memory merkleProof,
        uint256 verificationDataBatchIndex,
        bytes memory pubInputBytes
    ) public view returns (bytes32) {
        if (address(proofGeneratorAddr) != msg.sender) revert ProofGeneratorAddrMismatch();
        if (pubInputCommitment != keccak256(abi.encodePacked(pubInputBytes))) revert PubInputCommitmentMismatch();

        PublicValuesStruct memory publicValues = abi.decode(pubInputBytes, (PublicValuesStruct));

        (bool callWasSuccessfull, bytes memory proofIsIncluded) = alignedServiceManager.staticcall(
            abi.encodeWithSignature(
                "verifyBatchInclusion(bytes32,bytes32,bytes32,bytes20,bytes32,bytes,uint256,address)",
                proofCommitment,
                pubInputCommitment,
                provingSystemAuxDataCommitment,
                proofGeneratorAddr,
                batchMerkleRoot,
                merkleProof,
                verificationDataBatchIndex,
                paymentServiceAddr
            )
        );

        if (!callWasSuccessfull) revert StaticCallFailed();

        bool proofIsIncludedBool = abi.decode(proofIsIncluded, (bool));
        if (!proofIsIncludedBool) revert ProofNotIncludedInBatch();

        bytes32 requestOfframpId = keccak256(abi.encode(publicValues.offrampRequestParams));

        return requestOfframpId;
    }
}
