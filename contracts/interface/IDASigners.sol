// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity >=0.8.0 <0.9.0;

import "../libraries/BN254.sol";

interface IDASigners {
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
    function epochNumber() external view returns (uint);

    function getSigners(uint epoch) external view returns (address[] memory accounts, SignerDetail[] memory details);

    function registerSigner(SignerDetail memory _signer, BN254.G1Point memory _signature) external;

    function getAggPkG1(uint epoch, bytes memory signersBitmap) external view returns (BN254.G1Point memory aggPkG1);
}
