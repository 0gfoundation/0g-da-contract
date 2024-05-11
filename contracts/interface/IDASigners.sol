// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity >=0.8.0 <0.9.0;

import "../libraries/BN254.sol";

interface IDASigners {
    /*=== struct ===*/
    struct SignerDetail {
        address signer;
        string socket;
        BN254.G1Point pkG1;
        BN254.G2Point pkG2;
    }

    /*=== event ===*/
    event NewSigner(address indexed signer, BN254.G1Point pkG1, BN254.G2Point pkG2);
    event SocketUpdated(address indexed signer, string socket);

    /*=== function ===*/
    function epochNumber() external view returns (uint);

    function getSigner(address account) external view returns (SignerDetail memory);

    function getSigners(uint epoch) external view returns (SignerDetail[] memory details);

    function registerSigner(SignerDetail memory _signer, BN254.G1Point memory _signature) external;

    function updateSocket(string memory socket) external;

    function registerNextEpoch(BN254.G1Point memory _signature) external;

    function getAggPkG1(
        uint epoch,
        bytes memory signersBitmap
    ) external view returns (BN254.G1Point memory aggPkG1, uint total, uint hit);
}
