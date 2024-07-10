// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity >=0.8.0 <0.9.0;

import "../libraries/SampleVerifier.sol";
import "../interface/IDASample.sol";

contract MockDASample is IDASample {
    using SampleVerifier for SampleResponse;

    function submitSamplingResponse(SampleResponse memory rep) external view override {
        rep.verify();
    }

    function epochNumber() external pure returns (uint) {
        return 7;
    }

    function sampleTask() external view override returns (SampleTask memory) {
        return
            SampleTask({sampleHash: blockhash(0), quality: type(uint).max / 200, sampleHeight: 0, numSubmissions: 10});
    }
}
