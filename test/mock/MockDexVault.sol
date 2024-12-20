// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {VaultDepositFE} from "../../contracts/interfaces/IDexVault.sol";

contract MockDexVault {
    uint256 public amount;

    function depositTo(address, VaultDepositFE calldata data) external payable {
        amount = data.tokenAmount;
    }
}
