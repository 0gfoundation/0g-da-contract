// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity >=0.8.0 <0.9.0;

import "./libraries/BN254.sol";
import "./libraries/SampleVerifier.sol";
import "./libraries/Submission.sol";

import "./utils/PullPayment.sol";

import "./interface/IDAEntrance.sol";
import "./interface/IDASample.sol";
import "./interface/IDASigners.sol";
import "./interface/IFlow.sol";
import "./interface/Submission.sol";

import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

contract DAEntrance is IDAEntrance, IDASample, PullPayment, AccessControlEnumerableUpgradeable {
    using SampleVerifier for SampleResponse;
    using SubmissionLib for CommitRootSubmission;
    using BN254 for BN254.G1Point;

    /// @custom:storage-location erc7201:0g.storage.DAEntrance
    struct DAEntranceStorage {
        // submission identifier => verified erasure commitment
        mapping(bytes32 => BN254.G1Point) verifiedErasureCommitment;
        uint quorumIndex;
        mapping(bytes32 => bool) submittedDASampling;
        uint currentEpoch;
        bytes32 currentSampleSeed;
        uint sampleRound;
        uint nextSampleHeight;
        uint podasTarget;
        uint roundSubmissions;
        uint targetRoundSubmissions;
        uint currentEpochReward;
        uint activedReward;
        uint totalBaseReward;
        uint serviceFee;
        // parameters for DA parameters
        uint targetRoundSubmissionsNext;
        uint epochWindowSize;
        uint rewardRatio;
        uint baseReward;
        uint blobPrice;
        uint samplePeriod;
        uint serviceFeeRateBps;
        address treasury;
    }

    // keccak256(abi.encode(uint(keccak256("0g.storage.DAEntrance")) - 1)) & ~bytes32(uint(0xff))
    bytes32 private constant DAEntranceStorageLocation =
        0x1f01119f54caddd4b5bcce29799619f00bb427288e5c1c0713537061bd123800;

    function _getDAEntranceStorage() private pure returns (DAEntranceStorage storage $) {
        assembly {
            $.slot := DAEntranceStorageLocation
        }
    }

    IDASigners public constant DA_SIGNERS = IDASigners(0x0000000000000000000000000000000000001000);

    bytes32 public constant PARAMS_ADMIN_ROLE = keccak256("PARAMS_ADMIN_ROLE");

    uint public constant SLICE_NUMERATOR = 2;
    uint public constant SLICE_DENOMINATOR = 3;
    uint public constant MAX_PODAS_TARGET = type(uint).max / 128;

    // initialize
    function initialize() external initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(PARAMS_ADMIN_ROLE, _msgSender());

        DAEntranceStorage storage $ = _getDAEntranceStorage();

        $.currentEpoch = DA_SIGNERS.epochNumber();
        $.samplePeriod = 30;
        $.nextSampleHeight = (block.number / $.samplePeriod + 1) * $.samplePeriod;
        $.podasTarget = MAX_PODAS_TARGET;

        $.targetRoundSubmissionsNext = 20;
        $.epochWindowSize = 300;
        $.rewardRatio = 1200000;
        $.baseReward = 0;
        $.blobPrice = 0;

        // deploy pullpayment escrow
        __PullPayment_init();
    }

    // ===============
    // View Functions
    // ===============

    function currentEpoch() external view returns (uint) {
        return _getDAEntranceStorage().currentEpoch;
    }

    function currentSampleSeed() external view returns (bytes32) {
        return _getDAEntranceStorage().currentSampleSeed;
    }

    function sampleRound() external view returns (uint) {
        return _getDAEntranceStorage().sampleRound;
    }

    function nextSampleHeight() external view returns (uint) {
        return _getDAEntranceStorage().nextSampleHeight;
    }

    function podasTarget() external view returns (uint) {
        return _getDAEntranceStorage().podasTarget;
    }

    function roundSubmissions() external view returns (uint) {
        return _getDAEntranceStorage().roundSubmissions;
    }

    function targetRoundSubmissions() external view returns (uint) {
        return _getDAEntranceStorage().targetRoundSubmissions;
    }

    function currentEpochReward() external view returns (uint) {
        return _getDAEntranceStorage().currentEpochReward;
    }

    function activedReward() external view returns (uint) {
        return _getDAEntranceStorage().activedReward;
    }

    function totalBaseReward() external view returns (uint) {
        return _getDAEntranceStorage().totalBaseReward;
    }

    function serviceFee() external view returns (uint) {
        return _getDAEntranceStorage().serviceFee;
    }

    function targetRoundSubmissionsNext() external view returns (uint) {
        return _getDAEntranceStorage().targetRoundSubmissionsNext;
    }

    function epochWindowSize() external view returns (uint) {
        return _getDAEntranceStorage().epochWindowSize;
    }

    function rewardRatio() external view returns (uint) {
        return _getDAEntranceStorage().rewardRatio;
    }

    function baseReward() external view returns (uint) {
        return _getDAEntranceStorage().baseReward;
    }

    function blobPrice() external view returns (uint) {
        return _getDAEntranceStorage().blobPrice;
    }

    function samplePeriod() external view returns (uint) {
        return _getDAEntranceStorage().samplePeriod;
    }

    function serviceFeeRateBps() external view returns (uint) {
        return _getDAEntranceStorage().serviceFeeRateBps;
    }

    function treasury() external view returns (address) {
        return _getDAEntranceStorage().treasury;
    }

    // ===============
    // Sync Interfaces
    // ===============

    function syncFixedTimes(uint _times) external {
        _syncEpoch();
        for (uint i = 0; i < _times; ++i) {
            _updateSampleRound();
        }
    }

    function sync() public {
        _syncEpoch();
        DAEntranceStorage storage $ = _getDAEntranceStorage();
        while (block.number >= $.nextSampleHeight) {
            _updateSampleRound();
        }
    }

    function _syncEpoch() internal {
        (bool success, ) = address(DA_SIGNERS).call(abi.encodeWithSelector(IDASigners.makeEpoch.selector));
        require(success, "DAEntrance: make epoch failed");
        uint epoch = DA_SIGNERS.epochNumber();
        DAEntranceStorage storage $ = _getDAEntranceStorage();
        if ($.currentEpoch == epoch) {
            return;
        }

        $.currentEpoch = epoch;
        _updateRewardOnNewEpoch();
    }

    function _updateSampleRound() internal {
        DAEntranceStorage storage $ = _getDAEntranceStorage();
        if (block.number < $.nextSampleHeight) {
            return;
        }

        if ($.sampleRound > 0) {
            $.podasTarget = _adjustPodasTarget();
        }

        $.sampleRound += 1;
        uint sampleHeight = $.nextSampleHeight;
        $.currentSampleSeed = blockhash($.nextSampleHeight - 1);
        $.nextSampleHeight += $.samplePeriod;
        $.targetRoundSubmissions = $.targetRoundSubmissionsNext;
        $.roundSubmissions = 0;

        emit NewSampleRound($.sampleRound, sampleHeight, $.currentSampleSeed, $.podasTarget);
    }

    function _updateRewardOnNewEpoch() internal {
        DAEntranceStorage storage $ = _getDAEntranceStorage();
        uint epochServiceFee = ($.currentEpochReward * $.serviceFeeRateBps) / 10000;
        $.activedReward += $.currentEpochReward - epochServiceFee;
        $.currentEpochReward = 0;
        if (epochServiceFee > 0) {
            // The treasury is a trusted address set by the admin, and does not require async payment.
            Address.sendValue(payable($.treasury), epochServiceFee);
        }
    }

    function _adjustPodasTarget() internal view returns (uint podasTargetNext) {
        DAEntranceStorage storage $ = _getDAEntranceStorage();

        uint targetDelta;
        // Scale target to avoid overflow
        uint scaledTarget = $.podasTarget >> 32;

        if ($.roundSubmissions > $.targetRoundSubmissions) {
            targetDelta =
                (scaledTarget * ($.roundSubmissions - $.targetRoundSubmissions)) /
                $.targetRoundSubmissions /
                8;
            scaledTarget -= targetDelta;
        } else {
            targetDelta =
                (scaledTarget * ($.targetRoundSubmissions - $.roundSubmissions)) /
                $.targetRoundSubmissions /
                8;
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
        DAEntranceStorage storage $ = _getDAEntranceStorage();
        return $.verifiedErasureCommitment[identifier];
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

        DAEntranceStorage storage $ = _getDAEntranceStorage();
        require(msg.value >= _dataRoots.length * $.blobPrice, "Not enough da blob fee");
        $.currentEpochReward += msg.value;

        uint quorumCount = DA_SIGNERS.quorumCount($.currentEpoch);
        require(quorumCount > 0, "DAEntrance: No DA Signers");
        $.quorumIndex = ($.quorumIndex + 1) % quorumCount;

        uint n = _dataRoots.length;
        for (uint i = 0; i < n; ++i) {
            emit DataUpload(msg.sender, _dataRoots[i], $.currentEpoch, $.quorumIndex, $.blobPrice);
        }
    }

    // submit commit roots and signatures
    function submitVerifiedCommitRoots(CommitRootSubmission[] memory _submissions) external {
        DAEntranceStorage storage $ = _getDAEntranceStorage();
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
            $.verifiedErasureCommitment[_submissions[i].identifier()] = _submissions[i].erasureCommitment;
            emit ErasureCommitmentVerified(_submissions[i].dataRoot, _submissions[i].epoch, _submissions[i].quorumId);
        }
    }

    // =====================
    // DA Sampling submission
    // =====================

    function submitSamplingResponse(SampleResponse memory rep) external {
        sync();

        DAEntranceStorage storage $ = _getDAEntranceStorage();

        bytes32 identifier = rep.identifier();
        require(!$.submittedDASampling[identifier], "Duplicated submission");
        $.submittedDASampling[identifier] = true;

        require($.sampleRound > 0, "Sample round 0 cannot be mined");
        require($.roundSubmissions < $.targetRoundSubmissions * 2, "Too many submissions in one round");
        require(rep.sampleSeed == $.currentSampleSeed, "Unmatched sample seed");
        require(rep.quality <= $.podasTarget, "Quality not reached");
        require(commitmentExists(rep.dataRoot, rep.epoch, rep.quorumId), "Unrecorded commitment");
        require(rep.epoch + $.epochWindowSize >= $.currentEpoch, "Epoch has stopped sampling");
        require(rep.epoch < $.currentEpoch, "Cannot sample current epoch");

        rep.verify();

        address beneficiary = DA_SIGNERS.getQuorumRow(rep.epoch, rep.quorumId, rep.lineIndex);
        $.roundSubmissions += 1;

        uint reward = $.activedReward / $.rewardRatio;
        $.activedReward -= reward;
        reward += _claimBaseReward();
        if (reward > 0) {
            _asyncTransfer(beneficiary, reward);
        }

        emit DAReward(
            beneficiary,
            $.sampleRound,
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
        DAEntranceStorage storage $ = _getDAEntranceStorage();
        actualReward = $.totalBaseReward > $.baseReward ? $.baseReward : $.totalBaseReward;
        $.totalBaseReward -= actualReward;
    }

    function donate() public payable {
        sync();
        DAEntranceStorage storage $ = _getDAEntranceStorage();
        $.totalBaseReward += msg.value;
    }

    function sampleTask() external returns (SampleTask memory) {
        sync();
        DAEntranceStorage storage $ = _getDAEntranceStorage();
        uint maxRoundSubmissions = $.targetRoundSubmissions * 2;

        return
            SampleTask({
                sampleHash: $.currentSampleSeed,
                restSubmissions: uint64(maxRoundSubmissions - $.roundSubmissions),
                podasTarget: $.podasTarget
            });
    }

    function sampleRange() external returns (SampleRange memory) {
        sync();
        uint startEpoch = 0;
        uint endEpoch = 0;
        DAEntranceStorage storage $ = _getDAEntranceStorage();
        if ($.currentEpoch > 0) {
            endEpoch = $.currentEpoch - 1;
        }
        if (endEpoch >= $.epochWindowSize) {
            startEpoch = endEpoch - ($.epochWindowSize - 1);
        }

        return SampleRange({startEpoch: uint64(startEpoch), endEpoch: uint64(endEpoch)});
    }

    // =====================
    // Set Parameters
    // =====================

    function setRoundSubmissions(uint64 _targetRoundSubmissions) external onlyRole(PARAMS_ADMIN_ROLE) {
        sync();

        DAEntranceStorage storage $ = _getDAEntranceStorage();
        require(_targetRoundSubmissions <= $.targetRoundSubmissions * 4, "Increase round submissions too large");
        require(_targetRoundSubmissions >= $.targetRoundSubmissions / 4, "Decrease round submissions too large");
        require(_targetRoundSubmissions > 0, "Round submissions cannot be zero");

        $.targetRoundSubmissionsNext = _targetRoundSubmissions;
    }

    function setEpochWindowSize(uint64 _epochWindowSize) external onlyRole(PARAMS_ADMIN_ROLE) {
        sync();
        DAEntranceStorage storage $ = _getDAEntranceStorage();
        require(_epochWindowSize > 0, "Epoch window size cannot be zero");
        $.epochWindowSize = _epochWindowSize;
    }

    function setRewardRatio(uint64 _rewardRatio) external onlyRole(PARAMS_ADMIN_ROLE) {
        sync();
        DAEntranceStorage storage $ = _getDAEntranceStorage();
        require(_rewardRatio > 0, "Reward ratio must be non-zero");
        $.rewardRatio = _rewardRatio;
    }

    function setBaseReward(uint _baseReward) external onlyRole(PARAMS_ADMIN_ROLE) {
        sync();
        DAEntranceStorage storage $ = _getDAEntranceStorage();
        $.baseReward = _baseReward;
    }

    function setSamplePeriod(uint64 samplePeriod_) external onlyRole(PARAMS_ADMIN_ROLE) {
        sync();
        DAEntranceStorage storage $ = _getDAEntranceStorage();
        $.samplePeriod = samplePeriod_;
        if ($.sampleRound == 0) {
            $.nextSampleHeight = (block.number / $.samplePeriod + 1) * $.samplePeriod;
        }
    }

    function setBlobPrice(uint _blobPrice) external onlyRole(PARAMS_ADMIN_ROLE) {
        sync();
        DAEntranceStorage storage $ = _getDAEntranceStorage();
        $.blobPrice = _blobPrice;
    }

    function setServiceFeeRate(uint bps) external onlyRole(PARAMS_ADMIN_ROLE) {
        sync();
        DAEntranceStorage storage $ = _getDAEntranceStorage();
        $.serviceFeeRateBps = bps;
    }

    function setTreasury(address treasury_) external onlyRole(PARAMS_ADMIN_ROLE) {
        sync();
        DAEntranceStorage storage $ = _getDAEntranceStorage();
        $.treasury = treasury_;
    }
}
