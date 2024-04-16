// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./safe/SignatureValidator.sol";
import "./utils/Initializable.sol";

import "./interface/IDAEntrance.sol";
import "./interface/IAddressBook.sol";
import "./interface/IFlow.sol";
import "./interface/Submission.sol";

contract DAEntrance is IDAEntrance, SignatureValidator, Initializable {
    using EnumerableSet for EnumerableSet.AddressSet;

    // 0g storage contract address book
    address public addressBook;
    // signers
    EnumerableSet.AddressSet private signers;
    // data roots
    mapping(bytes32 => uint) public dataRootCnt;
    mapping(bytes32 => mapping(uint => bytes32)) public verifiedCommitRoot;

    // initialize
    function initialize(address _addressBook, address[] memory _signers) external onlyInitializeOnce {
        addressBook = _addressBook;
        uint n = _signers.length;
        for (uint i = 0; i < n; ++i) {
            signers.add(_signers[i]);
        }
    }

    function getSignersAndThreshold(
        bytes32 /*_dataRoot*/,
        uint /*_id*/
    ) public view returns (address[] memory res, uint threshold) {
        // TODO: pick signers use VRF
        res = signers.values();
        threshold = (res.length * 2) / 3;
    }

    // submit original data

    function _getDataRoot(Submission memory _submission) internal pure returns (bytes32 root) {
        uint i = _submission.nodes.length - 1;
        root = _submission.nodes[i].root;
        while (i > 0) {
            --i;
            root = keccak256(abi.encode(_submission.nodes[i].root, root));
        }
    }

    function submitOriginalData(Submission[] memory _submissions) external payable {
        IFlow flow_ = IFlow(IAddressBook(addressBook).flow());
        // TODO: refund
        flow_.batchSubmit{value: msg.value}(_submissions);
        uint n = _submissions.length;
        for (uint i = 0; i < n; ++i) {
            bytes32 root = _getDataRoot(_submissions[i]);
            dataRootCnt[root] += 1;
            emit DataUpload(root, dataRootCnt[root] - 1);
        }
    }

    // submit commit roots and signatures
    function submitVerifiedCommitRoots(CommitRootSubmission[] memory _submissions) external {
        uint n = _submissions.length;
        for (uint i = 0; i < n; ++i) {
            require(dataRootCnt[_submissions[i].dataRoot] > _submissions[i].id, "DAEntrance: invalid id");
            if (verifiedCommitRoot[_submissions[i].dataRoot][_submissions[i].id] != bytes32(0)) {
                continue;
            }
            bytes32 dataHash = keccak256(
                abi.encodePacked(_submissions[i].dataRoot, _submissions[i].id, _submissions[i].commitRoot)
            );
            (address[] memory blobSigners, uint threshold) = getSignersAndThreshold(
                _submissions[i].dataRoot,
                _submissions[i].id
            );
            checkNSignatures(dataHash, blobSigners, _submissions[i].signatures, threshold);
            verifiedCommitRoot[_submissions[i].dataRoot][_submissions[i].id] = _submissions[i].commitRoot;
            emit CommitRootVerified(_submissions[i].dataRoot, _submissions[i].id);
        }
    }

    receive() external payable {}
}
