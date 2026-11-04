// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IAccessControl } from "../lib/oz/contracts/access/IAccessControl.sol";

import {
    IAccessControlEnumerable
} from "../lib/oz/contracts/access/extensions/IAccessControlEnumerable.sol";

import { IERC165 } from "../lib/oz/contracts/utils/introspection/IERC165.sol";

import { TestBase, ISavingsLike } from "./TestBase.t.sol";

import { IGrovePrimeVault } from "../src/IGrovePrimeVault.sol";

abstract contract GettersTestBase is TestBase {

    uint16 internal constant REFERRAL = type(uint16).max;

    address internal owner1 = makeAddr("owner1");
    address internal owner2 = makeAddr("owner2");
    address internal owner3 = makeAddr("owner3");

    address internal recipient1 = makeAddr("recipient1");
    address internal recipient2 = makeAddr("recipient2");
    address internal recipient3 = makeAddr("recipient3");

    function setUp() public virtual override {
        super.setUp();

        vm.label(owner1, "owner1");
        vm.label(owner2, "owner2");
        vm.label(owner3, "owner3");

        vm.label(recipient1, "recipient1");
        vm.label(recipient2, "recipient2");
        vm.label(recipient3, "recipient3");
    }

}

contract PendingDepositRequestTests is GettersTestBase {

    function setUp() public override {
        super.setUp();

        _setCapacity(0);
    }

    /**********************************************************************************************/
    /*** pendingDepositRequestsLength                                                           ***/
    /**********************************************************************************************/

    function test_pendingDepositRequestsLength() external {
        assertEq(grPrime.pendingDepositRequestsLength(), 0);

        _requestDeposit(owner1, recipient1, 1_000e18);

        assertEq(grPrime.pendingDepositRequestsLength(), 1);

        _requestDeposit(owner1, recipient1, 1_000e18);

        assertEq(grPrime.pendingDepositRequestsLength(), 2);

        _setCapacity(VAULT_CAPACITY);
        _processPendingDeposits(type(uint256).max, 1);

        assertEq(grPrime.pendingDepositRequestsLength(), 1);

        _processPendingDeposits(type(uint256).max, 1);

        assertEq(grPrime.pendingDepositRequestsLength(), 0);
    }

    /**********************************************************************************************/
    /*** getPendingDepositRequest                                                               ***/
    /**********************************************************************************************/

    function test_getPendingDepositRequest_idBeforeFirstPendingBoundary() external {
        _requestDeposit(owner1, recipient1, 1_000e18);
        _requestDeposit(owner2, recipient2, 2_000e18);

        _setCapacity(VAULT_CAPACITY);
        _processPendingDeposits(1);

        vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
        grPrime.getPendingDepositRequest(0);

        grPrime.getPendingDepositRequest(1);
    }

    function test_getPendingDepositRequest_idAfterQueueBoundary() external {
        _requestDeposit(owner1, recipient1, 1_000e18);

        vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
        grPrime.getPendingDepositRequest(1);

        grPrime.getPendingDepositRequest(0);
    }

    function test_getPendingDepositRequest() external {
        _requestDeposit(owner1, recipient1, 1_000e18);
        _requestDeposit(owner2, recipient2, 2_000e18);

        _assertDepositRequest(0, owner1, recipient1, 1_000e18 - 1);
        _assertDepositRequest(1, owner2, recipient2, 2_000e18 - 1);
    }

    function test_getPendingDepositRequest_partialFill() external {
        _requestDeposit(owner1, recipient1, 1_000e18);

        _setCapacity(VAULT_CAPACITY);
        _processPendingDeposits(sUSDS.convertToShares(1_000e18) / 4, 1);

        _assertDepositRequest(0, owner1, recipient1, 750e18);
    }

    /**********************************************************************************************/
    /*** pendingDepositRequests                                                                 ***/
    /**********************************************************************************************/

    function test_pendingDepositRequests_noRequests() external view {
        assertEq(grPrime.pendingDepositRequests().length, 0);
    }

    function test_pendingDepositRequests() external {
        _requestDeposit(owner1, recipient1, 1_000e18);
        _requestDeposit(owner2, recipient2, 2_000e18);
        _requestDeposit(owner3, recipient3, 3_000e18);

        IGrovePrimeVault.Request[] memory requests = grPrime.pendingDepositRequests();

        assertEq(requests.length, 3);

        _assertDepositRequest(requests[0], owner1, recipient1, 1_000e18 - 1);
        _assertDepositRequest(requests[1], owner2, recipient2, 2_000e18 - 1);
        _assertDepositRequest(requests[2], owner3, recipient3, 3_000e18 - 1);
    }

    function test_pendingDepositRequests_someProcessed() external {
        _requestDeposit(owner1, recipient1, 1_000e18);
        _requestDeposit(owner2, recipient2, 2_000e18);
        _requestDeposit(owner3, recipient3, 3_000e18);

        _setCapacity(VAULT_CAPACITY);
        _processPendingDeposits(type(uint256).max, 2);

        IGrovePrimeVault.Request[] memory requests = grPrime.pendingDepositRequests();

        assertEq(requests.length, 1);

        _assertDepositRequest(requests[0], owner3, recipient3, 3_000e18 - 1);
    }

    function test_pendingDepositRequests_allProcessed() external {
        _requestDeposit(owner1, recipient1, 1_000e18);
        _requestDeposit(owner2, recipient2, 2_000e18);

        _setCapacity(VAULT_CAPACITY);
        _processPendingDeposits(type(uint256).max, type(uint256).max);

        assertEq(grPrime.pendingDepositRequests().length, 0);
    }

    function test_pendingDepositRequests_partialFill() external {
        _requestDeposit(owner1, recipient1, 1_000e18);
        _requestDeposit(owner2, recipient2, 2_000e18);

        _setCapacity(VAULT_CAPACITY);
        _processPendingDeposits(sUSDS.convertToShares(1_000e18) / 4, type(uint256).max);

        IGrovePrimeVault.Request[] memory requests = grPrime.pendingDepositRequests();

        assertEq(requests.length, 2);

        _assertDepositRequest(requests[0], owner1, recipient1, 750e18);
        _assertDepositRequest(requests[1], owner2, recipient2, 2_000e18 - 1);
    }

    function test_pendingDepositRequests_cancelledRequest() external {
        _requestDeposit(owner1, recipient1, 1_000e18);
        _requestDeposit(owner2, recipient2, 2_000e18);
        _requestDeposit(owner3, recipient3, 3_000e18);

        _requestDepositCancellation(owner2, 1, recipient2, sUSDS.convertToShares(2_000e18));

        IGrovePrimeVault.Request[] memory requests = grPrime.pendingDepositRequests();

        assertEq(requests.length, 3);

        _assertDepositRequest(requests[0], owner1, recipient1, 1_000e18 - 1);
        _assertEmptyRequest(requests[1]);
        _assertDepositRequest(requests[2], owner3, recipient3, 3_000e18 - 1);
    }

    /**********************************************************************************************/
    /*** getPendingDepositRequests                                                              ***/
    /**********************************************************************************************/

    function test_getPendingDepositRequests_startIdTooSmallBoundary() external {
        _requestDeposit(owner1, recipient1, 1_000e18);
        _requestDeposit(owner2, recipient2, 2_000e18);

        _setCapacity(VAULT_CAPACITY);
        _processPendingDeposits(type(uint256).max, 1);

        vm.expectRevert(IGrovePrimeVault.StartIdTooSmall.selector);
        grPrime.getPendingDepositRequests(0, 1);

        grPrime.getPendingDepositRequests(1, 1);
    }

    function test_getPendingDepositRequests_startIdTooLargeBoundary() external {
        _requestDeposit(owner1, recipient1, 1_000e18);

        vm.expectRevert(IGrovePrimeVault.StartIdTooLarge.selector);
        grPrime.getPendingDepositRequests(2, 0);

        grPrime.getPendingDepositRequests(1, 0);
    }

    function test_getPendingDepositRequests_zeroLength() external view {
        assertEq(grPrime.getPendingDepositRequests(0, 0).length, 0);
    }

    function test_getPendingDepositRequests_range() external {
        _requestDeposit(owner1, recipient1, 1_000e18);
        _requestDeposit(owner2, recipient2, 2_000e18);
        _requestDeposit(owner3, recipient3, 3_000e18);

        IGrovePrimeVault.Request[] memory requests = grPrime.getPendingDepositRequests(0, 3);

        assertEq(requests.length, 3);

        _assertDepositRequest(requests[0], owner1, recipient1, 1_000e18 - 1);
        _assertDepositRequest(requests[1], owner2, recipient2, 2_000e18 - 1);
        _assertDepositRequest(requests[2], owner3, recipient3, 3_000e18 - 1);

        requests = grPrime.getPendingDepositRequests(1, 2);

        assertEq(requests.length, 2);

        _assertDepositRequest(requests[0], owner2, recipient2, 2_000e18 - 1);
        _assertDepositRequest(requests[1], owner3, recipient3, 3_000e18 - 1);
    }

    function test_getPendingDepositRequests_clamping() external {
        _requestDeposit(owner1, recipient1, 1_000e18);
        _requestDeposit(owner2, recipient2, 2_000e18);

        assertEq(grPrime.getPendingDepositRequests(0, 3).length, 2);
    }

}

