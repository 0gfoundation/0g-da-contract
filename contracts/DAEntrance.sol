// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity >=0.8.0 <0.9.0;

import "./libraries/BN254.sol";

import "./utils/Initializable.sol";

import "./interface/IDAEntrance.sol";
import "./interface/IDASigners.sol";
import "./interface/IAddressBook.sol";
import "./interface/IFlow.sol";
import "./interface/Submission.sol";

contract DAEntrance is IDAEntrance, Initializable {
    using BN254 for BN254.G1Point;

    IDASigners public immutable DA_SIGNERS = IDASigners(0x0000000000000000000000000000000000001000);
    uint public immutable SLICE_NUMERATOR = 3;
    uint public immutable SLICE_DENOMINATOR = 8;

    // data roots => epoch number => quorum id => verified erasure commitment
    mapping(bytes32 => mapping(uint => mapping(uint => BN254.G1Point))) private _verifiedErasureCommitment;
    uint private _quorumIndex;

    // initialize
    function initialize() external onlyInitializeOnce {}

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
            {
                BN254.G1Point memory commitment = _verifiedErasureCommitment[_submissions[i].dataRoot][
                    _submissions[i].epoch
                ][_submissions[i].quorumId];
                if (commitment.X != 0 || commitment.Y != 0) {
                    continue;
                }
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

    receive() external payable {}
}
