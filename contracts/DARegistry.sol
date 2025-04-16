// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interface/IDASigners.sol";

error ErrSenderNotOrigin();
error ErrSenderNotSigner();

contract DARegistry is OwnableUpgradeable {
    address public constant DA_SIGNERS = 0x0000000000000000000000000000000000001000;

    /*
    /// @custom:storage-location erc7201:0g.storage.DARegistry
    struct DARegistryStorage {
    }

    // keccak256(abi.encode(uint(keccak256("0g.storage.DARegistry")) - 1)) & ~bytes32(uint(0xff))
    bytes32 private constant DARegistryStorageLocation = 0xd3e43b6fb85c1d2775adfd20bf0a5286bdb95963bf3e7f19c7a6513722c95000;

    function _getDARegistryStorage() private pure returns (DARegistryStorage storage $) {
        assembly {
            $.slot := DARegistryStorageLocation
        }
    }
    */

    function initialize() external initializer {
        __Ownable_init(0x2D7F2d2286994477Ba878f321b17A7e40E52cDa4);
    }

    function registerSigner(IDASigners.SignerDetail memory _signer, BN254.G1Point memory _signature) external {
        if (msg.sender != tx.origin) {
            revert ErrSenderNotOrigin();
        }
        if (msg.sender != _signer.signer) {
            revert ErrSenderNotSigner();
        }
        (bool success, bytes memory returnData) = DA_SIGNERS.call(
            abi.encodeWithSelector(IDASigners.registerSigner.selector, _signer, _signature)
        );
        require(success, string(abi.encodePacked("registerSigner call failed: ", returnData)));
    }

    function registerNextEpoch(BN254.G1Point memory _signature) external {
        if (msg.sender != tx.origin) {
            revert ErrSenderNotOrigin();
        }
        (bool success, bytes memory returnData) = DA_SIGNERS.call(
            abi.encodeWithSelector(IDASigners.registerNextEpoch.selector, msg.sender, _signature, 1)
        );
        require(success, string(abi.encodePacked("registerNextEpoch call failed: ", returnData)));
    }
}
