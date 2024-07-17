// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity >=0.8.0 <0.9.0;

import "../libraries/SampleVerifier.sol";

interface IDASample {
    struct SampleTask {
        bytes32 sampleHash;
        uint podasTarget;
        uint64 restSubmissions;
    }

    struct SampleRange {
        uint64 startEpoch;
        uint64 endEpoch;
    }

    event NewSampleRound(uint indexed sampleRound, uint sampleHeight, bytes32 sampleSeed, uint podasTarget);

    event DAReward(
        address indexed beneficiary,
        uint indexed sampleRound,
        uint indexed epoch,
        uint quorumId,
        bytes32 dataRoot,
        uint quality,
        uint lineIndex,
        uint sublineIndex,
        uint reward
    );

    function commitmentExists(bytes32 _dataRoot, uint _epoch, uint _quorumId) external view returns (bool);

    function submitSamplingResponse(SampleResponse memory rep) external;

    function sampleTask() external returns (SampleTask memory);

    function sampleRange() external returns (SampleRange memory);
}