contract PendingDepositCancellationRequestTests is GettersTestBase {

    function setUp() public override {
        super.setUp();

        _setCapacity(0);
    }

    /**********************************************************************************************/
    /*** pendingDepositCancellationRequestsLength                                               ***/
    /**********************************************************************************************/

    function test_pendingDepositCancellationRequestsLength() external {
        _requestDeposit(owner1, recipient1, 1_000e18);
        _requestDeposit(owner2, recipient2, 2_000e18);

        assertEq(grPrime.pendingDepositCancellationRequestsLength(), 0);

        _requestDepositCancellation(owner1, 0, recipient1, sUSDS.convertToShares(1_000e18));

        assertEq(grPrime.pendingDepositCancellationRequestsLength(), 1);

        _requestDepositCancellation(owner2, 1, recipient2, sUSDS.convertToShares(2_000e18));

        assertEq(grPrime.pendingDepositCancellationRequestsLength(), 2);

        _processPendingDepositCancellations(type(uint256).max, 1);

        assertEq(grPrime.pendingDepositCancellationRequestsLength(), 1);

        _processPendingDepositCancellations(type(uint256).max, 1);

        assertEq(grPrime.pendingDepositCancellationRequestsLength(), 0);
    }

    /**********************************************************************************************/
    /*** getPendingDepositCancellationRequest                                                   ***/
    /**********************************************************************************************/

    function test_getPendingDepositCancellationRequest_idBeforeFirstPendingBoundary() external {
        _requestDeposit(owner1, recipient1, 1_000e18);
        _requestDeposit(owner2, recipient2, 2_000e18);

        _requestDepositCancellation(owner1, 0, recipient1, sUSDS.convertToShares(1_000e18));
        _requestDepositCancellation(owner2, 1, recipient2, sUSDS.convertToShares(2_000e18));

        _setCapacity(VAULT_CAPACITY);
        _processPendingDepositCancellations(type(uint256).max, 1);

        vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
        grPrime.getPendingDepositCancellationRequest(0);

        grPrime.getPendingDepositCancellationRequest(1);
    }

    function test_getPendingDepositCancellationRequest_idAfterQueueBoundary() external {
        _requestDeposit(owner1, recipient1, 1_000e18);
        _requestDepositCancellation(owner1, 0, recipient1, sUSDS.convertToShares(1_000e18));

        vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
        grPrime.getPendingDepositCancellationRequest(1);

        grPrime.getPendingDepositCancellationRequest(0);
    }

    function test_getPendingDepositCancellationRequest() external {
        _requestDeposit(owner1, recipient1, 1_000e18);
        _requestDeposit(owner2, recipient2, 2_000e18);

        _requestDepositCancellation(owner1, 0, recipient1, sUSDS.convertToShares(1_000e18));
        _requestDepositCancellation(owner2, 1, recipient2, sUSDS.convertToShares(2_000e18));

        _assertDepositCancellationRequest(0, owner1, recipient1, 1_000e18 - 1);
        _assertDepositCancellationRequest(1, owner2, recipient2, 2_000e18 - 1);
    }

    function test_getPendingDepositCancellationRequest_partialFill() external {
        _requestDeposit(owner1, recipient1, 1_000e18);
        _requestDeposit(owner2, recipient2, 2_000e18);

        _requestDepositCancellation(owner1, 0, recipient1, sUSDS.convertToShares(1_000e18));
        _requestDepositCancellation(owner2, 1, recipient2, sUSDS.convertToShares(2_000e18));

        _setCapacity(VAULT_CAPACITY);

        _processPendingDepositCancellations(
            sUSDS.convertToShares(1_000e18) + sUSDS.convertToShares(2_000e18) / 4,
            2
        );

        _assertDepositCancellationRequest(1, owner2, recipient2, 1_500e18);
    }

    /**********************************************************************************************/
    /*** pendingDepositCancellationRequests                                                     ***/
    /**********************************************************************************************/

    function test_pendingDepositCancellationRequests_noRequests() external view {
        assertEq(grPrime.pendingDepositCancellationRequests().length, 0);
    }

    function test_pendingDepositCancellationRequests() external {
        _requestDeposit(owner1, recipient1, 1_000e18);
        _requestDeposit(owner2, recipient2, 2_000e18);
        _requestDeposit(owner3, recipient3, 3_000e18);

        _requestDepositCancellation(owner1, 0, recipient1, sUSDS.convertToShares(1_000e18));
        _requestDepositCancellation(owner2, 1, recipient2, sUSDS.convertToShares(2_000e18));
        _requestDepositCancellation(owner3, 2, recipient3, sUSDS.convertToShares(3_000e18));

        IGrovePrimeVault.Request[] memory requests = grPrime.pendingDepositCancellationRequests();

        assertEq(requests.length, 3);

        _assertDepositCancellationRequest(requests[0], owner1, recipient1, 1_000e18 - 1);
        _assertDepositCancellationRequest(requests[1], owner2, recipient2, 2_000e18 - 1);
        _assertDepositCancellationRequest(requests[2], owner3, recipient3, 3_000e18 - 1);
    }

    function test_pendingDepositCancellationRequests_someProcessed() external {
        _requestDeposit(owner1, recipient1, 1_000e18);
        _requestDeposit(owner2, recipient2, 2_000e18);
        _requestDeposit(owner3, recipient3, 3_000e18);

        _requestDepositCancellation(owner1, 0, recipient1, sUSDS.convertToShares(1_000e18));
        _requestDepositCancellation(owner2, 1, recipient2, sUSDS.convertToShares(2_000e18));
        _requestDepositCancellation(owner3, 2, recipient3, sUSDS.convertToShares(3_000e18));

        _setCapacity(VAULT_CAPACITY);
        _processPendingDepositCancellations(type(uint256).max, 2);

        IGrovePrimeVault.Request[] memory requests = grPrime.pendingDepositCancellationRequests();

        assertEq(requests.length, 1);

        _assertDepositCancellationRequest(requests[0], owner3, recipient3, 3_000e18 - 1);
    }

    function test_pendingDepositCancellationRequests_allProcessed() external {
        _requestDeposit(owner1, recipient1, 1_000e18);
        _requestDeposit(owner2, recipient2, 2_000e18);

        _requestDepositCancellation(owner1, 0, recipient1, sUSDS.convertToShares(1_000e18));
        _requestDepositCancellation(owner2, 1, recipient2, sUSDS.convertToShares(2_000e18));

        _setCapacity(VAULT_CAPACITY);
        _processPendingDepositCancellations(type(uint256).max, 2);

        assertEq(grPrime.pendingDepositCancellationRequests().length, 0);
    }

    function test_pendingDepositCancellationRequests_partialFill() external {
        _requestDeposit(owner1, recipient1, 1_000e18);
        _requestDeposit(owner2, recipient2, 2_000e18);

        _requestDepositCancellation(owner1, 0, recipient1, sUSDS.convertToShares(1_000e18));
        _requestDepositCancellation(owner2, 1, recipient2, sUSDS.convertToShares(2_000e18));

        _setCapacity(VAULT_CAPACITY);
        _processPendingDepositCancellations(sUSDS.convertToShares(1_000e18) / 4, 1);

        IGrovePrimeVault.Request[] memory requests = grPrime.pendingDepositCancellationRequests();

        assertEq(requests.length, 2);

        _assertDepositCancellationRequest(requests[0], owner1, recipient1, 750e18);
        _assertDepositCancellationRequest(requests[1], owner2, recipient2, 2_000e18 - 1);
    }

    /**********************************************************************************************/
    /*** getPendingDepositCancellationRequests                                                  ***/
    /**********************************************************************************************/

    function test_getPendingDepositCancellationRequests_startIdTooSmallBoundary() external {
        _requestDeposit(owner1, recipient1, 1_000e18);
        _requestDeposit(owner2, recipient2, 2_000e18);

        _requestDepositCancellation(owner1, 0, recipient1, sUSDS.convertToShares(1_000e18));
        _requestDepositCancellation(owner2, 1, recipient2, sUSDS.convertToShares(2_000e18));

        _setCapacity(VAULT_CAPACITY);
        _processPendingDepositCancellations(type(uint256).max, 1);

        vm.expectRevert(IGrovePrimeVault.StartIdTooSmall.selector);
        grPrime.getPendingDepositCancellationRequests(0, 1);

        grPrime.getPendingDepositCancellationRequests(1, 1);
    }

    function test_getPendingDepositCancellationRequests_startIdTooLargeBoundary() external {
        _requestDeposit(owner1, recipient1, 1_000e18);

        _requestDepositCancellation(owner1, 0, recipient1, sUSDS.convertToShares(1_000e18));

        vm.expectRevert(IGrovePrimeVault.StartIdTooLarge.selector);
        grPrime.getPendingDepositCancellationRequests(2, 0);

        grPrime.getPendingDepositCancellationRequests(1, 0);
    }

    function test_getPendingDepositCancellationRequests_zeroLength() external view {
        assertEq(grPrime.getPendingDepositCancellationRequests(0, 0).length, 0);
    }

    function test_getPendingDepositCancellationRequests_range() external {
        _requestDeposit(owner1, recipient1, 1_000e18);
        _requestDeposit(owner2, recipient2, 2_000e18);
        _requestDeposit(owner3, recipient3, 3_000e18);

        _requestDepositCancellation(owner1, 0, recipient1, sUSDS.convertToShares(1_000e18));
        _requestDepositCancellation(owner2, 1, recipient2, sUSDS.convertToShares(2_000e18));
        _requestDepositCancellation(owner3, 2, recipient3, sUSDS.convertToShares(3_000e18));

        IGrovePrimeVault.Request[] memory requests
            = grPrime.getPendingDepositCancellationRequests(0, 3);

        assertEq(requests.length, 3);

        _assertDepositCancellationRequest(requests[0], owner1, recipient1, 1_000e18 - 1);
        _assertDepositCancellationRequest(requests[1], owner2, recipient2, 2_000e18 - 1);
        _assertDepositCancellationRequest(requests[2], owner3, recipient3, 3_000e18 - 1);

        requests = grPrime.getPendingDepositCancellationRequests(1, 2);

        assertEq(requests.length, 2);

        _assertDepositCancellationRequest(requests[0], owner2, recipient2, 2_000e18 - 1);
        _assertDepositCancellationRequest(requests[1], owner3, recipient3, 3_000e18 - 1);
    }

    function test_getPendingDepositCancellationRequests_clamping() external {
        _requestDeposit(owner1, recipient1, 1_000e18);
        _requestDeposit(owner2, recipient2, 2_000e18);

        _requestDepositCancellation(owner1, 0, recipient1, sUSDS.convertToShares(1_000e18));
        _requestDepositCancellation(owner2, 1, recipient2, sUSDS.convertToShares(2_000e18));

        assertEq(grPrime.getPendingDepositCancellationRequests(0, 3).length, 2);
    }

}

