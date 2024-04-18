// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity >=0.8.0 <0.9.0;

import "../libraries/BN254.sol";

interface IDARegistry {
    /*=== struct ===*/
    struct SignerDetail {
        string socket;
        BN254.G1Point pkG1;
        BN254.G2Point pkG2;
    }

    /*=== event ===*/
    event NewSigner(address indexed signer, BN254.G1Point pkG1, BN254.G2Point pkG2);
    event SocketUpdated(address indexed signer, string socket);

    /*=== function ===*/
    function getSigners() external view returns (address[] memory accounts, SignerDetail[] memory details);

    function signerCount() external view returns (uint);

    function checkSignature(
        BN254.G1Point memory _hash,
        address[] memory _signers,
        BN254.G2Point memory _aggPkG2,
        BN254.G1Point memory _signature
    ) external view;
}
