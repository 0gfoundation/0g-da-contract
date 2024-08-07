// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity >=0.8.0 <0.9.0;

import "./Submission.sol";
import "../libraries/BN254.sol";

interface IDAEntrance {
    /*=== structs ===*/
    struct CommitRootSubmission {
        bytes32 dataRoot;
        uint epoch;
        uint quorumId;
        BN254.G1Point erasureCommitment;
        bytes quorumBitmap;
        // the aggregate G2 pubkey pass to 0x08 precompile contract, pay attention to the element order:
        // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-197.md#encoding
        BN254.G2Point aggPkG2;
        BN254.G1Point signature;
    }

    /*=== events ===*/

    event DataUpload(address sender, bytes32 dataRoot, uint epoch, uint quorumId, uint blobPrice);
    event ErasureCommitmentVerified(bytes32 dataRoot, uint epoch, uint quorumId);

    /*=== functions ===*/
    function submitOriginalData(bytes32[] memory _dataRoots) external payable;

    function verifiedErasureCommitment(bytes32, uint, uint) external view returns (BN254.G1Point memory);

    function submitVerifiedCommitRoots(CommitRootSubmission[] memory _submissions) external;
}
