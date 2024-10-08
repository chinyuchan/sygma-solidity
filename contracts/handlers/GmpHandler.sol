// The Licensed Work is (c) 2022 Sygma
// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../interfaces/IHandler.sol";
import "../utils/SanityChecks.sol";

/**
    @title Handles generic deposits and deposit executions.
    @author ChainSafe Systems.
    @notice This contract is intended to be used with the Bridge contract.
 */
contract GmpHandler is IHandler {
    using SanityChecks for *;

    uint256 public constant MAX_FEE = 1000000;

    address public immutable _bridgeAddress;

    modifier onlyBridge() {
        _onlyBridge();
        _;
    }

    function _onlyBridge() private view {
        require(msg.sender == _bridgeAddress, "sender must be bridge contract");
    }

    /**
        @param bridgeAddress Contract address of previously deployed Bridge.
     */
    constructor(
        address          bridgeAddress
    ) {
        _bridgeAddress = bridgeAddress;
    }

    /**
        @notice Blank function, required in IHandler.
        @param resourceID ResourceID to be used when making deposits.
        @param contractAddress Address of contract to be called when a deposit is made and a deposited is executed.
        @param args Additional data to be passed to specified handler.
     */
    function setResource(
        bytes32 resourceID,
        address contractAddress,
        bytes calldata args
    ) external onlyBridge {}

    /**
        @notice A deposit is initiated by making a deposit in the Bridge contract.
        @param resourceID ResourceID used to find address of contract to be used for deposit.
        @param depositor Address of the account making deposit in the Bridge contract.
        @param data Structure should be constructed as follows:
          maxFee:                       uint256  bytes  0                                                                                           -  32
          len(executeFuncSignature):    uint16   bytes  32                                                                                          -  34
          executeFuncSignature:         bytes    bytes  34                                                                                          -  34 + len(executeFuncSignature)
          len(executeContractAddress):  uint8    bytes  34 + len(executeFuncSignature)                                                              -  35 + len(executeFuncSignature)
          executeContractAddress        bytes    bytes  35 + len(executeFuncSignature)                                                              -  35 + len(executeFuncSignature) + len(executeContractAddress)
          len(executionDataDepositor):  uint8    bytes  35 + len(executeFuncSignature) + len(executeContractAddress)                                -  36 + len(executeFuncSignature) + len(executeContractAddress)
          executionDataDepositor:       bytes    bytes  36 + len(executeFuncSignature) + len(executeContractAddress)                                -  36 + len(executeFuncSignature) + len(executeContractAddress) + len(executionDataDepositor)
          executionData:                bytes    bytes  36 + len(executeFuncSignature) + len(executeContractAddress) + len(executionDataDepositor)  -  END

          executionData is repacked together with executionDataDepositor address for using it in the target contract.
          If executionData contains dynamic types then it is necessary to keep the offsets correct.
          executionData should be encoded together with a 32-byte address and then passed as a parameter without that address.
          If the target function accepts (address depositor, bytes executionData)
          then a function like the following one can be used:

            function prepareDepositData(bytes calldata executionData) view external returns (bytes memory) {
                bytes memory encoded = abi.encode(address(0), executionData);
                return this.slice(encoded, 32);
            }

            function slice(bytes calldata input, uint256 position) pure public returns (bytes memory) {
                return input[position:];
            }
          After this, the target contract will get the following:
          executeFuncSignature(address executionDataDepositor, bytes executionData)

          Another example: if the target function accepts (address depositor, uint[], address)
          then a function like the following one can be used:

            function prepareDepositData(uint[] calldata uintArray, address addr) view external returns (bytes memory) {
                bytes memory encoded = abi.encode(address(0), uintArray, addr);
                return this.slice(encoded, 32);
            }

          After this, the target contract will get the following:
          executeFuncSignature(address executionDataDepositor, uint[] uintArray, address addr)
     */
    function deposit(bytes32 resourceID, address depositor, bytes calldata data) external view returns (bytes memory) {
        require(data.length >= 76, "Incorrect data length"); // 32 + 2 + 1 + 1 + 20 + 20

        uint256        maxFee;
        uint16         lenExecuteFuncSignature;
        uint8          lenExecuteContractAddress;
        uint8          lenExecutionDataDepositor;
        address        executionDataDepositor;

        uint256 pointer = 0;

        maxFee                            = uint256(bytes32(data[:pointer += 32])); 
        lenExecuteFuncSignature           = uint16(bytes2(data[pointer:pointer += 2]));
        pointer += lenExecuteFuncSignature;
        lenExecuteContractAddress         = uint8(bytes1(data[pointer:pointer += 1]));
        pointer += lenExecuteContractAddress;
        lenExecutionDataDepositor         = uint8(bytes1(data[pointer:pointer += 1]));
        executionDataDepositor            = address(uint160(bytes20(data[pointer:pointer + lenExecutionDataDepositor])));

        require(maxFee < MAX_FEE, 'requested fee too large');
        require(depositor == executionDataDepositor, 'incorrect depositor in deposit data');
    }

    /**
        @notice Proposal execution should be initiated when a proposal is finalized in the Bridge contract.
        @param resourceID ResourceID used to find address of contract to be used for deposit.
        @param data Structure should be constructed as follows:
          maxFee:                             uint256  bytes  0                                                             -  32
          len(executeFuncSignature):          uint16   bytes  32                                                            -  34
          executeFuncSignature:               bytes    bytes  34                                                            -  34 + len(executeFuncSignature)
          len(executeContractAddress):        uint8    bytes  34 + len(executeFuncSignature)                                -  35 + len(executeFuncSignature)
          executeContractAddress              bytes    bytes  35 + len(executeFuncSignature)                                -  35 + len(executeFuncSignature) + len(executeContractAddress)
          len(executionDataDepositor):        uint8    bytes  35 + len(executeFuncSignature) + len(executeContractAddress)  -  36 + len(executeFuncSignature) + len(executeContractAddress)
          executionDataDepositor:             bytes    bytes  36 + len(executeFuncSignature) + len(executeContractAddress)                                -  36 + len(executeFuncSignature) + len(executeContractAddress) + len(executionDataDepositor)
          executionData:                      bytes    bytes  36 + len(executeFuncSignature) + len(executeContractAddress) + len(executionDataDepositor)  -  END

          executionData is repacked together with executionDataDepositor address for using it in the target contract.
          If executionData contains dynamic types then it is necessary to keep the offsets correct.
          executionData should be encoded together with a 32-byte address and then passed as a parameter without that address.
          If the target function accepts (address depositor, bytes executionData)
          then a function like the following one can be used:

            function prepareDepositData(bytes calldata executionData) view external returns (bytes memory) {
                bytes memory encoded = abi.encode(address(0), executionData);
                return this.slice(encoded, 32);
            }

            function slice(bytes calldata input, uint256 position) pure public returns (bytes memory) {
                return input[position:];
            }

          After this, the target contract will get the following:
          executeFuncSignature(address executionDataDepositor, bytes executionData)

          Another example: if the target function accepts (address depositor, uint[], address)
          then a function like the following one can be used:

            function prepareDepositData(uint[] calldata uintArray, address addr) view external returns (bytes memory) {
                bytes memory encoded = abi.encode(address(0), uintArray, addr);
                return this.slice(encoded, 32);
            }

          After this, the target contract will get the following:
          executeFuncSignature(address executionDataDepositor, uint[] uintArray, address addr)
     */
    function executeProposal(bytes32 resourceID, bytes calldata data) external onlyBridge returns (bytes memory) {
        uint256        maxFee;
        uint16         lenExecuteFuncSignature;
        bytes4         executeFuncSignature;
        uint8          lenExecuteContractAddress;
        address        executeContractAddress;
        uint8          lenExecutionDataDepositor;
        address        executionDataDepositor;
        bytes   memory executionData;
        
        uint256 pointer = 0;

        maxFee                            = uint256(bytes32(data[:pointer += 32])); 
        lenExecuteFuncSignature           = uint16(bytes2(data[pointer:pointer += 2]));
        lenExecuteFuncSignature.mustBe(4);
        executeFuncSignature              = bytes4(data[pointer:pointer += lenExecuteFuncSignature]);
        lenExecuteContractAddress         = uint8(bytes1(data[pointer:pointer += 1]));
        lenExecuteContractAddress.mustBe(20);
        executeContractAddress            = address(uint160(bytes20(data[pointer:pointer += lenExecuteContractAddress])));
        lenExecutionDataDepositor         = uint8(bytes1(data[pointer:pointer += 1]));
        lenExecutionDataDepositor.mustBe(20);
        executionDataDepositor            = address(uint160(bytes20(data[pointer:pointer += lenExecutionDataDepositor])));
        executionData                     = bytes(data[pointer:]);

        bytes memory callData = abi.encodePacked(executeFuncSignature, abi.encode(executionDataDepositor), executionData);
        (bool success, bytes memory returndata) = executeContractAddress.call{gas: maxFee}(callData);
        return abi.encode(success, returndata);
    }
}
