// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./interface/IDARegistry.sol";
import "./libraries/BN254.sol";
import "./utils/Initializable.sol";

contract DARegistry is IDARegistry, Initializable {
    using BN254 for BN254.G1Point;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant REGISTRATION_DOMAIN = "REGISTRATION_DOMAIN";

    // signers
    EnumerableSet.AddressSet private signers;
    mapping(address => SignerDetail) public signerDetails;

    function initialize() external onlyInitializeOnce {}

    /*=== view functions ===*/
    function signerCount() external view returns (uint) {
        return signers.length();
    }

    function getSigners() external view returns (address[] memory accounts, SignerDetail[] memory details) {
        accounts = signers.values();
        uint n = accounts.length;
        details = new SignerDetail[](n);
        for (uint i = 0; i < n; ++i) {
            details[i] = signerDetails[accounts[i]];
        }
    }

    function checkSignature(
        BN254.G1Point memory _hash,
        address[] memory _signers,
        BN254.G2Point memory _aggPkG2,
        BN254.G1Point memory _signature
    ) external view {
        uint n = _signers.length;
        BN254.G1Point memory aggPkG1;
        for (uint i = 0; i < n; ++i) {
            require(signers.contains(_signers[i]), "DARegistry: not signer");
            if (i > 0) {
                require(_signers[i] > _signers[i - 1], "DARegistry: invalid signer order");
            }
            SignerDetail memory detail = signerDetails[_signers[i]];
            aggPkG1 = aggPkG1.plus(detail.pkG1);
        }
        uint gamma = uint(
            keccak256(
                abi.encodePacked(
                    _signature.X,
                    _signature.Y,
                    aggPkG1.X,
                    aggPkG1.Y,
                    _aggPkG2.X,
                    _aggPkG2.Y,
                    _hash.X,
                    _hash.Y
                )
            )
        ) % BN254.FR_MODULUS;
        (bool success, bool valid) = BN254.safePairing(
            _signature.plus(aggPkG1.scalar_mul(gamma)),
            BN254.negGeneratorG2(),
            _hash.plus(BN254.generatorG1().scalar_mul(gamma)),
            _aggPkG2,
            120000
        );
        require(success, "DARegistry: pairing precompile call failed");
        require(valid, "DARegistry: signature is invalid");
    }

    /*=== signer management ===*/

    function registrationMessageHash(address _account) public view returns (BN254.G1Point memory) {
        return BN254.hashToG1(keccak256(abi.encode(REGISTRATION_DOMAIN, _account)));
    }

    function _registerSigner(
        address _account,
        SignerDetail memory _signer,
        BN254.G1Point memory _hash,
        BN254.G1Point memory _signature
    ) internal {
        // pairing
        // gamma = h(sigma, P, P', H(m))
        uint gamma = uint(
            keccak256(
                abi.encodePacked(
                    _signature.X,
                    _signature.Y,
                    _signer.pkG1.X,
                    _signer.pkG1.Y,
                    _signer.pkG2.X,
                    _signer.pkG2.Y,
                    _hash.X,
                    _hash.Y
                )
            )
        ) % BN254.FR_MODULUS;
        require(
            BN254.pairing(
                _signature.plus(_signer.pkG1.scalar_mul(gamma)),
                BN254.negGeneratorG2(),
                _hash.plus(BN254.generatorG1().scalar_mul(gamma)),
                _signer.pkG2
            ),
            "DARegistry: signature verification failed"
        );
        // save signer
        signers.add(_account);
        signerDetails[_account] = _signer;
        emit NewSigner(_account, _signer.pkG1, _signer.pkG2);
        emit SocketUpdated(_account, _signer.socket);
    }

    function registerSigner(SignerDetail memory _signer, BN254.G1Point memory _signature) external {
        require(!signers.contains(msg.sender), "DARegistry: already registered");
        // TODO: signer staking
        _registerSigner(msg.sender, _signer, registrationMessageHash(msg.sender), _signature);
    }
}
