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
        bytes32 commitRoot;
        bytes quorumBitmap;
        BN254.G2Point aggPkG2;
        BN254.G1Point signature;
    }

    /*=== events ===*/

    event DataUpload(bytes32 dataRoot, uint id, uint quorumId);
    event CommitRootVerified(bytes32 dataRoot, uint id, uint quorumId);

    /*=== functions ===*/
    function submitOriginalData(bytes32[] memory _dataRoots) external payable;

    function verifiedCommitRoot(bytes32, uint, uint) external view returns (bytes32);

    function submitVerifiedCommitRoots(CommitRootSubmission[] memory _submissions) external;
}
