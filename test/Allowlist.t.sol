// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IAccessControl } from "../lib/oz/contracts/access/IAccessControl.sol";

import { TestBase } from "./TestBase.t.sol";

import { IGrovePrimeVault } from "../src/IGrovePrimeVault.sol";

contract AllowlistTests is TestBase {

    address internal user         = makeAddr("user");
    address internal recipient    = makeAddr("recipient");
    address internal unauthorized = makeAddr("unauthorized");

    function setUp() public override virtual {
        super.setUp();

        _setAllowlistEnabled(true);

        vm.label(user,      "user");
        vm.label(recipient, "recipient");
    }

    function _notAuthorized(address account) internal view returns (bytes memory) {
        return abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            account,
            ALLOWLIST_MANAGER_ROLE
        );
    }

    /**********************************************************************************************/
    /*** setAllowlistEnabled                                                                    ***/
    /**********************************************************************************************/

    function test_setAllowlistEnabled_notAllowlistManager() external {
        vm.expectRevert(_notAuthorized(unauthorized));
        vm.prank(unauthorized);
        grPrime.setAllowlistEnabled(false);
    }

    function test_setAllowlistEnabled_adminIsNotAllowlistManager() external {
        vm.expectRevert(_notAuthorized(admin));
        vm.prank(admin);
        grPrime.setAllowlistEnabled(false);
    }

    function test_setAllowlistEnabled() external {
        assertTrue(grPrime.allowlistEnabled());

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.AllowlistEnabledSet(allowlistManager, false);

        vm.prank(allowlistManager);
        grPrime.setAllowlistEnabled(false);

        assertFalse(grPrime.allowlistEnabled());

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.AllowlistEnabledSet(allowlistManager, true);

        vm.prank(allowlistManager);
        grPrime.setAllowlistEnabled(true);

        assertTrue(grPrime.allowlistEnabled());
    }

    /**********************************************************************************************/
    /*** setAllowlisted                                                                         ***/
    /**********************************************************************************************/

    function test_setAllowlisted_notAllowlistManager() external {
        vm.expectRevert(_notAuthorized(unauthorized));
        vm.prank(unauthorized);
        grPrime.setAllowlisted(recipient, true);
    }

    function test_setAllowlisted() external {
        assertFalse(grPrime.isMintRedeemAllowlisted(recipient));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.AllowlistUpdated(allowlistManager, recipient, true);

        vm.prank(allowlistManager);
        grPrime.setAllowlisted(recipient, true);

        assertTrue(grPrime.isMintRedeemAllowlisted(recipient));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.AllowlistUpdated(allowlistManager, recipient, false);

        vm.prank(allowlistManager);
        grPrime.setAllowlisted(recipient, false);

        assertFalse(grPrime.isMintRedeemAllowlisted(recipient));
    }

    function test_setAllowlisted_worksWhileDisabled() external {
        _setAllowlistEnabled(false);
        _setAllowlisted(recipient, true);

        assertTrue(grPrime.isMintRedeemAllowlisted(recipient));
    }

    /**********************************************************************************************/
    /*** requestDeposit                                                                         ***/
    /**********************************************************************************************/

    function test_requestDeposit_recipientNotAllowlisted() external {
        deal(address(usds), user, 1_000_000e18);

        vm.startPrank(user);
        usds.approve(address(grPrime), 1_000_000e18);

        vm.expectRevert(IGrovePrimeVault.RecipientNotAllowlisted.selector);
        grPrime.requestDeposit(1_000_000e18, recipient, 0);
        vm.stopPrank();
    }

    function test_requestDeposit_recipientRemovedFromAllowlist() external {
        _setAllowlisted(recipient, true);
        _setAllowlisted(recipient, false);

        deal(address(usds), user, 1_000_000e18);

        vm.startPrank(user);
        usds.approve(address(grPrime), 1_000_000e18);

        vm.expectRevert(IGrovePrimeVault.RecipientNotAllowlisted.selector);
        grPrime.requestDeposit(1_000_000e18, recipient, 0);
        vm.stopPrank();
    }

    function test_requestDeposit_onlyRecipientIsChecked() external {
        _setAllowlisted(recipient, true);

        assertFalse(grPrime.isMintRedeemAllowlisted(user));

        _requestDeposit(user, recipient, 1_000_000e18);  // Filled instantly

        assertEq(grPrime.balanceOf(user), 0);
        assertGt(grPrime.balanceOf(recipient), 0);
    }

    function test_requestDeposit_allowlistedDepositorStillNeedsAllowlistedRecipient() external {
        _setAllowlisted(user, true);

        deal(address(usds), user, 1_000_000e18);

        vm.startPrank(user);
        usds.approve(address(grPrime), 1_000_000e18);

        vm.expectRevert(IGrovePrimeVault.RecipientNotAllowlisted.selector);
        grPrime.requestDeposit(1_000_000e18, recipient, 0);
        vm.stopPrank();
    }

    function test_requestDeposit_allowlistDisabled() external {
        _setAllowlistEnabled(false);

        assertFalse(grPrime.isMintRedeemAllowlisted(recipient));

        _requestDeposit(user, recipient, 1_000_000e18);  // Filled instantly

        assertGt(grPrime.balanceOf(recipient), 0);
    }

    /**********************************************************************************************/
    /*** updateDepositRecipient                                                                 ***/
    /**********************************************************************************************/

    function test_updateDepositRecipient_recipientNotAllowlisted() external {
        _setAllowlisted(user, true);
        _setCapacity(0);
        _requestDeposit(user, 1_000_000e18);  // Request 0 queued

        vm.expectRevert(IGrovePrimeVault.RecipientNotAllowlisted.selector);
        vm.prank(user);
        grPrime.updateDepositRecipient(0, recipient);
    }

    function test_updateDepositRecipient_allowlisted() external {
        _setAllowlisted(user,      true);
        _setAllowlisted(recipient, true);
        _setCapacity(0);
        _requestDeposit(user, 1_000_000e18);  // Request 0 queued

        vm.prank(user);
        grPrime.updateDepositRecipient(0, recipient);

        _assertDepositRequest(0, user, recipient, 1_000_000e18 - 1);
    }

    function test_updateDepositRecipient_allowlistDisabled() external {
        _setAllowlisted(user, true);
        _setCapacity(0);
        _requestDeposit(user, 1_000_000e18);  // Request 0 queued

        _setAllowlistEnabled(false);

        vm.prank(user);
        grPrime.updateDepositRecipient(0, recipient);

        _assertDepositRequest(0, user, recipient, 1_000_000e18 - 1);
    }

    /**********************************************************************************************/
    /*** Queued requests are not re-checked                                                     ***/
    /**********************************************************************************************/

    function test_processPendingDeposits_recipientRemovedAfterRequest() external {
        _setAllowlisted(recipient, true);
        _setCapacity(0);
        _requestDeposit(user, recipient, 1_000_000e18);  // Request 0 queued

        _setAllowlisted(recipient, false);
        _setCapacity(VAULT_CAPACITY);

        _processPendingDeposits();

        assertGt(grPrime.balanceOf(recipient), 0);
    }

    function test_processPendingDeposits_allowlistEnabledAfterRequest() external {
        _setAllowlistEnabled(false);
        _setCapacity(0);
        _requestDeposit(user, recipient, 1_000_000e18);  // Request 0 queued

        _setAllowlistEnabled(true);
        _setCapacity(VAULT_CAPACITY);

        _processPendingDeposits();

        assertGt(grPrime.balanceOf(recipient), 0);
    }

    /**********************************************************************************************/
    /*** requestRedeem                                                                          ***/
    /**********************************************************************************************/

    function test_requestRedeem_recipientNotAllowlisted() external {
        _setAllowlisted(user, true);
        _requestDeposit(user, 1_000_000e18);  // Filled instantly

        uint256 shares = grPrime.balanceOf(user);

        vm.expectRevert(IGrovePrimeVault.RecipientNotAllowlisted.selector);
        vm.prank(user);
        grPrime.requestRedeem(shares, recipient);
    }

    function test_requestRedeem_onlyRecipientIsChecked() external {
        _setAllowlisted(user, true);
        _requestDeposit(user, 1_000_000e18);  // Filled instantly

        _setAllowlisted(user,      false);
        _setAllowlisted(recipient, true);

        _requestRedeem(user, recipient, grPrime.balanceOf(user));

        _assertRedeemRequest(0, user, recipient, 1_000_000e18 - 1);
    }

    function test_requestRedeem_allowlistDisabled() external {
        _setAllowlisted(user, true);
        _requestDeposit(user, 1_000_000e18);  // Filled instantly

        _setAllowlistEnabled(false);

        _requestRedeem(user, recipient, grPrime.balanceOf(user));

        _assertRedeemRequest(0, user, recipient, 1_000_000e18 - 1);
    }

    /**********************************************************************************************/
    /*** updateRedeemRecipient                                                                  ***/
    /**********************************************************************************************/

    function test_updateRedeemRecipient_recipientNotAllowlisted() external {
        _setAllowlisted(user, true);
        _requestDeposit(user, 1_000_000e18);            // Filled instantly
        _requestRedeem(user, grPrime.balanceOf(user));  // Request 0 redeem queued

        vm.expectRevert(IGrovePrimeVault.RecipientNotAllowlisted.selector);
        vm.prank(user);
        grPrime.updateRedeemRecipient(0, recipient);
    }

    function test_updateRedeemRecipient_allowlisted() external {
        _setAllowlisted(user,      true);
        _setAllowlisted(recipient, true);
        _requestDeposit(user, 1_000_000e18);            // Filled instantly
        _requestRedeem(user, grPrime.balanceOf(user));  // Request 0 redeem queued

        vm.prank(user);
        grPrime.updateRedeemRecipient(0, recipient);

        _assertRedeemRequest(0, user, recipient, 1_000_000e18 - 1);
    }

    function test_updateRedeemRecipient_allowlistDisabled() external {
        _setAllowlisted(user, true);
        _requestDeposit(user, 1_000_000e18);            // Filled instantly
        _requestRedeem(user, grPrime.balanceOf(user));  // Request 0 redeem queued

        _setAllowlistEnabled(false);

        vm.prank(user);
        grPrime.updateRedeemRecipient(0, recipient);

        _assertRedeemRequest(0, user, recipient, 1_000_000e18 - 1);
    }

    /**********************************************************************************************/
    /*** Queued redeem requests are not re-checked                                              ***/
    /**********************************************************************************************/

    function test_processPendingRedeems_recipientRemovedAfterRequest() external {
        _setAllowlisted(user,      true);
        _setAllowlisted(recipient, true);
        _requestDeposit(user, 1_000_000e18);                       // Filled instantly
        _requestRedeem(user, recipient, grPrime.balanceOf(user));  // Request 0 redeem queued

        _setAllowlisted(recipient, false);

        _processPendingRedeems();

        assertEq(grPrime.pendingRedeemShares(), 0);
        assertApproxEqAbs(usds.balanceOf(recipient), 1_000_000e18, 2);
    }

    function test_processPendingRedeems_allowlistEnabledAfterRequest() external {
        _setAllowlistEnabled(false);
        _requestDeposit(user, 1_000_000e18);                       // Filled instantly
        _requestRedeem(user, recipient, grPrime.balanceOf(user));  // Request 0 redeem queued

        _setAllowlistEnabled(true);

        _processPendingRedeems();

        assertEq(grPrime.pendingRedeemShares(), 0);
        assertApproxEqAbs(usds.balanceOf(recipient), 1_000_000e18, 2);
    }

    /**********************************************************************************************/
    /*** Other paths are unaffected                                                             ***/
    /**********************************************************************************************/

    function test_transfer_toNonAllowlisted() external {
        _setAllowlisted(user, true);
        _requestDeposit(user, 1_000_000e18);  // Filled instantly

        uint256 shares = grPrime.balanceOf(user);

        vm.prank(user);
        grPrime.transfer(recipient, shares);

        assertEq(grPrime.balanceOf(recipient), shares);
    }

    function test_requestDepositCancellation_toNonAllowlisted() external {
        _setAllowlisted(user, true);
        _setCapacity(0);
        _requestDeposit(user, 1_000_000e18);  // Request 0 queued

        _requestDepositCancellation(user, 0, recipient, sUSDS.convertToShares(1_000_000e18));

        _assertDepositCancellationRequest(0, user, recipient, 1_000_000e18 - 1);
    }

}
