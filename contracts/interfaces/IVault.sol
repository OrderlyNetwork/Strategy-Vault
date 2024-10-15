pragma solidity ^0.8.24;

library VaultTypes {
    struct VaultDelegate {
        bytes32 brokerHash;
        address delegateSigner;
    }
}

interface IVault {
    function delegateSigner(VaultTypes.VaultDelegate calldata data) external;
}
