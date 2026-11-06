// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IAccessControl } from "../lib/oz/contracts/access/IAccessControl.sol";

import { TestBase } from "./TestBase.t.sol";

import { IGrovePrimeVault } from "../src/IGrovePrimeVault.sol";

contract TransferRestrictionsTests is TestBase {

    IGrovePrimeVault.TransferMode internal constant ENABLED        = IGrovePrimeVault.TransferMode.Enabled;
    IGrovePrimeVault.TransferMode internal constant ALLOWLIST_ONLY = IGrovePrimeVault.TransferMode.AllowlistOnly;
    IGrovePrimeVault.TransferMode internal constant DISABLED       = IGrovePrimeVault.TransferMode.Disabled;

    address internal user         = makeAddr("user");
    address internal receiver     = makeAddr("receiver");
    address internal spender      = makeAddr("spender");
    address internal unauthorized = makeAddr("unauthorized");

    uint256 internal shares;

    function setUp() public override virtual {
        super.setUp();

        _requestDeposit(user, 1_000_000e18);  // Filled instantly

        shares = grPrime.balanceOf(user);

        vm.prank(user);
        grPrime.approve(spender, type(uint256).max);

        _setTransferMode(ALLOWLIST_ONLY);

        vm.label(user,     "user");
        vm.label(receiver, "receiver");
        vm.label(spender,  "spender");
    }

    function _notAuthorized(address account) internal view returns (bytes memory) {
        return abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            account,
            ALLOWLIST_MANAGER_ROLE
        );
    }

    /**********************************************************************************************/
    /*** setTransferMode                                                                        ***/
    /**********************************************************************************************/

    function test_setTransferMode_notAllowlistManager() external {
        vm.expectRevert(_notAuthorized(unauthorized));
        vm.prank(unauthorized);
        grPrime.setTransferMode(ENABLED);
    }

    function test_setTransferMode_adminIsNotAllowlistManager() external {
        vm.expectRevert(_notAuthorized(admin));
        vm.prank(admin);
        grPrime.setTransferMode(ENABLED);
    }

    function test_setTransferMode() external {
        assertEq(uint8(grPrime.transferMode()), uint8(ALLOWLIST_ONLY));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.TransferModeSet(allowlistManager, DISABLED);

        vm.prank(allowlistManager);
        grPrime.setTransferMode(DISABLED);

        assertEq(uint8(grPrime.transferMode()), uint8(DISABLED));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.TransferModeSet(allowlistManager, ENABLED);

        vm.prank(allowlistManager);
        grPrime.setTransferMode(ENABLED);

        assertEq(uint8(grPrime.transferMode()), uint8(ENABLED));
    }

    /**********************************************************************************************/
    /*** setTransferAllowlisted                                                                 ***/
    /**********************************************************************************************/

    function test_setTransferAllowlisted_notAllowlistManager() external {
        vm.expectRevert(_notAuthorized(unauthorized));
        vm.prank(unauthorized);
        grPrime.setTransferAllowlisted(receiver, true);
    }

    function test_setTransferAllowlisted() external {
        assertFalse(grPrime.isTransferAllowlisted(receiver));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.TransferAllowlistUpdated(allowlistManager, receiver, true);

        vm.prank(allowlistManager);
        grPrime.setTransferAllowlisted(receiver, true);

        assertTrue(grPrime.isTransferAllowlisted(receiver));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.TransferAllowlistUpdated(allowlistManager, receiver, false);

        vm.prank(allowlistManager);
        grPrime.setTransferAllowlisted(receiver, false);

        assertFalse(grPrime.isTransferAllowlisted(receiver));
    }

    function test_transferAllowlist_isSeparateFromRecipientAllowlist() external {
        _setAllowlisted(receiver, true);

        assertTrue(grPrime.isMintRedeemAllowlisted(receiver));
        assertFalse(grPrime.isTransferAllowlisted(receiver));

        _setTransferAllowlisted(user, true);

        assertTrue(grPrime.isTransferAllowlisted(user));
        assertFalse(grPrime.isMintRedeemAllowlisted(user));
    }

    /**********************************************************************************************/
    /*** Enabled                                                                                ***/
    /**********************************************************************************************/

    function test_transfer_enabled() external {
        _setTransferMode(ENABLED);

        vm.prank(user);
        grPrime.transfer(receiver, shares);

        assertEq(grPrime.balanceOf(receiver), shares);
    }

    function test_transferFrom_enabled() external {
        _setTransferMode(ENABLED);

        vm.prank(spender);
        grPrime.transferFrom(user, receiver, shares);

        assertEq(grPrime.balanceOf(receiver), shares);
    }

    /**********************************************************************************************/
    /*** AllowlistOnly                                                                          ***/
    /**********************************************************************************************/

    function test_transfer_allowlistOnly_senderNotAllowlisted() external {
        _setTransferAllowlisted(receiver, true);

        vm.expectRevert(IGrovePrimeVault.SenderNotTransferAllowlisted.selector);
        vm.prank(user);
        grPrime.transfer(receiver, shares);
    }

    function test_transfer_allowlistOnly_receiverNotAllowlisted() external {
        _setTransferAllowlisted(user, true);

        vm.expectRevert(IGrovePrimeVault.ReceiverNotTransferAllowlisted.selector);
        vm.prank(user);
        grPrime.transfer(receiver, shares);
    }

    function test_transfer_allowlistOnly_recipientAllowlistDoesNotApply() external {
        _setAllowlisted(user,     true);
        _setAllowlisted(receiver, true);

        vm.expectRevert(IGrovePrimeVault.SenderNotTransferAllowlisted.selector);
        vm.prank(user);
        grPrime.transfer(receiver, shares);
    }

    function test_transfer_allowlistOnly() external {
        _setTransferAllowlisted(user,     true);
        _setTransferAllowlisted(receiver, true);

        vm.prank(user);
        grPrime.transfer(receiver, shares);

        assertEq(grPrime.balanceOf(user),     0);
        assertEq(grPrime.balanceOf(receiver), shares);
    }

    function test_transferFrom_allowlistOnly_senderNotAllowlisted() external {
        _setTransferAllowlisted(spender,  true);
        _setTransferAllowlisted(receiver, true);

        vm.expectRevert(IGrovePrimeVault.SenderNotTransferAllowlisted.selector);
        vm.prank(spender);
        grPrime.transferFrom(user, receiver, shares);
    }

    function test_transferFrom_allowlistOnly_receiverNotAllowlisted() external {
        _setTransferAllowlisted(user,    true);
        _setTransferAllowlisted(spender, true);

        vm.expectRevert(IGrovePrimeVault.ReceiverNotTransferAllowlisted.selector);
        vm.prank(spender);
        grPrime.transferFrom(user, receiver, shares);
    }

    function test_transferFrom_allowlistOnly_spenderNotChecked() external {
        _setTransferAllowlisted(user,     true);
        _setTransferAllowlisted(receiver, true);

        assertFalse(grPrime.isTransferAllowlisted(spender));

        vm.prank(spender);
        grPrime.transferFrom(user, receiver, shares);

        assertEq(grPrime.balanceOf(receiver), shares);
    }

    function test_transfer_allowlistOnly_senderRemoved() external {
        _setTransferAllowlisted(user,     true);
        _setTransferAllowlisted(receiver, true);
        _setTransferAllowlisted(user,     false);

        vm.expectRevert(IGrovePrimeVault.SenderNotTransferAllowlisted.selector);
        vm.prank(user);
        grPrime.transfer(receiver, shares);
    }

    /**********************************************************************************************/
    /*** Disabled                                                                               ***/
    /**********************************************************************************************/

    function test_transfer_disabled() external {
        _setTransferAllowlisted(user,     true);
        _setTransferAllowlisted(receiver, true);
        _setTransferMode(DISABLED);

        vm.expectRevert(IGrovePrimeVault.TransfersDisabled.selector);
        vm.prank(user);
        grPrime.transfer(receiver, shares);
    }

    function test_transferFrom_disabled() external {
        _setTransferAllowlisted(user,     true);
        _setTransferAllowlisted(receiver, true);
        _setTransferMode(DISABLED);

        vm.expectRevert(IGrovePrimeVault.TransfersDisabled.selector);
        vm.prank(spender);
        grPrime.transferFrom(user, receiver, shares);
    }

    function test_approve_disabled() external {
        _setTransferMode(DISABLED);

        vm.prank(user);
        grPrime.approve(receiver, shares);

        assertEq(grPrime.allowance(user, receiver), shares);
    }

    /**********************************************************************************************/
    /*** Mints and redeems are unaffected                                                       ***/
    /**********************************************************************************************/

    function test_requestDeposit_mintsWhileDisabled() external {
        _setTransferMode(DISABLED);

        _requestDeposit(user, receiver, 1_000_000e18);  // Filled instantly

        assertGt(grPrime.balanceOf(receiver), 0);
    }

    function test_requestDeposit_mintsToNonTransferAllowlisted() external {
        _requestDeposit(user, receiver, 1_000_000e18);  // Filled instantly

        assertFalse(grPrime.isTransferAllowlisted(receiver));
        assertGt(grPrime.balanceOf(receiver), 0);
    }

    function test_requestRedeem_disabled() external {
        _setTransferMode(DISABLED);

        _requestRedeem(user, receiver, shares);  // Request 0 redeem queued

        assertEq(grPrime.balanceOf(user), 0);

        _processPendingRedeems();

        assertEq(grPrime.pendingRedeemShares(), 0);
        assertApproxEqAbs(usds.balanceOf(receiver), 1_000_000e18, 2);
    }

    function test_requestRedeem_allowlistOnly_notTransferAllowlisted() external {
        assertFalse(grPrime.isTransferAllowlisted(user));

        _requestRedeem(user, shares);  // Request 0 redeem queued

        assertEq(grPrime.balanceOf(user), 0);

        _processPendingRedeems();

        assertEq(grPrime.pendingRedeemShares(), 0);
        assertApproxEqAbs(usds.balanceOf(user), 1_000_000e18, 2);
    }

}
