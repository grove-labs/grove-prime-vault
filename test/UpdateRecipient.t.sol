// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { TestBase } from "./TestBase.t.sol";

import { IGrovePrimeVault } from "../src/IGrovePrimeVault.sol";

contract UpdateRecipientTests is TestBase {

    address internal user = makeAddr("user");

    function setUp() public override virtual {
        super.setUp();

        vm.label(user, "user");
    }

    /**********************************************************************************************/
    /*** updateDepositRecipient                                                                 ***/
    /**********************************************************************************************/

    function test_updateDepositRecipient_zeroRecipient() external {
        vm.expectRevert(IGrovePrimeVault.ZeroRecipient.selector);
        vm.prank(user);
        grPrime.updateDepositRecipient(0, address(0));
    }

    function test_updateDepositRecipient_vaultIsRecipient() external {
        vm.expectRevert(IGrovePrimeVault.VaultIsRecipient.selector);
        vm.prank(user);
        grPrime.updateDepositRecipient(0, address(grPrime));
    }

    function test_updateDepositRecipient_invalidRequestIdBoundary() external {
        _setCapacity(0);
        _requestDeposit(user, 1_000_000e18);

        vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
        vm.prank(user);
        grPrime.updateDepositRecipient(1, user);

        vm.prank(user);
        grPrime.updateDepositRecipient(0, user);
    }

    function test_updateDepositRecipient_noRequest() external {
        _requestDeposit(user, 1_000_000e18);  // Request 0 filled instantly

        vm.expectRevert(IGrovePrimeVault.NoRequest.selector);
        vm.prank(user);
        grPrime.updateDepositRecipient(0, user);
    }

    function test_updateDepositRecipient_notRequestOwner() external {
        _setCapacity(0);
        _requestDeposit(user, 1_000_000e18);  // Request 0 queued

        vm.expectRevert(IGrovePrimeVault.NotRequestOwner.selector);
        vm.prank(makeAddr("unauthorized"));
        grPrime.updateDepositRecipient(0, user);
    }

    function test_updateDepositRecipient() external {
        address newRecipient = makeAddr("newRecipient");

        _setCapacity(0);
        _requestDeposit(user, 1_000_000e18);  // Request 0 queued

        _assertDepositRequest(0, user, user, 1_000_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositRecipientUpdated(0, newRecipient);

        vm.prank(user);
        grPrime.updateDepositRecipient(0, newRecipient);

        _assertDepositRequest(0, user, newRecipient, 1_000_000e18 - 1);
    }

    /**********************************************************************************************/
    /*** updateDepositCancellationRecipient                                                     ***/
    /**********************************************************************************************/

    function test_updateDepositCancellationRecipient_zeroRecipient() external {
        vm.expectRevert(IGrovePrimeVault.ZeroRecipient.selector);
        vm.prank(user);
        grPrime.updateDepositCancellationRecipient(0, address(0));
    }

    function test_updateDepositCancellationRecipient_vaultIsRecipient() external {
        vm.expectRevert(IGrovePrimeVault.VaultIsRecipient.selector);
        vm.prank(user);
        grPrime.updateDepositCancellationRecipient(0, address(grPrime));
    }

    function test_updateDepositCancellationRecipient_invalidRequestIdBoundary() external {
        _setCapacity(0);
        _requestDeposit(user, 1_000_000e18);                                         // Request 0 queued
        _requestDepositCancellation(user, 0, sUSDS.convertToShares(1_000_000e18));  // Request 0 cancellation queued

        vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
        vm.prank(user);
        grPrime.updateDepositCancellationRecipient(1, user);

        vm.prank(user);
        grPrime.updateDepositCancellationRecipient(0, user);
    }

    function test_updateDepositCancellationRecipient_noRequest() external {
        _setCapacity(0);
        _requestDeposit(user, 1_000_000e18);                                         // Request 0 queued
        _requestDepositCancellation(user, 0, sUSDS.convertToShares(1_000_000e18));  // Request 0 cancellation queued
        _processPendingDepositCancellations(1);                                     // Request 0 processed

        vm.expectRevert(IGrovePrimeVault.NoRequest.selector);
        vm.prank(user);
        grPrime.updateDepositCancellationRecipient(0, user);
    }

    function test_updateDepositCancellationRecipient_notRequestOwner() external {
        _setCapacity(0);
        _requestDeposit(user, 1_000_000e18);                                         // Request 0 queued
        _requestDepositCancellation(user, 0, sUSDS.convertToShares(1_000_000e18));  // Request 0 cancellation queued

        vm.expectRevert(IGrovePrimeVault.NotRequestOwner.selector);
        vm.prank(makeAddr("unauthorized"));
        grPrime.updateDepositCancellationRecipient(0, user);
    }

    function test_updateDepositCancellationRecipient() external {
        address newRecipient = makeAddr("newRecipient");

        _setCapacity(0);
        _requestDeposit(user, 1_000_000e18);                                         // Request 0 queued
        _requestDepositCancellation(user, 0, sUSDS.convertToShares(1_000_000e18));  // Request 0 cancellation queued

        _assertDepositCancellationRequest(0, user, user, 1_000_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellationRecipientUpdated(0, newRecipient);

        vm.prank(user);
        grPrime.updateDepositCancellationRecipient(0, newRecipient);

        _assertDepositCancellationRequest(0, user, newRecipient, 1_000_000e18 - 1);
    }

    /**********************************************************************************************/
    /*** updateRedeemRecipient                                                                  ***/
    /**********************************************************************************************/

    function test_updateRedeemRecipient_zeroRecipient() external {
        vm.expectRevert(IGrovePrimeVault.ZeroRecipient.selector);
        vm.prank(user);
        grPrime.updateRedeemRecipient(0, address(0));
    }

    function test_updateRedeemRecipient_vaultIsRecipient() external {
        vm.expectRevert(IGrovePrimeVault.VaultIsRecipient.selector);
        vm.prank(user);
        grPrime.updateRedeemRecipient(0, address(grPrime));
    }

    function test_updateRedeemRecipient_invalidRequestIdBoundary() external {
        _requestDeposit(user, 1_000_000e18);  // Request 0 filled instantly
        _requestRedeem(user,  100e18);        // Request 0 redeem queued

        vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
        vm.prank(user);
        grPrime.updateRedeemRecipient(1, user);

        vm.prank(user);
        grPrime.updateRedeemRecipient(0, user);
    }

    function test_updateRedeemRecipient_noRequest() external {
        _requestDeposit(user, 1_000_000e18);  // Request 0 filled instantly
        _requestRedeem(user,  100e18);        // Request 0 redeem queued

        _processPendingRedeems(1);

        vm.expectRevert(IGrovePrimeVault.NoRequest.selector);
        vm.prank(user);
        grPrime.updateRedeemRecipient(0, user);
    }

    function test_updateRedeemRecipient_notRequestOwner() external {
        _requestDeposit(user, 1_000_000e18);  // Request 0 filled instantly
        _requestRedeem(user,  100e18);        // Request 0 redeem queued

        vm.expectRevert(IGrovePrimeVault.NotRequestOwner.selector);
        vm.prank(makeAddr("unauthorized"));
        grPrime.updateRedeemRecipient(0, user);
    }

    function test_updateRedeemRecipient() external {
        address newRecipient = makeAddr("newRecipient");

        _requestDeposit(user, 1_000_000e18);      // Request 0 filled instantly
        _requestRedeem(user,  1_000_000e18 - 1);  // Request 0 redeem queued

        _assertRedeemRequest(0, user, user, 1_000_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.RedeemRecipientUpdated(0, newRecipient);

        vm.prank(user);
        grPrime.updateRedeemRecipient(0, newRecipient);

        _assertRedeemRequest(0, user, newRecipient, 1_000_000e18 - 1);
    }

}
