// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.12;

import "../interface/IDAEntrance.sol";

library SubmissionLib {
    using BN254 for BN254.G1Point;

    function identifier(IDAEntrance.CommitRootSubmission memory submission) internal pure returns (bytes32) {
        return computeIdentifier(submission.dataRoot, submission.epoch, submission.quorumId);
    }

    function computeIdentifier(bytes32 _dataRoot, uint _epoch, uint _quorumId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_dataRoot, _epoch, _quorumId));
    }

    function dataHash(IDAEntrance.CommitRootSubmission memory submission) internal view returns (BN254.G1Point memory) {
        return
            BN254.hashToG1(
                keccak256(
                    abi.encodePacked(
                        submission.dataRoot,
                        submission.epoch,
                        submission.quorumId,
                        submission.erasureCommitment.X,
                        submission.erasureCommitment.Y
                    )
                )
            );
    }

    function validateSignature(
        IDAEntrance.CommitRootSubmission memory submission,
        BN254.G1Point memory _aggPkG1
    ) internal view {
        BN254.G1Point memory _hash = dataHash(submission);
        BN254.G2Point memory _aggPkG2 = submission.aggPkG2;
        BN254.G1Point memory _signature = submission.signature;

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
}
