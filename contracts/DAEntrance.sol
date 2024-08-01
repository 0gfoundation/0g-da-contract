// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity >=0.8.0 <0.9.0;

import "./libraries/BN254.sol";
import "./libraries/SampleVerifier.sol";
import "./libraries/Submission.sol";

import "./utils/ZgInitializable.sol";
import "./utils/PullPayment.sol";

import "./interface/IDAEntrance.sol";
import "./interface/IDASample.sol";
import "./interface/IDASigners.sol";
import "./interface/IAddressBook.sol";
import "./interface/IFlow.sol";
import "./interface/Submission.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract DAEntrance is IDAEntrance, IDASample, PullPayment, ZgInitializable, AccessControlEnumerable {
    using SampleVerifier for SampleResponse;
    using SubmissionLib for CommitRootSubmission;
    using BN254 for BN254.G1Point;

    // reserved storage slots for base contract upgrade in future
    uint[50] private __gap;

    IDASigners public constant DA_SIGNERS = IDASigners(0x0000000000000000000000000000000000001000);
    uint public constant SLICE_NUMERATOR = 2;
    uint public constant SLICE_DENOMINATOR = 3;
    bytes32 public constant PARAMS_ADMIN_ROLE = keccak256("PARAMS_ADMIN_ROLE");

    // submission identifier => verified erasure commitment
    mapping(bytes32 => BN254.G1Point) private _verifiedErasureCommitment;
    uint private _quorumIndex;
    mapping(bytes32 => bool) private _submittedDASampling;

    uint public currentEpoch;

    // state for DA Sampling
    uint public constant MAX_PODAS_TARGET = type(uint).max / 128;
    bytes32 public currentSampleSeed;
    uint public sampleRound;
    uint public nextSampleHeight;
    uint public podasTarget;
    uint public roundSubmissions;
    uint public targetRoundSubmissions;
    uint public currentEpochReward;
    uint public activedReward;
    uint public totalBaseReward;
    uint public serviceFee;

    // parameters for DA parameters
    uint public targetRoundSubmissionsNext;
    uint public epochWindowSize;
    uint public rewardRatio;
    uint public baseReward;
    uint public blobPrice;
    uint public samplePeriod;
    uint public serviceFeeRateBps;
    address public treasury;

    // initialize
    function initialize() external onlyInitializeOnce {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(PARAMS_ADMIN_ROLE, _msgSender());

        currentEpoch = DA_SIGNERS.epochNumber();
        samplePeriod = 30;
        nextSampleHeight = (block.number / samplePeriod + 1) * samplePeriod;
        podasTarget = MAX_PODAS_TARGET;

        targetRoundSubmissionsNext = 20;
        epochWindowSize = 300;
        rewardRatio = 1200000;
        baseReward = 0;
        blobPrice = 0;

        // deploy pullpayment escrow
        _escrow = new Escrow();
    }

    // ===============
    // Sync Interfaces
    // ===============

    function sync() public {
        _syncEpoch();
        _updateSampleRound();
    }

    function _syncEpoch() internal {
        uint epoch = DA_SIGNERS.epochNumber();
        if (currentEpoch == epoch) {
            return;
        }

        currentEpoch = epoch;
        _updateRewardOnNewEpoch();
    }

    function _updateSampleRound() internal {
        if (block.number < nextSampleHeight) {
            return;
        }

        if (sampleRound > 0) {
            podasTarget = _adjustPodasTarget();
        }

        sampleRound += 1;
        uint sampleHeight = nextSampleHeight;
        currentSampleSeed = blockhash(nextSampleHeight - 1);
        nextSampleHeight += samplePeriod;
        targetRoundSubmissions = targetRoundSubmissionsNext;
        roundSubmissions = 0;

        emit NewSampleRound(sampleRound, sampleHeight, currentSampleSeed, podasTarget);
    }

    function _updateRewardOnNewEpoch() internal {
        uint epochServiceFee = (currentEpochReward * serviceFeeRateBps) / 10000;
        activedReward += currentEpochReward - epochServiceFee;
        currentEpochReward = 0;
        if (epochServiceFee > 0) {
            // The treasury is a trusted address set by the admin, and does not require async payment.
            Address.sendValue(payable(treasury), epochServiceFee);
        }
    }

    function _adjustPodasTarget() internal view returns (uint podasTargetNext) {
        uint targetDelta;
        // Scale target to avoid overflow
        uint scaledTarget = podasTarget >> 32;

        if (roundSubmissions > targetRoundSubmissions) {
            targetDelta = (scaledTarget * (roundSubmissions - targetRoundSubmissions)) / targetRoundSubmissions / 8;
            scaledTarget -= targetDelta;
        } else {
            targetDelta = (scaledTarget * (targetRoundSubmissions - roundSubmissions)) / targetRoundSubmissions / 8;
            scaledTarget += targetDelta;
        }

        if (scaledTarget >= MAX_PODAS_TARGET >> 32) {
            podasTargetNext = MAX_PODAS_TARGET;
        } else {
            podasTargetNext = scaledTarget << 32;
        }
    }

    // ===============
    // Query Interfaces
    // ===============

    function verifiedErasureCommitment(
        bytes32 _dataRoot,
        uint _epoch,
        uint _quorumId
    ) public view returns (BN254.G1Point memory) {
        bytes32 identifier = SubmissionLib.computeIdentifier(_dataRoot, _epoch, _quorumId);
        return _verifiedErasureCommitment[identifier];
    }

    function commitmentExists(bytes32 _dataRoot, uint _epoch, uint _quorumId) public view returns (bool) {
        BN254.G1Point memory commitment = verifiedErasureCommitment(_dataRoot, _epoch, _quorumId);

        return !commitment.isZero();
    }

    // ===============
    // Blob Submission
    // ===============
    function submitOriginalData(bytes32[] memory _dataRoots) external payable {
        sync();

        require(msg.value >= _dataRoots.length * blobPrice, "Not enough da blob fee");
        currentEpochReward += msg.value;

        uint quorumCount = DA_SIGNERS.quorumCount(currentEpoch);
        require(quorumCount > 0, "DAEntrance: No DA Signers");
        _quorumIndex = (_quorumIndex + 1) % quorumCount;

        uint n = _dataRoots.length;
        for (uint i = 0; i < n; ++i) {
            emit DataUpload(_dataRoots[i], currentEpoch, _quorumIndex, blobPrice);
        }
    }

    // submit commit roots and signatures
    function submitVerifiedCommitRoots(CommitRootSubmission[] memory _submissions) external {
        uint n = _submissions.length;
        for (uint i = 0; i < n; ++i) {
            if (commitmentExists(_submissions[i].dataRoot, _submissions[i].epoch, _submissions[i].quorumId)) {
                continue;
            }

            // verify signature
            (BN254.G1Point memory aggPkG1, uint total, uint hit) = DA_SIGNERS.getAggPkG1(
                _submissions[i].epoch,
                _submissions[i].quorumId,
                _submissions[i].quorumBitmap
            );
            _submissions[i].validateSignature(aggPkG1);
            require(SLICE_NUMERATOR * total <= hit * SLICE_DENOMINATOR, "DARegistry: insufficient signed slices");

            // save verified root
            _verifiedErasureCommitment[_submissions[i].identifier()] = _submissions[i].erasureCommitment;
            emit ErasureCommitmentVerified(_submissions[i].dataRoot, _submissions[i].epoch, _submissions[i].quorumId);
        }
    }

    // =====================
    // DA Sampling submission
    // =====================

    function submitSamplingResponse(SampleResponse memory rep) external {
        sync();

        bytes32 identifier = rep.identifier();
        require(!_submittedDASampling[identifier], "Duplicated submission");
        _submittedDASampling[identifier] = true;

        require(sampleRound > 0, "Sample round 0 cannot be mined");
        require(roundSubmissions < targetRoundSubmissions * 2, "Too many submissions in one round");
        require(rep.sampleSeed == currentSampleSeed, "Unmatched sample seed");
        require(rep.quality <= podasTarget, "Quality not reached");
        require(commitmentExists(rep.dataRoot, rep.epoch, rep.quorumId), "Unrecorded commitment");
        require(rep.epoch + epochWindowSize >= currentEpoch, "Epoch has stopped sampling");
        require(rep.epoch < currentEpoch, "Cannot sample current epoch");

        rep.verify();

        address beneficiary = DA_SIGNERS.getQuorumRow(rep.epoch, rep.quorumId, rep.lineIndex);
        roundSubmissions += 1;

        uint reward = activedReward / rewardRatio;
        activedReward -= reward;
        reward += _claimBaseReward();
        if (reward > 0) {
            _asyncTransfer(beneficiary, reward);
        }

        emit DAReward(
            beneficiary,
            sampleRound,
            rep.epoch,
            rep.quorumId,
            rep.dataRoot,
            rep.quality,
            rep.lineIndex,
            rep.sublineIndex,
            reward
        );
    }

    function _claimBaseReward() internal returns (uint actualReward) {
        actualReward = totalBaseReward > baseReward ? baseReward : totalBaseReward;
        totalBaseReward -= actualReward;
    }

    function donate() public payable {
        sync();
        totalBaseReward += msg.value;
    }

    function sampleTask() external returns (SampleTask memory) {
        sync();
        uint maxRoundSubmissions = targetRoundSubmissions * 2;

        return
            SampleTask({
                sampleHash: currentSampleSeed,
                restSubmissions: uint64(maxRoundSubmissions - roundSubmissions),
                podasTarget: podasTarget
            });
    }

    function sampleRange() external returns (SampleRange memory) {
        sync();
        uint startEpoch = 0;
        uint endEpoch = 0;
        if (currentEpoch > 0) {
            endEpoch = currentEpoch - 1;
        }
        if (endEpoch >= epochWindowSize) {
            startEpoch = endEpoch - (epochWindowSize - 1);
        }

        return SampleRange({startEpoch: uint64(startEpoch), endEpoch: uint64(endEpoch)});
    }

    // =====================
    // Set Parameters
    // =====================

    function setRoundSubmissions(uint64 _targetRoundSubmissions) external onlyRole(PARAMS_ADMIN_ROLE) {
        sync();

        require(_targetRoundSubmissions <= targetRoundSubmissions * 4, "Increase round submissions too large");
        require(_targetRoundSubmissions >= targetRoundSubmissions / 4, "Decrease round submissions too large");
        require(_targetRoundSubmissions > 0, "Round submissions cannot be zero");

        targetRoundSubmissionsNext = _targetRoundSubmissions;
    }

    function setEpochWindowSize(uint64 _epochWindowSize) external onlyRole(PARAMS_ADMIN_ROLE) {
        sync();
        require(_epochWindowSize > 0, "Epoch window size cannot be zero");
        epochWindowSize = _epochWindowSize;
    }

    function setRewardRatio(uint64 _rewardRatio) external onlyRole(PARAMS_ADMIN_ROLE) {
        sync();
        require(_rewardRatio > 0, "Reward ratio must be non-zero");
        rewardRatio = _rewardRatio;
    }

    function setBaseReward(uint _baseReward) external onlyRole(PARAMS_ADMIN_ROLE) {
        sync();
        baseReward = _baseReward;
    }

    function setSamplePeriod(uint64 samplePeriod_) external onlyRole(PARAMS_ADMIN_ROLE) {
        sync();
        samplePeriod = samplePeriod_;
        if (sampleRound == 0) {
            nextSampleHeight = (block.number / samplePeriod + 1) * samplePeriod;
        }
    }

    function setBlobPrice(uint _blobPrice) external onlyRole(PARAMS_ADMIN_ROLE) {
        sync();
        blobPrice = _blobPrice;
    }

    function setServiceFeeRate(uint bps) external onlyRole(PARAMS_ADMIN_ROLE) {
        sync();
        serviceFeeRateBps = bps;
    }

    function setTreasury(address treasury_) external onlyRole(PARAMS_ADMIN_ROLE) {
        sync();
        treasury = treasury_;
    }
}
