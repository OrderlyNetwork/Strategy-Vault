// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IDepositProxyImplementation} from "../interfaces/IDepositProxyImplementation.sol";
import {IProtocolVault} from "../interfaces/IProtocolVault.sol";
import {IDexVault, VaultDepositFE} from "../interfaces/IDexVault.sol";
import {DepositParams} from "../lib/types/VaultStruct.sol";

/// @title DepositBeaconImpl
/// @notice Implementation contract for deposit proxies
/// @dev This contract is used via OpenZeppelin's BeaconProxy pattern
/// @dev Proxies query factory (beacon) for current implementation address on each call
contract DepositBeaconImpl is IDepositProxyImplementation, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Factory address used for authorization
    address public immutable FACTORY;

    constructor(address _factory) {
        FACTORY = _factory;
    }

    modifier onlyFactory() {
        if (msg.sender != FACTORY) revert OnlyFactory();
        _;
    }

    /// @inheritdoc IDepositProxyImplementation
    function depositToVault(address vault, DepositParams memory params) external payable onlyFactory nonReentrant {
        // Approve vault to spend tokens
        IERC20(params.token).forceApprove(vault, params.amount);

        // Deposit to vault with msg.value
        IProtocolVault(vault).deposit{value: msg.value}(params);
    }

    /// @inheritdoc IDepositProxyImplementation
    function depositToDex(address dexVault, address receiver, address token, VaultDepositFE memory data)
        external
        payable
        onlyFactory
        nonReentrant
    {
        // Approve dexVault to spend tokens
        IERC20(token).forceApprove(dexVault, uint128(data.tokenAmount));

        // Deposit to dexVault
        IDexVault(dexVault).depositTo{value: msg.value}(receiver, data);
    }

    /// @inheritdoc IDepositProxyImplementation
    function withdraw(address token, address to, uint256 amount) external onlyFactory nonReentrant {
        IERC20(token).safeTransfer(to, amount);
    }
}
