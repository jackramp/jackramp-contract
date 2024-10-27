// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

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

contract Jackramp is ERC20, ReentrancyGuardTransient {
    error OfframpRequestAlreadyExists();
    error OfframpRequestAmountIsZero();
    error OfframpRequestChannelAccountIsEmpty();
    error OfframpRequestChannelIdIsEmpty();
    error OfframpRequestDoesNotExist();
    error OfframpRequestAlreadyProved();
    // Aligned
    error InvalidElf(bytes32 provingSystemAuxDataCommitment);
    error ProofGeneratorAddrMismatch();
    error ProofAlreadyUsed(bytes32 fullHash);
    error StaticCallFailed();
    error ProofNotIncludedInBatch();
    error PubInputCommitmentMismatch();
    // Reclaim
    error InvalidReclaimProof();
    error ReclaimProofAlreadyUsed(bytes32 hashedClaimInfo);

    event Mint(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event RequestOfframp(bytes32 indexed requestOfframpId, OfframpRequestParams params);
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

    struct OfframpRequestStorage {
        address user;
        uint256 amount;
        uint256 amountRealWorld;
        bytes32 channelAccount;
        bytes32 channelId;
        bool isProved;
        bytes32 proof;
        bytes32 reclaimProof;
    }

    using SafeERC20 for IERC20;

    // aligned
    address public immutable alignedServiceManager;
    address public immutable paymentServiceAddr;
    bytes32 public immutable elfCommitment;

    // reclaim
    address public immutable reclaimHide;

    // storages
    address public immutable underlyingUSD;

    mapping(bytes32 => OfframpRequestStorage) public offrampRequests;
    mapping(bytes32 => bool) public usedProofs;
    mapping(bytes32 => bool) public usedReclaimProofs;

    constructor(
        address _underlyingUSD,
        address _alignedServiceManager,
        address _paymentServiceAddr,
        bytes32 _elfCommitment,
        address _reclaimHide
    ) ERC20("jackUSD", "jackUSD") {
        underlyingUSD = _underlyingUSD;
        alignedServiceManager = _alignedServiceManager;
        paymentServiceAddr = _paymentServiceAddr;
        elfCommitment = _elfCommitment;
        reclaimHide = _reclaimHide;
    }

    function mint(uint256 amount) public nonReentrant {
        _mint(msg.sender, amount);
        IERC20(underlyingUSD).safeTransferFrom(msg.sender, address(this), amount);
        emit Mint(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant {
        _burn(msg.sender, amount);
        IERC20(underlyingUSD).safeTransfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    function requestOfframp(OfframpRequestParams memory params) public nonReentrant {
        bytes32 requestOfframpId = keccak256(abi.encode(params));

        if (offrampRequests[requestOfframpId].user != address(0)) revert OfframpRequestAlreadyExists();
        if (params.amount == 0) revert OfframpRequestAmountIsZero();
        if (params.amountRealWorld == 0) revert OfframpRequestAmountIsZero();
        if (params.channelAccount == bytes32("")) revert OfframpRequestChannelAccountIsEmpty();
        if (params.channelId == bytes32("")) revert OfframpRequestChannelIdIsEmpty();

        // sanitize params
        params.user = msg.sender;
        params.amountRealWorld = params.amount;

        // IERC20(address(this)).safeTransferFrom(msg.sender, address(this), params.amount);

        _transfer(msg.sender, address(this), params.amount);

        offrampRequests[requestOfframpId] = OfframpRequestStorage({
            user: params.user,
            amount: params.amount,
            amountRealWorld: params.amountRealWorld,
            channelAccount: params.channelAccount,
            channelId: params.channelId,
            isProved: false,
            proof: "",
            reclaimProof: ""
        });

        emit RequestOfframp(requestOfframpId, params);
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
    ) public nonReentrant {
        // verify aligned proof
        if (elfCommitment != provingSystemAuxDataCommitment) revert InvalidElf(provingSystemAuxDataCommitment);
        if (address(proofGeneratorAddr) != msg.sender) revert ProofGeneratorAddrMismatch();
        if (pubInputCommitment != keccak256(abi.encodePacked(pubInputBytes))) revert PubInputCommitmentMismatch();

        bytes32 fullHash = keccak256(
            abi.encodePacked(proofCommitment, pubInputCommitment, provingSystemAuxDataCommitment, proofGeneratorAddr)
        );

        // decode publicValuesStruct
        PublicValuesStruct memory publicValues = abi.decode(pubInputBytes, (PublicValuesStruct));

        if (usedProofs[proofCommitment]) revert ProofAlreadyUsed(proofCommitment);
        if (usedReclaimProofs[publicValues.proof.hashedClaimInfo]) {
            revert ReclaimProofAlreadyUsed(publicValues.proof.hashedClaimInfo);
        }

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

        // verify Reclaim proof
        //if (!ReclaimHide(reclaimHide).verifyProof(publicValues.proof)) revert InvalidReclaimProof();

        bytes32 requestOfframpId = keccak256(abi.encode(publicValues.offrampRequestParams));

        OfframpRequestStorage storage request = offrampRequests[requestOfframpId];

        if (request.user == address(0)) revert OfframpRequestDoesNotExist();
        if (request.isProved) revert OfframpRequestAlreadyProved();

        request.isProved = true;
        request.proof = fullHash;
        request.reclaimProof = publicValues.proof.hashedClaimInfo;
        usedProofs[fullHash] = true;
        usedReclaimProofs[publicValues.proof.hashedClaimInfo] = true;

        _burn(address(this), request.amount);

        IERC20(underlyingUSD).safeTransfer(msg.sender, request.amount);

        emit FillOfframp(requestOfframpId, msg.sender, fullHash, publicValues.proof.hashedClaimInfo);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
