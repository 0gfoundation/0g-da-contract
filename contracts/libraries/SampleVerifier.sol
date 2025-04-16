// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.12;

uint64 constant NUM_COSET = 3;
uint64 constant BLOB_ROW = 1024;
uint64 constant BLOB_COL = 1024;
uint64 constant SUBLINES = 32;

struct SampleResponse {
    bytes32 sampleSeed;
    uint64 epoch;
    uint64 quorumId;
    uint32 lineIndex;
    uint32 sublineIndex;
    uint quality;
    bytes32 dataRoot;
    bytes32[3] blobRoots; // NUM_COSET
    bytes32[] proof;
    bytes data;
}

library SampleVerifier {
    function identifier(SampleResponse memory rep) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(rep.sampleSeed, rep.epoch, rep.quorumId, rep.lineIndex, rep.sublineIndex));
    }

    function verify(SampleResponse memory rep) internal pure {
        require(rep.sampleSeed != bytes32(0), "Sample seed cannot be empty");

        require(rep.lineIndex < BLOB_ROW * NUM_COSET, "Incorrect line index");
        require(rep.sublineIndex < SUBLINES, "Incorrect sub-line index");

        uint lineQuality = calculateLineQuality(rep.sampleSeed, rep.epoch, rep.quorumId, rep.dataRoot, rep.lineIndex);
        uint dataQuality = calculateDataQuality(lineQuality, uint(rep.sublineIndex), rep.data);
        require(type(uint).max - lineQuality >= dataQuality, "Quality overflow");
        require(lineQuality + dataQuality == rep.quality, "Incorrect quality");

        require(rep.data.length == (32 * BLOB_COL) / SUBLINES, "Incorrect data length");

        bytes32 lineRoot = calculateLineRoot(rep.data);

        uint64 blobIndex = rep.lineIndex / BLOB_ROW;
        bytes32 blobRoot = rep.blobRoots[blobIndex];

        uint64 merklePosition = (rep.lineIndex % BLOB_ROW) * SUBLINES + rep.sublineIndex;
        verifyBlobRoot(lineRoot, blobRoot, rep.proof, merklePosition);
        verifyDataRoot(rep.blobRoots, rep.dataRoot);
    }

    function calculateDataQuality(uint lineQuality, uint sublineIndex, bytes memory data) internal pure returns (uint) {
        return uint(keccak256(abi.encodePacked(lineQuality, sublineIndex, data)));
    }

    function calculateLineQuality(
        bytes32 blockHash,
        uint epoch,
        uint quorumId,
        bytes32 dataRoot,
        uint64 lineIndex
    ) internal pure returns (uint) {
        return uint(keccak256(abi.encodePacked(blockHash, epoch, quorumId, dataRoot, lineIndex)));
    }

    function verifyDataRoot(bytes32[3] memory blobRoots, bytes32 dataRoot) internal pure {
        require(calculateDataRoot(blobRoots) == dataRoot, "Incorrect dataRoot");
    }

    function calculateDataRoot(bytes32[3] memory blobRoots) internal pure returns (bytes32) {
        return keccakPair(keccakPair(blobRoots[0], blobRoots[1]), blobRoots[2]);
    }

    /**
     * @dev Calculates the Merkle root of a given blob line following 0g-storage rule.
     * @param data A blob line.
     * @return The calculated line Merkle root.
     */
    function calculateLineRoot(bytes memory data) internal pure returns (bytes32) {
        uint length = data.length;

        // Check if length is greater than 256 and a power of 2
        require(
            length >= 256 && (length & (length - 1)) == 0,
            "Data length must be greater than 256 and a power of 2."
        );

        uint numHashes = length / 256;
        bytes32[] memory hashes = new bytes32[](numHashes);

        // Compute Keccak hash for each 256 bytes chunk
        for (uint i = 0; i < numHashes; i++) {
            bytes32 h;
            assembly {
                let dataPtr := add(data, add(32, mul(i, 256)))
                h := keccak256(dataPtr, 256)
            }
            hashes[i] = h;
        }

        // Calculate the Merkle root
        while (numHashes > 1) {
            uint half = numHashes / 2;
            for (uint i = 0; i < half; i++) {
                hashes[i] = keccakPair(hashes[2 * i], hashes[2 * i + 1]);
            }
            numHashes = half;
        }

        return hashes[0];
    }

    /**
     * @dev Verifies if a given leaf node (blob line root) is part of a Merkle tree with a given root (blob root).
     * @param lineRoot The leaf node (blob line root).
     * @param blobRoot The root of the Merkle tree (blob root).
     * @param proof The Merkle proof, a list of sibling hashes from the root to the leaf.
     * @param leafIndex The index of the leaf node in the Merkle tree.
     */
    function verifyBlobRoot(
        bytes32 lineRoot,
        bytes32 blobRoot,
        bytes32[] memory proof,
        uint64 leafIndex
    ) internal pure {
        bytes32 currentHash = lineRoot;

        for (uint i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            if (leafIndex % 2 == 0) {
                // Current node is a left child
                currentHash = keccakPair(currentHash, proofElement);
            } else {
                // Current node is a right child
                currentHash = keccakPair(proofElement, currentHash);
            }

            // Move to the next level
            leafIndex >>= 1;
        }

        // Check if the computed root matches the provided blob root
        require(currentHash == blobRoot, "Incorrect blob Root");
    }

    function keccakPair(bytes32 x, bytes32 y) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(x, y));
    }
}
