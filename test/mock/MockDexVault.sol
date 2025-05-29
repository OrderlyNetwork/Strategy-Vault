// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {VaultDepositFE} from "../../contracts/interfaces/IDexVault.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

contract MockDexVault {
    bytes32 constant NATIVE_HASH = 0x0000000000000000000000000000000000000000000000000000000000000000;

    uint256 public amount;
    address public token;
    bool public depositFeeEnabled = true;

    //receive native token
    receive() external payable {}

    function depositTo(address, VaultDepositFE calldata data) external payable {
        if (data.tokenHash != NATIVE_HASH) {
            SafeTransferLib.safeTransferFrom(ERC20(token), msg.sender, address(this), data.tokenAmount);
            amount += data.tokenAmount;
        }
    }

    function getDepositFee(address, VaultDepositFE calldata) external pure returns (uint256) {
        return 0;
    }

    function depositId() external pure returns (uint256) {
        return 1;
    }

    function setToken(address _token) external {
        token = _token;
    }
}
