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

    address public addressBook; // 0g storage contract address book
    address public signerRegistry;
    // data roots => epoch number => verified commitment root
    mapping(bytes32 => mapping(uint => bytes32)) public verifiedCommitRoot;

    // initialize
    function initialize(address _addressBook) external onlyInitializeOnce {
        addressBook = _addressBook;
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
        uint epoch = DA_SIGNERS.epochNumber();
        // TODO: refund
        flow_.batchSubmit{value: msg.value}(_submissions);
        uint n = _submissions.length;
        for (uint i = 0; i < n; ++i) {
            bytes32 root = _getDataRoot(_submissions[i]);
            emit DataUpload(root, epoch);
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
            if (verifiedCommitRoot[_submissions[i].dataRoot][_submissions[i].epoch] != bytes32(0)) {
                continue;
            }
            // verify signature
            BN254.G1Point memory dataHash = BN254.hashToG1(
                keccak256(abi.encodePacked(_submissions[i].dataRoot, _submissions[i].epoch, _submissions[i].commitRoot))
            );
            BN254.G1Point memory aggPkG1 = DA_SIGNERS.getAggPkG1(_submissions[i].epoch, _submissions[i].signersBitmap);
            _validateSignature(dataHash, aggPkG1, _submissions[i].aggPkG2, _submissions[i].signature);
            // save verified root
            verifiedCommitRoot[_submissions[i].dataRoot][_submissions[i].epoch] = _submissions[i].commitRoot;
            emit CommitRootVerified(_submissions[i].dataRoot, _submissions[i].epoch);
        }
    }

    receive() external payable {}
}
