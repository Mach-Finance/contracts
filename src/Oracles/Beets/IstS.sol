// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.22;

interface IstS {
    // https://github.com/beethovenxfi/sonic-staking/blob/4fde3014f287f2ba38d559a23317a892e92cd3e6/src/SonicStaking.sol#L254
    // rate = total $S / total stS
    function getRate() external view returns (uint256);
}
