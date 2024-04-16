// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0 <0.9.0;

import "./ErrorMessage.sol";
import "./SignatureDecoder.sol";

import "../interface/ISignatureValidator.sol";

abstract contract SignatureValidator is ISignatureValidatorConstants, SignatureDecoder, ErrorMessage {
    /**
     * @notice Checks whether the contract signature is valid. Reverts otherwise.
     * @dev This is extracted to a separate function for better compatibility with Certora's prover.
     *      More info here: https://github.com/safe-global/safe-smart-account/pull/661
     * @param owner Address of the owner used to sign the message
     * @param dataHash Hash of the data (could be either a message hash or transaction hash)
     * @param signatures Signature data that should be verified.
     * @param offset Offset to the start of the contract signature in the signatures byte array
     */
    function checkContractSignature(
        address owner,
        bytes32 dataHash,
        bytes memory signatures,
        uint offset
    ) internal view {
        // Check that signature data pointer (s) is in bounds (points to the length of data -> 32 bytes)
        if (offset + 32 > signatures.length) revertWithError("GS022");

        // Check if the contract signature is in bounds: start of data is s + 32 and end is start + signature length
        uint contractSignatureLen;
        /* solhint-disable no-inline-assembly */
        /// @solidity memory-safe-assembly
        assembly {
            contractSignatureLen := mload(add(add(signatures, offset), 0x20))
        }
        /* solhint-enable no-inline-assembly */
        if (offset + 32 + contractSignatureLen > signatures.length) revertWithError("GS023");

        // Check signature
        bytes memory contractSignature;
        /* solhint-disable no-inline-assembly */
        /// @solidity memory-safe-assembly
        assembly {
            // The signature data for contract signatures is appended to the concatenated signatures and the offset is stored in s
            contractSignature := add(add(signatures, offset), 0x20)
        }
        /* solhint-enable no-inline-assembly */

        if (ISignatureValidator(owner).isValidSignature(dataHash, contractSignature) != EIP1271_MAGIC_VALUE)
            revertWithError("GS024");
    }

    function checkNSignatures(
        bytes32 dataHash,
        address[] memory signers,
        bytes memory signatures,
        uint requiredSignatures
    ) internal view {
        // Check that the provided signature data is not too short
        if (signatures.length < requiredSignatures * 65) revertWithError("GS020");
        // There cannot be an signer with address 0.
        address currentSigner;
        uint v; // Implicit conversion from uint8 to uint will be done for v received from signatureSplit(...).
        bytes32 r;
        bytes32 s;
        uint i;
        uint j;
        uint n = signers.length;
        for (i = 0; i < requiredSignatures; i++) {
            (v, r, s) = signatureSplit(signatures, i);
            if (v == 0) {
                // If v is 0 then it is a contract signature
                // When handling contract signatures the address of the contract is encoded into r
                currentSigner = address(uint160(uint(r)));

                // Check that signature data pointer (s) is not pointing inside the static part of the signatures bytes
                // This check is not completely accurate, since it is possible that more signatures than the threshold are send.
                // Here we only check that the pointer is not pointing inside the part that is being processed
                if (uint(s) < requiredSignatures * 65) revertWithError("GS021");

                // The contract signature check is extracted to a separate function for better compatibility with formal verification
                // A quote from the Certora team:
                // "The assembly code broke the pointer analysis, which switched the prover in failsafe mode, where it is (a) much slower and (b) computes different hashes than in the normal mode."
                // More info here: https://github.com/safe-global/safe-smart-account/pull/661
                checkContractSignature(currentSigner, dataHash, signatures, uint(s));
            } else if (v == 1) {
                revertWithError("GS025");
            } else if (v > 30) {
                // If v > 30 then default va (27,28) has been adjusted for eth_sign flow
                // To support eth_sign and similar we adjust v and hash the messageHash with the Ethereum message prefix before applying ecrecover
                currentSigner = ecrecover(
                    keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", dataHash)),
                    uint8(v - 4),
                    r,
                    s
                );
            } else {
                // Default is the ecrecover flow with the provided data hash
                // Use ecrecover with the messageHash for EOA signatures
                currentSigner = ecrecover(dataHash, uint8(v), r, s);
            }
            // check signer
            while (j < n && currentSigner != signers[j]) {
                j++;
            }
            if (j >= n || currentSigner != signers[j]) {
                revertWithError("GS026");
            }
        }
    }
}
