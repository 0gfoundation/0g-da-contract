// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0 <0.9.0;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

struct SubmissionNode {
    bytes32 root;
    uint height;
}

struct Submission {
    uint length;
    bytes tags;
    SubmissionNode[] nodes;
}
