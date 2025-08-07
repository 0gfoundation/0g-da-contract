// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "./interface/IDASigners.sol";
import "./interface/IDARegistry.sol";

import "./libraries/TransferHelper.sol";

contract DARegistry is IDARegistry, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    address public constant DA_SIGNERS = 0x0000000000000000000000000000000000001000;

    /// @custom:storage-location erc7201:0g.storage.DARegistry
    struct DARegistryStorage {
        uint tokensPerVote;
        uint maxVotes;
        mapping(address => uint) staked;
    }

    // keccak256(abi.encode(uint(keccak256("0g.storage.DARegistry")) - 1)) & ~bytes32(uint(0xff))
    bytes32 private constant DARegistryStorageLocation =
        0xd3e43b6fb85c1d2775adfd20bf0a5286bdb95963bf3e7f19c7a6513722c95000;

    function _getDARegistryStorage() private pure returns (DARegistryStorage storage $) {
        assembly {
            $.slot := DARegistryStorageLocation
        }
    }

    function initialize() external initializer {
        __Ownable_init(0x2D7F2d2286994477Ba878f321b17A7e40E52cDa4);

        DARegistryStorage storage $ = _getDARegistryStorage();
        $.maxVotes = 30 ether;
        $.tokensPerVote = 102400;
    }

    function staked(address account) external view returns (uint) {
        DARegistryStorage storage $ = _getDARegistryStorage();
        return $.staked[account];
    }

    function stake() external payable nonReentrant {
        if (msg.sender != tx.origin) {
            revert ErrSenderNotOrigin();
        }
        DARegistryStorage storage $ = _getDARegistryStorage();
        $.staked[msg.sender] += msg.value;
        emit Staked(msg.sender, msg.value);
    }

    function withdraw() external nonReentrant {
        if (msg.sender != tx.origin) {
            revert ErrSenderNotOrigin();
        }
        uint epoch = IDASigners(DA_SIGNERS).epochNumber();
        if (
            IDASigners(DA_SIGNERS).registeredEpoch(msg.sender, epoch) ||
            IDASigners(DA_SIGNERS).registeredEpoch(msg.sender, epoch + 1)
        ) {
            revert ErrSenderRegisteredCurrentOrNextEpoch();
        }

        DARegistryStorage storage $ = _getDARegistryStorage();
        uint amount = $.staked[msg.sender];
        $.staked[msg.sender] = 0;
        TransferHelper.safeTransferETH(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    function registerSigner(
        IDASigners.SignerDetail memory _signer,
        BN254.G1Point memory _signature
    ) external nonReentrant {
        if (msg.sender != tx.origin) {
            revert ErrSenderNotOrigin();
        }
        if (msg.sender != _signer.signer) {
            revert ErrSenderNotSigner();
        }
        DARegistryStorage storage $ = _getDARegistryStorage();
        if ($.staked[msg.sender] < $.tokensPerVote) {
            revert ErrInsufficientStaked();
        }
        (bool success, bytes memory returnData) = DA_SIGNERS.call(
            abi.encodeWithSelector(IDASigners.registerSigner.selector, _signer, _signature)
        );
        require(success, string(abi.encodePacked("registerSigner call failed: ", returnData)));
    }

    function registerNextEpoch(BN254.G1Point memory _signature) external nonReentrant {
        if (msg.sender != tx.origin) {
            revert ErrSenderNotOrigin();
        }
        DARegistryStorage storage $ = _getDARegistryStorage();
        uint votes = $.staked[msg.sender] / $.tokensPerVote;
        if (votes > $.maxVotes) {
            votes = $.maxVotes;
        }
        if (votes == 0) {
            revert ErrSenderNotEligibleToVote();
        }
        (bool success, bytes memory returnData) = DA_SIGNERS.call(
            abi.encodeWithSelector(IDASigners.registerNextEpoch.selector, msg.sender, _signature, votes)
        );
        require(success, string(abi.encodePacked("registerNextEpoch call failed: ", returnData)));
    }
}
