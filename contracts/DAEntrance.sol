// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity >=0.8.0 <0.9.0;

import "./libraries/BN254.sol";
import "./libraries/SampleVerifier.sol";

import "./utils/Initializable.sol";

import "./interface/IDAEntrance.sol";
import "./interface/IDASample.sol";
import "./interface/IDASigners.sol";
import "./interface/IAddressBook.sol";
import "./interface/IFlow.sol";
import "./interface/Submission.sol";

contract DAEntrance is IDAEntrance, IDASample, Initializable {
    using BN254 for BN254.G1Point;
    using SampleVerifier for SampleResponse;

    // reserved storage slots for base contract upgrade in future
    uint[50] private __gap;

    IDASigners public immutable DA_SIGNERS = IDASigners(0x0000000000000000000000000000000000001000);
    uint public immutable SLICE_NUMERATOR = 3;
    uint public immutable SLICE_DENOMINATOR = 8;

    // data roots => epoch number => quorum id => verified erasure commitment
    mapping(bytes32 => mapping(uint => mapping(uint => BN254.G1Point))) private _verifiedErasureCommitment;
    uint private _quorumIndex;

    // parameters for DA Sampling
    uint public nextSampleHeight;
    uint public targetQuality;
    uint public immutable MAX_TARGET_QUALITY = type(uint).max / 262144;
    uint public roundSubmissions;
    uint public immutable TARGET_ROUND_SUBMISSIONS = 20;

    // initialize
    function initialize() external onlyInitializeOnce {
        nextSampleHeight = SampleVerifier.nextSampleHeight(block.number);
        targetQuality = MAX_TARGET_QUALITY;
    }

    /*
    function _getDataRoot(Submission memory _submission) internal pure returns (bytes32 root) {
        uint i = _submission.nodes.length - 1;
        root = _submission.nodes[i].root;
        while (i > 0) {
            --i;
            root = keccak256(abi.encode(_submission.nodes[i].root, root));
        }
    }
    */

    function verifiedErasureCommitment(
        bytes32 _dataRoot,
        uint _epoch,
        uint _quorumId
    ) external view returns (BN254.G1Point memory) {
        return _verifiedErasureCommitment[_dataRoot][_epoch][_quorumId];
    }

    function commitmentExists(bytes32 _dataRoot, uint _epoch, uint _quorumId) public view returns (bool) {
        BN254.G1Point memory commitment = _verifiedErasureCommitment[_dataRoot][_epoch][_quorumId];

        return commitment.X != 0 || commitment.Y != 0;
    }

    // submit encoded data
    function submitOriginalData(bytes32[] memory _dataRoots) external payable {
        uint epoch = DA_SIGNERS.epochNumber();
        uint quorumCount = DA_SIGNERS.quorumCount(epoch);
        require(quorumCount > 0, "DAEntrance: No DA Signers");
        _quorumIndex = (_quorumIndex + 1) % quorumCount;
        /*
        // TODO: refund
        flow_.batchSubmit{value: msg.value}(_submissions);
        uint n = _submissions.length;
        for (uint i = 0; i < n; ++i) {
            bytes32 root = _getDataRoot(_submissions[i]);
            emit DataUpload(root, epoch);
        }
        */
        uint n = _dataRoots.length;
        for (uint i = 0; i < n; ++i) {
            emit DataUpload(_dataRoots[i], epoch, _quorumIndex);
        }
    }

    function _validateSignature(
        BN254.G1Point memory _hash,
        BN254.G1Point memory _aggPkG1,
        BN254.G2Point memory _aggPkG2,
        BN254.G1Point memory _signature
    ) internal view {
        uint gamma = uint(
            keccak256(
                abi.encodePacked(
                    _signature.X,
                    _signature.Y,
                    _aggPkG1.X,
                    _aggPkG1.Y,
                    _aggPkG2.X,
                    _aggPkG2.Y,
                    _hash.X,
                    _hash.Y
                )
            )
        ) % BN254.FR_MODULUS;
        (bool success, bool valid) = BN254.safePairing(
            _signature.plus(_aggPkG1.scalar_mul(gamma)),
            BN254.negGeneratorG2(),
            _hash.plus(BN254.generatorG1().scalar_mul(gamma)),
            _aggPkG2,
            120000
        );
        require(success, "DARegistry: pairing precompile call failed");
        require(valid, "DARegistry: signature is invalid");
    }

    // submit commit roots and signatures
    function submitVerifiedCommitRoots(CommitRootSubmission[] memory _submissions) external {
        uint n = _submissions.length;
        for (uint i = 0; i < n; ++i) {
            if (commitmentExists(_submissions[i].dataRoot, _submissions[i].epoch, _submissions[i].quorumId)) {
                continue;
            }

            // verify signature
            BN254.G1Point memory dataHash = BN254.hashToG1(
                keccak256(
                    abi.encodePacked(
                        _submissions[i].dataRoot,
                        _submissions[i].epoch,
                        _submissions[i].quorumId,
                        _submissions[i].erasureCommitment.X,
                        _submissions[i].erasureCommitment.Y
                    )
                )
            );
            (BN254.G1Point memory aggPkG1, uint total, uint hit) = DA_SIGNERS.getAggPkG1(
                _submissions[i].epoch,
                _submissions[i].quorumId,
                _submissions[i].quorumBitmap
            );
            require(SLICE_NUMERATOR * total <= hit * SLICE_DENOMINATOR, "DARegistry: insufficient signed slices");
            _validateSignature(dataHash, aggPkG1, _submissions[i].aggPkG2, _submissions[i].signature);
            // save verified root
            _verifiedErasureCommitment[_submissions[i].dataRoot][_submissions[i].epoch][
                _submissions[i].quorumId
            ] = _submissions[i].erasureCommitment;
            emit ErasureCommitmentVerified(_submissions[i].dataRoot, _submissions[i].epoch, _submissions[i].quorumId);
        }
    }

    function submitSamplingResponse(SampleResponse memory rep) external {
        updateSampleRound();

        require(roundSubmissions < TARGET_ROUND_SUBMISSIONS * 2, "Too many submissions in one round");
        require(rep.sampleHeight == nextSampleHeight - SAMPLE_PERIOD, "Unmatched sample height");
        require(rep.quality <= targetQuality, "Quality not reached");
        require(commitmentExists(rep.dataRoot, rep.epoch, rep.quorumId), "Unrecorded commitment");
        // TODO: check whether epoch is still valid

        rep.verify();

        // TODO: better DA_SIGNERS interface
        address beneficiary = DA_SIGNERS.getQuorumRow(rep.epoch, rep.quorumId, rep.lineIndex);
        roundSubmissions += 1;

        // TODO: send reward
        payable(beneficiary).transfer(0);

        emit DAReward(
            beneficiary,
            rep.sampleHeight,
            rep.epoch,
            rep.quorumId,
            rep.dataRoot,
            rep.quality,
            rep.lineIndex,
            rep.sublineIndex
        );
    }

    function updateSampleRound() public {
        if (block.number < nextSampleHeight) {
            return;
        }

        uint targetQualityDelta;
        if (roundSubmissions > TARGET_ROUND_SUBMISSIONS) {
            targetQualityDelta = (roundSubmissions - TARGET_ROUND_SUBMISSIONS) / TARGET_ROUND_SUBMISSIONS / 8;
            targetQuality -= targetQualityDelta;
        } else {
            targetQualityDelta = (TARGET_ROUND_SUBMISSIONS - roundSubmissions) / TARGET_ROUND_SUBMISSIONS / 8;
            targetQuality += targetQualityDelta;
        }
        if (targetQuality > MAX_TARGET_QUALITY) {
            targetQuality = MAX_TARGET_QUALITY;
        }

        nextSampleHeight = SampleVerifier.nextSampleHeight(block.number);
        roundSubmissions = 0;
    }

    function sampleTask() external returns (SampleTask memory) {
        updateSampleRound();

        uint sampleHeight = nextSampleHeight - SAMPLE_PERIOD;

        return
            SampleTask({
                sampleHash: blockhash(sampleHeight),
                numSubmissions: uint64(roundSubmissions),
                sampleHeight: uint64(sampleHeight),
                quality: targetQuality
            });
    }

    receive() external payable {}
}
