// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Origin} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import {OAppPreCrimeSimulatorUpgradeable} from "../../src/precrime/OAppPreCrimeSimulatorUpgradeable.sol";

contract PreCrimeV2SimulatorMock is OAppPreCrimeSimulatorUpgradeable {
    struct PreCrimeV2SimulatorMockStorage {
        uint256 _count;
    }

    // keccak256(abi.encode(uint256(keccak256("layerzero.storage.PreCrimeV2SimulatorMock")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PreCrimeV2SimulatorMockStorageLocation =
        0x064105631010ecee24d8f9e6ecdad1fb00ec3ed4960a05753476234f5e95d100;

    function _getPreCrimeV2SimulatorMockStorage() internal pure returns (PreCrimeV2SimulatorMockStorage storage $) {
        assembly {
            $.slot := PreCrimeV2SimulatorMockStorageLocation
        }
    }

    error InvalidEid();

    function count() external view returns (uint256) {
        PreCrimeV2SimulatorMockStorage storage $ = _getPreCrimeV2SimulatorMockStorage();
        return $._count;
    }

    function _lzReceiveSimulate(
        Origin calldata _origin,
        bytes32, /*_guid*/
        bytes calldata, /*_message*/
        address, /*_executor*/
        bytes calldata /*_extraData*/
    ) internal override {
        if (_origin.srcEid == 0) revert InvalidEid();
        PreCrimeV2SimulatorMockStorage storage $ = _getPreCrimeV2SimulatorMockStorage();
        $._count++;
    }

    function isPeer(uint32 _eid, bytes32 _peer) public pure override returns (bool) {
        return bytes32(uint256(_eid)) == _peer;
    }
}
