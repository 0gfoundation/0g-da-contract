// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity >=0.8.0 <0.9.0;

import "./Submission.sol";

interface IDAEntrance {
    /*=== structs ===*/
    struct CommitRootSubmission {
        bytes32 dataRoot;
        uint id;
        bytes32 commitRoot;
        address[] signers;
        bytes signatures;
    }

    /*=== events ===*/

    event DataUpload(bytes32 dataRoot, uint id);
    event CommitRootVerified(bytes32 dataRoot, uint id);

    /*=== functions ===*/
    function addressBook() external view returns (address);
    function dataRootCnt(bytes32) external view returns (uint);
    function getSignersAndThreshold(
        bytes32 /*_dataRoot*/,
        uint /*_id*/
    ) external view returns (address[] memory res, uint threshold);
    function submitOriginalData(Submission[] memory _submissions) external payable;
    function verifiedCommitRoot(bytes32, uint) external view returns (bytes32);
    function submitVerifiedCommitRoots(CommitRootSubmission[] memory _submissions) external;
}
