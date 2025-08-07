// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity >=0.8.0 <0.9.0;

interface IDARegistry {
    error ErrSenderNotOrigin();
    error ErrSenderNotSigner();
    error ErrSenderNotEligibleToVote();
    error ErrSenderRegisteredCurrentOrNextEpoch();
    error ErrInsufficientStaked();

    event Staked(address account, uint amount);
    event Withdraw(address account, uint amount);
}
