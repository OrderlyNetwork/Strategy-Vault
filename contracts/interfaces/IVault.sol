pragma solidity ^0.8.26;

library VaultTypes {
    struct VaultDelegate {
        bytes32 brokerHash;
        address delegateSigner;
    }
}

interface IVault {
    function delegateSigner(VaultTypes.VaultDelegate calldata data) external;
}
