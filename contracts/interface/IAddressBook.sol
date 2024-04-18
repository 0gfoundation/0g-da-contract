// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0 <0.9.0;

interface IAddressBook {
    function market() external view returns (address);

    function reward() external view returns (address);

    function flow() external view returns (address);

    function mine() external view returns (address);
}
