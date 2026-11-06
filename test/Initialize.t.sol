// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Initializable } from "../lib/oz/contracts/proxy/utils/Initializable.sol";

import { ERC1967Proxy, TestBase, GrovePrimeVault } from "./TestBase.t.sol";

import { IGrovePrimeVault } from "../src/IGrovePrimeVault.sol";

import { GrovePrimeVault } from "../src/GrovePrimeVault.sol";

contract InitializeTests is TestBase {

    address internal deployer = makeAddr("deployer");

    GrovePrimeVault internal implementation;

    function setUp() public override virtual {
        super.setUp();

        vm.prank(deployer);
        implementation = new GrovePrimeVault();
    }

    function _deploy(uint256 minDeposit, uint256 minDepositCancellation, uint256 minRedeem)
        internal
        returns (IGrovePrimeVault)
    {
        return _deploy(minDeposit, minDepositCancellation, minRedeem, true);
    }

    function _deploy(
        uint256 minDeposit,
        uint256 minDepositCancellation,
        uint256 minRedeem,
        bool    allowlistEnabled
    )
        internal
        returns (IGrovePrimeVault)
    {
        return _deploy(
            minDeposit,
            minDepositCancellation,
            minRedeem,
            allowlistEnabled,
            IGrovePrimeVault.TransferMode.AllowlistOnly
        );
    }

    function _deploy(
        uint256                       minDeposit,
        uint256                       minDepositCancellation,
        uint256                       minRedeem,
        bool                          allowlistEnabled,
        IGrovePrimeVault.TransferMode transferMode
    )
        internal
        returns (IGrovePrimeVault)
    {
        vm.prank(deployer);

        return GrovePrimeVault(
            address(new ERC1967Proxy(
                address(implementation),
                abi.encodeCall(
                    IGrovePrimeVault.initialize,
                    (
                        address(sUSDS),
                        "Grove Prime USDS",
                        "grPrime",
                        admin,
                        minDeposit,
                        minDepositCancellation,
                        minRedeem,
                        allowlistEnabled,
                        transferMode
                    )
                )
            ))
        );
    }

    /**********************************************************************************************/
    /*** initialize                                                                             ***/
    /**********************************************************************************************/

    function test_initialize_zeroMinDeposit() external {
        vm.expectRevert(IGrovePrimeVault.ZeroMinDeposit.selector);
        _deploy(0, 0, 0);
    }

    function test_initialize_zeroMinDepositCancellation() external {
        vm.expectRevert(IGrovePrimeVault.ZeroMinDepositCancellation.selector);
        _deploy(1, 0, 0);
    }

    function test_initialize_zeroMinRedeem() external {
        vm.expectRevert(IGrovePrimeVault.ZeroMinRedeem.selector);
        _deploy(1, 1, 0);
    }

    function test_initialize_alreadyInitialized() external {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        grPrime.initialize(
            address(sUSDS),
            "Grove Prime USDS",
            "grPrime",
            admin,
            1,
            1,
            1,
            true,
            IGrovePrimeVault.TransferMode.AllowlistOnly
        );
    }

    function test_initialize_implementationDisabled() external {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(
            address(sUSDS),
            "Grove Prime USDS",
            "grPrime",
            admin,
            1,
            1,
            1,
            true,
            IGrovePrimeVault.TransferMode.AllowlistOnly
        );
    }

    function test_initialize() external {
        address expectedProxy = vm.computeCreateAddress(deployer, vm.getNonce(deployer));

        vm.expectEmit(expectedProxy);
        emit IGrovePrimeVault.Drip(uint192(RAY), 0);

        vm.expectEmit(expectedProxy);
        emit IGrovePrimeVault.VSRSet(expectedProxy, RAY);

        vm.expectEmit(expectedProxy);
        emit IGrovePrimeVault.VSRBoundsSet(expectedProxy, RAY, RAY);

        vm.expectEmit(expectedProxy);
        emit IGrovePrimeVault.MinDepositSet(deployer, MINIMUM_DEPOSIT);

        vm.expectEmit(expectedProxy);
        emit IGrovePrimeVault.MinDepositCancellationSet(deployer, MINIMUM_DEPOSIT_CANCELLATION);

        vm.expectEmit(expectedProxy);
        emit IGrovePrimeVault.MinRedeemSet(deployer, MINIMUM_REDEEM);

        vm.expectEmit(expectedProxy);
        emit IGrovePrimeVault.AllowlistEnabledSet(expectedProxy, true);

        vm.expectEmit(expectedProxy);
        emit IGrovePrimeVault.TransferModeSet(expectedProxy, IGrovePrimeVault.TransferMode.AllowlistOnly);

        IGrovePrimeVault vault = _deploy(MINIMUM_DEPOSIT, MINIMUM_DEPOSIT_CANCELLATION, MINIMUM_REDEEM);

        assertEq(address(vault), expectedProxy);

        assertEq(vault.savings(),  address(sUSDS));
        assertEq(vault.asset(),    address(usds));
        assertEq(vault.name(),     "Grove Prime USDS");
        assertEq(vault.symbol(),   "grPrime");
        assertEq(vault.decimals(), 18);

        assertTrue(vault.hasRole(DEFAULT_ADMIN_ROLE, admin));

        assertEq(vault.chi(),    RAY);
        assertEq(vault.rho(),    vm.getBlockTimestamp());
        assertEq(vault.vsr(),    RAY);
        assertEq(vault.minVSR(), RAY);
        assertEq(vault.maxVSR(), RAY);

        assertEq(vault.minDeposit(),             MINIMUM_DEPOSIT);
        assertEq(vault.minDepositCancellation(), MINIMUM_DEPOSIT_CANCELLATION);
        assertEq(vault.minRedeem(),              MINIMUM_REDEEM);

        assertEq(vault.allowlistEnabled(), true);

        assertEq(uint8(vault.transferMode()), uint8(IGrovePrimeVault.TransferMode.AllowlistOnly));

        assertEq(usds.allowance(address(vault), address(sUSDS)), type(uint256).max);
    }

    function test_initialize_allowlistDisabled() external {
        address expectedProxy = vm.computeCreateAddress(deployer, vm.getNonce(deployer));

        vm.expectEmit(expectedProxy);
        emit IGrovePrimeVault.AllowlistEnabledSet(expectedProxy, false);

        IGrovePrimeVault vault = _deploy(MINIMUM_DEPOSIT, MINIMUM_DEPOSIT_CANCELLATION, MINIMUM_REDEEM, false);

        assertEq(vault.allowlistEnabled(), false);
    }

    function test_initialize_transferModeEnabled() external {
        address expectedProxy = vm.computeCreateAddress(deployer, vm.getNonce(deployer));

        vm.expectEmit(expectedProxy);
        emit IGrovePrimeVault.TransferModeSet(expectedProxy, IGrovePrimeVault.TransferMode.Enabled);

        IGrovePrimeVault vault = _deploy(
            MINIMUM_DEPOSIT,
            MINIMUM_DEPOSIT_CANCELLATION,
            MINIMUM_REDEEM,
            true,
            IGrovePrimeVault.TransferMode.Enabled
        );

        assertEq(uint8(vault.transferMode()), uint8(IGrovePrimeVault.TransferMode.Enabled));
    }

    function test_initialize_transferModeDisabled() external {
        address expectedProxy = vm.computeCreateAddress(deployer, vm.getNonce(deployer));

        vm.expectEmit(expectedProxy);
        emit IGrovePrimeVault.TransferModeSet(expectedProxy, IGrovePrimeVault.TransferMode.Disabled);

        IGrovePrimeVault vault = _deploy(
            MINIMUM_DEPOSIT,
            MINIMUM_DEPOSIT_CANCELLATION,
            MINIMUM_REDEEM,
            true,
            IGrovePrimeVault.TransferMode.Disabled
        );

        assertEq(uint8(vault.transferMode()), uint8(IGrovePrimeVault.TransferMode.Disabled));
    }

}