contract PendingRedeemRequestTests is GettersTestBase {

    /**********************************************************************************************/
    /*** pendingRedeemRequestsLength                                                            ***/
    /**********************************************************************************************/

    function test_pendingRedeemRequestsLength() external {
        _setCapacity(VAULT_CAPACITY);

        _requestDeposit(owner1, 1_000e18);
        _requestDeposit(owner2, 2_000e18);

        assertEq(grPrime.pendingRedeemRequestsLength(), 0);

        _requestRedeem(owner1, grPrime.balanceOf(owner1));

        assertEq(grPrime.pendingRedeemRequestsLength(), 1);

        _requestRedeem(owner2, grPrime.balanceOf(owner2));

        assertEq(grPrime.pendingRedeemRequestsLength(), 2);

        _processPendingRedeems(type(uint256).max, 1);

        assertEq(grPrime.pendingRedeemRequestsLength(), 1);

        _processPendingRedeems(type(uint256).max, 1);

        assertEq(grPrime.pendingRedeemRequestsLength(), 0);
    }

    /**********************************************************************************************/
    /*** getPendingRedeemRequest                                                                ***/
    /**********************************************************************************************/

    function test_getPendingRedeemRequest_idBeforeFirstPendingBoundary() external {
        _requestDeposit(owner1, 1_000e18);
        _requestDeposit(owner2, 2_000e18);

        _requestRedeem(owner1, recipient1, grPrime.balanceOf(owner1));
        _requestRedeem(owner2, recipient2, grPrime.balanceOf(owner2));

        _processPendingRedeems(type(uint256).max, 1);

        vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
        grPrime.getPendingRedeemRequest(0);

        grPrime.getPendingRedeemRequest(1);
    }

    function test_getPendingRedeemRequest_idAfterQueueBoundary() external {
        _requestDeposit(owner1, 1_000e18);
        _requestRedeem(owner1, recipient1, grPrime.balanceOf(owner1));

        vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
        grPrime.getPendingRedeemRequest(1);

        grPrime.getPendingRedeemRequest(0);
    }

    function test_getPendingRedeemRequest() external {
        _requestDeposit(owner1, 1_000e18);
        _requestRedeem(owner1, recipient1, grPrime.balanceOf(owner1));

        _requestDeposit(owner2, 2_000e18);
        _requestRedeem(owner2, recipient2, grPrime.balanceOf(owner2));

        _assertRedeemRequest(0, owner1, recipient1, 1_000e18 - 1);
        _assertRedeemRequest(1, owner2, recipient2, 2_000e18 - 1);
    }

    function test_getPendingRedeemRequest_partialFill() external {
        _requestDeposit(owner1, 1_000e18);
        uint256 sharesOfOwner1 = grPrime.balanceOf(owner1);
        _requestRedeem(owner1, recipient1, sharesOfOwner1);

        _requestDeposit(owner2, 2_000e18);
        uint256 sharesOfOwner2 = grPrime.balanceOf(owner2);
        _requestRedeem(owner2, recipient2, sharesOfOwner2);

        _processPendingRedeems(sharesOfOwner1 / 4, 1);

        _assertRedeemRequest(0, owner1, recipient1, 750e18);
        _assertRedeemRequest(1, owner2, recipient2, 2_000e18 - 1);
    }

    /**********************************************************************************************/
    /*** pendingRedeemRequests                                                                  ***/
    /**********************************************************************************************/

    function test_pendingRedeemRequests_noRequests() external view {
        assertEq(grPrime.pendingRedeemRequests().length, 0);
    }

    function test_pendingRedeemRequests() external {
        _requestDeposit(owner1, 1_000e18);
        _requestDeposit(owner2, 2_000e18);
        _requestDeposit(owner3, 3_000e18);

        _requestRedeem(owner1, recipient1, grPrime.balanceOf(owner1));
        _requestRedeem(owner2, recipient2, grPrime.balanceOf(owner2));
        _requestRedeem(owner3, recipient3, grPrime.balanceOf(owner3));

        IGrovePrimeVault.Request[] memory requests = grPrime.pendingRedeemRequests();

        assertEq(requests.length, 3);

        _assertRedeemRequest(requests[0], owner1, recipient1, 1_000e18 - 1);
        _assertRedeemRequest(requests[1], owner2, recipient2, 2_000e18 - 1);
        _assertRedeemRequest(requests[2], owner3, recipient3, 3_000e18 - 1);
    }

    function test_pendingRedeemRequests_someProcessed() external {
        _requestDeposit(owner1, 1_000e18);
        _requestDeposit(owner2, 2_000e18);
        _requestDeposit(owner3, 3_000e18);

        _requestRedeem(owner1, recipient1, grPrime.balanceOf(owner1));
        _requestRedeem(owner2, recipient2, grPrime.balanceOf(owner2));
        _requestRedeem(owner3, recipient3, grPrime.balanceOf(owner3));

        _processPendingRedeems(type(uint256).max, 2);

        IGrovePrimeVault.Request[] memory requests = grPrime.pendingRedeemRequests();

        assertEq(requests.length, 1);

        _assertRedeemRequest(requests[0], owner3, recipient3, 3_000e18 - 1);
    }

    function test_pendingRedeemRequests_allProcessed() external {
        _requestDeposit(owner1, 1_000e18);
        _requestDeposit(owner2, 2_000e18);

        _requestRedeem(owner1, recipient1, grPrime.balanceOf(owner1));
        _requestRedeem(owner2, recipient2, grPrime.balanceOf(owner2));

        _processPendingRedeems(type(uint256).max, type(uint256).max);

        assertEq(grPrime.pendingRedeemRequests().length, 0);
    }

    function test_pendingRedeemRequests_partialFill() external {
        _requestDeposit(owner1, 1_000e18);
        uint256 owner1GrPrimeShares = grPrime.balanceOf(owner1);
        _requestRedeem(owner1, recipient1, owner1GrPrimeShares);

        _requestDeposit(owner2, 2_000e18);
        uint256 owner2GrPrimeShares = grPrime.balanceOf(owner2);
        _requestRedeem(owner2, recipient2, owner2GrPrimeShares);

        _processPendingRedeems(owner1GrPrimeShares / 4, type(uint256).max);

        IGrovePrimeVault.Request[] memory requests = grPrime.pendingRedeemRequests();

        assertEq(requests.length, 2);

        _assertRedeemRequest(requests[0], owner1, recipient1, 750e18);
        _assertRedeemRequest(requests[1], owner2, recipient2, 2_000e18 - 1);
    }

    /**********************************************************************************************/
    /*** getPendingRedeemRequests                                                               ***/
    /**********************************************************************************************/

    function test_getPendingRedeemRequests_startIdTooSmallBoundary() external {
        _requestDeposit(owner1, 1_000e18);
        _requestDeposit(owner2, 2_000e18);

        _requestRedeem(owner1, recipient1, grPrime.balanceOf(owner1));
        _requestRedeem(owner2, recipient2, grPrime.balanceOf(owner2));

        _processPendingRedeems(type(uint256).max, 1);

        vm.expectRevert(IGrovePrimeVault.StartIdTooSmall.selector);
        grPrime.getPendingRedeemRequests(0, 1);

        grPrime.getPendingRedeemRequests(1, 1);
    }

    function test_getPendingRedeemRequests_startIdTooLargeBoundary() external {
        _requestDeposit(owner1, 1_000e18);

        _requestRedeem(owner1, recipient1, grPrime.balanceOf(owner1));

        vm.expectRevert(IGrovePrimeVault.StartIdTooLarge.selector);
        grPrime.getPendingRedeemRequests(2, 0);

        grPrime.getPendingRedeemRequests(1, 0);
    }

    function test_getPendingRedeemRequests_zeroLength() external view {
        assertEq(grPrime.getPendingRedeemRequests(0, 0).length, 0);
    }

    function test_getPendingRedeemRequests_range() external {
        _requestDeposit(owner1, 1_000e18);
        _requestDeposit(owner2, 2_000e18);
        _requestDeposit(owner3, 3_000e18);

        _requestRedeem(owner1, recipient1, grPrime.balanceOf(owner1));
        _requestRedeem(owner2, recipient2, grPrime.balanceOf(owner2));
        _requestRedeem(owner3, recipient3, grPrime.balanceOf(owner3));

        IGrovePrimeVault.Request[] memory requests = grPrime.getPendingRedeemRequests(0, 3);

        assertEq(requests.length, 3);

        _assertRedeemRequest(requests[0], owner1, recipient1, 1_000e18 - 1);
        _assertRedeemRequest(requests[1], owner2, recipient2, 2_000e18 - 1);
        _assertRedeemRequest(requests[2], owner3, recipient3, 3_000e18 - 1);

        requests = grPrime.getPendingRedeemRequests(1, 2);

        assertEq(requests.length, 2);

        _assertRedeemRequest(requests[0], owner2, recipient2, 2_000e18 - 1);
        _assertRedeemRequest(requests[1], owner3, recipient3, 3_000e18 - 1);
    }

    function test_getPendingRedeemRequests_clamping() external {
        _requestDeposit(owner1, 1_000e18);
        _requestDeposit(owner2, 2_000e18);

        _requestRedeem(owner1, recipient1, grPrime.balanceOf(owner1));
        _requestRedeem(owner2, recipient2, grPrime.balanceOf(owner2));

        assertEq(grPrime.getPendingRedeemRequests(0, 3).length, 2);
    }

}

contract SupportsInterfaceTests is GettersTestBase {

    function test_supportsInterface_unsupportedInterface() external view {
        assertEq(grPrime.supportsInterface(0x00000000), false);
        assertEq(grPrime.supportsInterface(0xffffffff), false);
    }

    function test_supportsInterface() external view {
        assertEq(grPrime.supportsInterface(type(IAccessControl).interfaceId),           true);
        assertEq(grPrime.supportsInterface(type(IAccessControlEnumerable).interfaceId), true);
        assertEq(grPrime.supportsInterface(type(IERC165).interfaceId),                  true);
        assertEq(grPrime.supportsInterface(type(IGrovePrimeVault).interfaceId),         true);
    }

}
