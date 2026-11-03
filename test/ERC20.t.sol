// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ERC1967Proxy } from "../lib/oz/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { Ethereum } from "../lib/spark-address-registry/src/Ethereum.sol";

import { TokenFuzzChecks } from "../lib/token-tests/src/TokenFuzzChecks.sol";

import { IGrovePrimeVault } from "../src/IGrovePrimeVault.sol";

import { GrovePrimeVault } from "../src/GrovePrimeVault.sol";

contract ERC20Tests is TokenFuzzChecks {

    bytes32 internal OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    address internal admin    = makeAddr("admin");
    address internal operator = makeAddr("operator");

    GrovePrimeVault internal grPrime;

    function setUp() public {
        vm.createSelectFork(getChain("mainnet").rpcUrl, _getBlock());

        grPrime = GrovePrimeVault(
            address(new ERC1967Proxy(
                address(new GrovePrimeVault()),
                abi.encodeCall(
                    IGrovePrimeVault.initialize,
                    (Ethereum.SPARK_VAULT_V2_SPUSDC, "Grove Prime USDC", "grPrime", admin, 1, 1, 1)
                )
            ))
        );

        vm.startPrank(admin);
        grPrime.grantRole(OPERATOR_ROLE, operator);
        grPrime.setVSRBounds(1e27, grPrime.MAX_VSR());
        vm.stopPrank();
    }

    function _getBlock() internal pure returns (uint256) {
        return 26148600;
    }

    function test_erc20() external {
        checkBulkERC20(address(grPrime), "GrovePrimeVault", "Grove Prime USDC", "grPrime", "1", 6);
    }

    function testFuzz_erc20(uint256 amount1, uint256 amount2, uint256 vsr, uint256 warpTime) external {
        amount1  = bound(amount1,  0,    1e36);
        amount2  = bound(amount2,  0,    1e36);
        vsr      = bound(vsr,      1e27, 1.000000012857214317438491659e27);  // 0 to 50% APY
        warpTime = bound(warpTime, 0,    10 days);

        vm.prank(operator);
        grPrime.setVSR(vsr);

        skip(warpTime);

        checkBulkERC20Fuzz({
            _token        : address(grPrime),
            _contractName : "GrovePrimeVault",
            from          : makeAddr("from"),
            to            : makeAddr("to"),
            amount1       : amount1,
            amount2       : amount2
        });
    }

    function test_permit() external {
        uint256 privateKey1 = 0x112233445566;
        uint256 privateKey2 = 0xAABBCCDDEEFF;

        checkBulkPermit(address(grPrime), "GrovePrimeVault", privateKey1, privateKey2);
    }

    function testFuzz_permit(
        uint256 amount,
        uint256 deadline,
        uint256 nonce,
        uint128 privateKey
    )
        external
    {
        amount     = bound(amount,   0,                      1e36);
        deadline   = bound(deadline, vm.getBlockTimestamp(), vm.getBlockTimestamp() + 100 days);
        nonce      = bound(nonce,    0,                      type(uint256).max);

        checkBulkPermitFuzz({
            _token        : address(grPrime),
            _contractName : "GrovePrimeVault",
            privKey       : privateKey,
            to            : makeAddr("to"),
            amount        : amount,
            deadline      : deadline,
            nonce         : nonce
        });
    }

}
