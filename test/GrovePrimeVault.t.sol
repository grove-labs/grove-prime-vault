// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IERC20 } from "../lib/oz/contracts/token/ERC20/IERC20.sol";

import { IGrovePrimeVault } from "../src/IGrovePrimeVault.sol";

import { TestBase, ISavingsLike } from "./TestBase.t.sol";

abstract contract GrovePrimeVaultTests is TestBase {

    uint16 internal constant REFERRAL = type(uint16).max;

    address internal user = makeAddr("user");

    function setUp() public override virtual {
        super.setUp();

        vm.label(user, "user");

        skip(365 days);

        vaultState.availableCapacityValue = grPrime.convertToAssets(VAULT_CAPACITY);
    }

}

contract RequestDepositTests is GrovePrimeVaultTests {

    // Failure tests

    function test_requestDeposit_isPaused() external {
        _pause();

        vm.expectRevert(IGrovePrimeVault.IsPaused.selector);
        vm.prank(user);
        grPrime.requestDeposit(100e18, user, 0);
    }

    function test_requestDeposit_zeroRecipient() external {
        vm.expectRevert(IGrovePrimeVault.ZeroRecipient.selector);
        vm.prank(user);
        grPrime.requestDeposit(100e18, address(0), 0);
    }

    function test_requestDeposit_vaultIsRecipient() external {
        vm.expectRevert(IGrovePrimeVault.VaultIsRecipient.selector);
        vm.prank(user);
        grPrime.requestDeposit(100e18, address(grPrime), 0);
    }

    function test_requestDeposit_belowMinDepositBoundary() external {
        deal(address(usds), user, MINIMUM_DEPOSIT);

        vm.prank(user);
        usds.approve(address(grPrime), MINIMUM_DEPOSIT);

        vm.expectRevert(IGrovePrimeVault.BelowMinDeposit.selector);
        vm.prank(user);
        grPrime.requestDeposit(MINIMUM_DEPOSIT - 1, user, 0);

        vm.prank(user);
        grPrime.requestDeposit(MINIMUM_DEPOSIT, user, 0);
    }

    function test_requestDeposit_insufficientAllowanceBoundary() external {
        deal(address(usds), user, 1_000_000e18 + 1);

        vm.prank(user);
        usds.approve(address(grPrime), 1_000_000e18);

        vm.prank(user);
        vm.expectRevert("Usds/insufficient-allowance");
        grPrime.requestDeposit(1_000_000e18 + 1, user, 0);

        vm.prank(user);
        grPrime.requestDeposit(1_000_000e18, user, 0);
    }

    function test_requestDeposit_insufficientBalanceBoundary() external {
        deal(address(usds), user, 1_000_000e18);

        vm.prank(user);
        usds.approve(address(grPrime), 1_000_000e18 + 1);

        vm.prank(user);
        vm.expectRevert("Usds/insufficient-balance");
        grPrime.requestDeposit(1_000_000e18 + 1, user, 0);

        vm.prank(user);
        grPrime.requestDeposit(1_000_000e18, user, 0);
    }

    // Success tests

    function test_requestDeposit_partialFill() external {
        _requestDeposit(user, 1_000_000e18);  // Deposit Request 0 (Filled instantly)

        _setCapacity(grPrime.convertToShares(1_500_000e18));

        vaultState.rho                    = vm.getBlockTimestamp();
        vaultState.chi                    = 1.049999999999999999961070145e27;
        vaultState.totalAssets            = 1_000_000e18 - 2;
        vaultState.availableCapacityValue = 500_000e18 + 1;
        vaultState.availableLiquidAssets  = 1_000_000e18 - 1;

        vaultState.depositRequests.pendingShareValue = 0;
        vaultState.depositRequests.length            = 0;
        vaultState.depositRequests.firstPendingId    = 1;

        AccountBalances memory userBalances = AccountBalances({
            account           : user,
            assets            : 0,
            shareValue        : 1_000_000e18 - 2,
            savingsShareValue : 0,
            claimableAssets   : 0
        });

        AccountBalances memory vaultBalances = AccountBalances({
            account           : address(grPrime),
            assets            : 0,
            shareValue        : 0,
            savingsShareValue : 1_000_000e18 - 1,
            claimableAssets   : 0
        });

        _assertVaultState();

        _assertAccountBalances(userBalances);
        _assertAccountBalances(vaultBalances);

        deal(address(usds), user, 800_000e18);

        vm.prank(user);
        usds.approve(address(grPrime), 800_000e18);

        uint256 expectedConvertedAssets       = 500_000e18;
        uint256 expectedSavingsSharesMinted   = sUSDS.convertToShares(800_000e18);
        uint256 expectedSavingsSharesConsumed = sUSDS.convertToShares(expectedConvertedAssets) + 1;
        uint256 expectedSharesMinted          = grPrime.convertToShares(expectedConvertedAssets);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Referral(REFERRAL, 1, user, user, 800_000e18);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositRequest(1, user, user, 800_000e18, expectedSavingsSharesMinted);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Deposit(1, user, user, expectedSavingsSharesConsumed, expectedConvertedAssets, expectedSharesMinted);

        vm.prank(user);
        uint256 requestId = grPrime.requestDeposit(800_000e18, user, REFERRAL);

        assertEq(requestId, 1);

        _assertDepositRequest(1, user, user, 300_000e18 - 2);

        vaultState.totalAssets            += 500_000e18 - 1;
        vaultState.availableCapacityValue  = 2;
        vaultState.availableLiquidAssets  += 800_000e18 - 1;

        vaultState.depositRequests.pendingShareValue += 300_000e18 - 2;
        vaultState.depositRequests.length             = 1;
        vaultState.depositRequests.firstPendingId     = 1;

        userBalances.shareValue += 500_000e18 - 1;

        vaultBalances.savingsShareValue += 800_000e18 - 1;

        _assertVaultState();
        _assertAccountBalances(userBalances);
        _assertAccountBalances(vaultBalances);
    }

    function test_requestDeposit_queued() external {
        _requestDeposit(user, 1_000_000e18);  // Deposit Request 0 (Filled instantly)

        _setCapacity(grPrime.convertToShares(1_000_000e18));

        vaultState.rho                    = vm.getBlockTimestamp();
        vaultState.chi                    = 1.049999999999999999961070145e27;
        vaultState.totalAssets            = 1_000_000e18 - 2;
        vaultState.availableCapacityValue = 1;
        vaultState.availableLiquidAssets  = 1_000_000e18 - 1;

        vaultState.depositRequests.pendingShareValue = 0;
        vaultState.depositRequests.length            = 0;
        vaultState.depositRequests.firstPendingId    = 1;

        AccountBalances memory userBalances = AccountBalances({
            account           : user,
            assets            : 0,
            shareValue        : 1_000_000e18 - 2,
            savingsShareValue : 0,
            claimableAssets   : 0
        });

        AccountBalances memory vaultBalances = AccountBalances({
            account           : address(grPrime),
            assets            : 0,
            shareValue        : 0,
            savingsShareValue : 1_000_000e18 - 1,
            claimableAssets   : 0
        });

        _assertVaultState();

        _assertAccountBalances(userBalances);
        _assertAccountBalances(vaultBalances);

        deal(address(usds), user, 800_000e18);

        vm.prank(user);
        usds.approve(address(grPrime), 800_000e18);

        uint256 expectedSavingsSharesMinted = sUSDS.convertToShares(800_000e18);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Referral(REFERRAL, 1, user, user, 800_000e18);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositRequest(1, user, user, 800_000e18, expectedSavingsSharesMinted);

        vm.prank(user);
        uint256 requestId = grPrime.requestDeposit(800_000e18, user, REFERRAL);

        assertEq(requestId, 1);

        _assertDepositRequest(1, user, user, 800_000e18 - 1);

        vaultState.availableLiquidAssets += 800_000e18 - 1;

        vaultState.depositRequests.pendingShareValue = 800_000e18 - 1;
        vaultState.depositRequests.length            = 1;
        vaultState.depositRequests.firstPendingId    = 1;

        vaultBalances.savingsShareValue += 800_000e18 - 1;

        _assertVaultState();
        _assertAccountBalances(userBalances);
        _assertAccountBalances(vaultBalances);
    }

}

contract RequestRedeemTests is GrovePrimeVaultTests {

    // Failure tests

    function test_requestRedeem_isPaused() external {
        _pause();

        vm.expectRevert(IGrovePrimeVault.IsPaused.selector);
        vm.prank(user);
        grPrime.requestRedeem(100e18, user);
    }

    function test_requestRedeem_zeroRecipient() external {
        vm.expectRevert(IGrovePrimeVault.ZeroRecipient.selector);
        vm.prank(user);
        grPrime.requestRedeem(100e18, address(0));
    }

    function test_requestRedeem_vaultIsRecipient() external {
        vm.expectRevert(IGrovePrimeVault.VaultIsRecipient.selector);
        vm.prank(user);
        grPrime.requestRedeem(100e18, address(grPrime));
    }

    function test_requestRedeem_belowMinRedeemBoundary() external {
        _requestDeposit(user, 1_000e18);

        vm.expectRevert(IGrovePrimeVault.BelowMinRedeem.selector);
        vm.prank(user);
        grPrime.requestRedeem(MINIMUM_REDEEM - 1, user);

        vm.prank(user);
        grPrime.requestRedeem(MINIMUM_REDEEM, user);
    }

    function test_requestRedeem_insufficientBalanceBoundary() external {
        _requestDeposit(user, 1_000e18);

        uint256 grPrimeShares = grPrime.balanceOf(user);

        assertEq(grPrimeShares, 952.380952380952380986e18);

        vm.expectRevert("GrovePrimeVault/insufficient-balance");
        vm.prank(user);
        grPrime.requestRedeem(grPrimeShares + 1, user);

        vm.prank(user);
        grPrime.requestRedeem(grPrimeShares, user);
    }

    // Success tests

    function test_requestRedeem() external {
        _requestDeposit(user, 1_000_000e18);  // Deposit Request 0 (Filled instantly)

        vaultState.rho                    = vm.getBlockTimestamp();
        vaultState.chi                    = 1.049999999999999999961070145e27;
        vaultState.totalAssets            = 1_000_000e18 - 2;
        vaultState.availableCapacityValue = 104_000_000e18 - 3_892_984;  // Vault capacity value was ~105m because of ~5% change in chi prior to the first deposit
        vaultState.availableLiquidAssets  = 1_000_000e18 - 1;

        vaultState.depositRequests.firstPendingId = 1;

        AccountBalances memory userBalances = AccountBalances({
            account           : user,
            assets            : 0,
            shareValue        : 1_000_000e18 - 2,
            savingsShareValue : 0,
            claimableAssets   : 0
        });

        AccountBalances memory vaultBalances = AccountBalances({
            account           : address(grPrime),
            assets            : 0,
            shareValue        : 0,
            savingsShareValue : 1_000_000e18 - 1,
            claimableAssets   : 0
        });

        _assertVaultState();

        _assertAccountBalances(userBalances);
        _assertAccountBalances(vaultBalances);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.RedeemRequest(0, user, user, 500_000e18, 0);

        vm.prank(user);
        uint256 requestId = grPrime.requestRedeem(500_000e18, user);

        assertEq(requestId, 0);

        vaultState.redeemRequests.pendingShareValue = 525_000e18 - 19_465;  // 500k grPrime == ~525k USD because of current exchange rate
        vaultState.redeemRequests.length            = 1;
        vaultState.redeemRequests.firstPendingId    = 0;

        userBalances.shareValue -= 525_000e18 - 19_465;

        vaultBalances.shareValue += 525_000e18 - 19_465;

        _assertRedeemRequest(0, user, user, 525_000e18 - 19_465);

        _assertVaultState();
        _assertAccountBalances(userBalances);
        _assertAccountBalances(vaultBalances);
    }

    function test_requestRedeem_withFee() external {
        _setMaxRedeemFeeRate(0.01e18);  // 1%
        _setRedeemFeeRate(0.005e18);    // 0.5%

        _requestDeposit(user, 1_000_000e18);  // Deposit Request 0 (Filled instantly)

        vaultState.rho                    = vm.getBlockTimestamp();
        vaultState.chi                    = 1.049999999999999999961070145e27;
        vaultState.totalAssets            = 1_000_000e18 - 2;
        vaultState.availableCapacityValue = 104_000_000e18 - 3_892_984;  // Vault capacity value was ~105m because of ~5% change in chi prior to the first deposit
        vaultState.availableLiquidAssets  = 1_000_000e18 - 1;

        vaultState.depositRequests.firstPendingId = 1;

        AccountBalances memory userBalances = AccountBalances({
            account           : user,
            assets            : 0,
            shareValue        : 1_000_000e18 - 2,
            savingsShareValue : 0,
            claimableAssets   : 0
        });

        AccountBalances memory vaultBalances = AccountBalances({
            account           : address(grPrime),
            assets            : 0,
            shareValue        : 0,
            savingsShareValue : 1_000_000e18 - 1,
            claimableAssets   : 0
        });

        _assertVaultState();

        _assertAccountBalances(userBalances);
        _assertAccountBalances(vaultBalances);

        // Assets held (sUSDS value) match assets owed to grPrime holders, within rounding
        assertEq(grPrime.availableLiquidAssets() - grPrime.totalAssets(), 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.RedeemRequest(0, user, user, 500_000e18, 2_500e18);

        vm.prank(user);
        uint256 requestId = grPrime.requestRedeem(500_000e18, user);

        assertEq(requestId, 0);

        // Fee shares are burned, so supply and assets drop and capacity frees up
        vaultState.totalAssets            -= 2_625e18 - 97;  // 2_500e18 fee shares * ~1.05 chi
        vaultState.availableCapacityValue += 2_625e18 - 98;

        vaultState.redeemRequests.pendingShareValue = 525_000e18 - 2_625e18 - 19_368;
        vaultState.redeemRequests.length            = 1;
        vaultState.redeemRequests.firstPendingId    = 0;

        userBalances.shareValue -= 525_000e18 - 19_465;

        vaultBalances.shareValue += 525_000e18 - 2_625e18 - 19_368;

        _assertRedeemRequest(0, user, user, 525_000e18 - 2_625e18 - 19_368);

        _assertVaultState();
        _assertAccountBalances(userBalances);
        _assertAccountBalances(vaultBalances);

        // Assets held are unchanged but assets owed dropped by the burned fee, the difference is Grove's profit
        assertEq(grPrime.availableLiquidAssets() - grPrime.totalAssets(), 2_625e18 - 96);
    }

}

contract ProcessPendingDepositsTests is GrovePrimeVaultTests {

    address internal ali = makeAddr("ali");
    address internal bob = makeAddr("bob");
    address internal cam = makeAddr("cam");

    AccountBalances internal aliBalances;
    AccountBalances internal bobBalances;
    AccountBalances internal camBalances;
    AccountBalances internal vaultBalances;

    function setUp() public override {
        super.setUp();

        vm.label(ali, "ali");
        vm.label(bob, "bob");
        vm.label(cam, "cam");

        _setCapacity(0);

        _requestDeposit(ali, 100_000e18);    // Will be cancelled
        _requestDeposit(bob, 200_000e18);    // Will be cancelled
        _requestDeposit(cam, 300_000e18);    // Will be cancelled
        _requestDeposit(ali, 400_000e18);    // Will be filled
        _requestDeposit(bob, 500_000e18);    // Will be filled
        _requestDeposit(cam, 600_000e18);    // Will be cancelled
        _requestDeposit(ali, 700_000e18);    // Will be filled
        _requestDeposit(bob, 800_000e18);    // Will be filled
        _requestDeposit(cam, 900_000e18);    // Will be cancelled
        _requestDeposit(ali, 1_000_000e18);  // Will be partially filled

        _requestDepositCancellation(ali, 0, sUSDS.convertToShares(100_000e18));
        _requestDepositCancellation(bob, 1, sUSDS.convertToShares(200_000e18));
        _requestDepositCancellation(cam, 2, sUSDS.convertToShares(300_000e18));
        _requestDepositCancellation(cam, 5, sUSDS.convertToShares(600_000e18));
        _requestDepositCancellation(cam, 8, sUSDS.convertToShares(900_000e18));

        uint256 depositedAssets = 5_500_000e18;

        uint256 pendingDepositAssets = 400_000e18 + 500_000e18 + 700_000e18 + 800_000e18 + 1_000_000e18;

        uint256 pendingDepositCancellationAssets = 100_000e18 + 200_000e18 + 300_000e18 + 600_000e18 + 900_000e18;

        uint256 targetAssets = 400_000e18 + 500_000e18 + 700_000e18 + 800_000e18 + 200_000e18;  // Only 200k of the last 1MM deposit

        _setCapacity(grPrime.convertToShares(targetAssets));

        vaultState.rho                    = vm.getBlockTimestamp();
        vaultState.chi                    = 1.049999999999999999961070145e27;
        vaultState.totalAssets            = 0;
        vaultState.totalClaimable         = 0;
        vaultState.availableCapacityValue = targetAssets - 1;
        vaultState.availableLiquidAssets  = depositedAssets - 8;

        vaultState.depositRequests.pendingShareValue = pendingDepositAssets - 3;
        vaultState.depositRequests.length            = 7;
        vaultState.depositRequests.firstPendingId    = 3;

        vaultState.depositCancellationRequests.pendingShareValue = pendingDepositCancellationAssets - 5;
        vaultState.depositCancellationRequests.length            = 5;
        vaultState.depositCancellationRequests.firstPendingId    = 0;

        aliBalances = AccountBalances({
            account           : ali,
            assets            : 0,
            shareValue        : 0,
            savingsShareValue : 0,
            claimableAssets   : 0
        });

        bobBalances = AccountBalances({
            account           : bob,
            assets            : 0,
            shareValue        : 0,
            savingsShareValue : 0,
            claimableAssets   : 0
        });

        camBalances = AccountBalances({
            account           : cam,
            assets            : 0,
            shareValue        : 0,
            savingsShareValue : 0,
            claimableAssets   : 0
        });

        vaultBalances = AccountBalances({
            account           : address(grPrime),
            assets            : 0,
            shareValue        : 0,
            savingsShareValue : depositedAssets - 8,
            claimableAssets   : 0
        });

        _assertVaultState();

        _assertAccountBalances(aliBalances);
        _assertAccountBalances(bobBalances);
        _assertAccountBalances(camBalances);
        _assertAccountBalances(vaultBalances);

        for (uint256 i = 0; i < 3; i++) {
            vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
            grPrime.getPendingDepositRequest(i);
        }

        _assertDepositRequest(3, ali, ali, 400_000e18 - 1);
        _assertDepositRequest(4, bob, bob, 500_000e18 - 1);

        _assertEmptyDepositRequest(5);

        _assertDepositRequest(6, ali, ali, 700_000e18 - 1);
        _assertDepositRequest(7, bob, bob, 800_000e18 - 1);

        _assertEmptyDepositRequest(8);

        _assertDepositRequest(9, ali, ali, 1_000_000e18 - 1);
    }

    // Failure tests

    function test_processPendingDeposits_isPaused() external {
        _pause();

        vm.expectRevert(IGrovePrimeVault.IsPaused.selector);
        vm.prank(operator);
        grPrime.processPendingDeposits(type(uint256).max, type(uint256).max);
    }

    // Success tests

    function test_processPendingDeposits_infiniteMaxSavingsShares_infiniteMaxRequests() external {
        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ProcessPendingDeposits(operator, type(uint256).max, type(uint256).max);

        // Deposit Request 3

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(0), ali, grPrime.convertToShares(400_000e18) - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Deposit(3, ali, ali, sUSDS.convertToShares(400_000e18), 400_000e18 - 1, grPrime.convertToShares(400_000e18) - 1);

        // Deposit Request 4

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(0), bob, grPrime.convertToShares(500_000e18) - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Deposit(4, bob, bob, sUSDS.convertToShares(500_000e18), 500_000e18 - 1, grPrime.convertToShares(500_000e18) - 1);

        // Deposit Request 6

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(0), ali, grPrime.convertToShares(700_000e18) - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Deposit(6, ali, ali, sUSDS.convertToShares(700_000e18), 700_000e18 - 1, grPrime.convertToShares(700_000e18) - 1);

        // Deposit Request 7

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(0), bob, grPrime.convertToShares(800_000e18) - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Deposit(7, bob, bob, sUSDS.convertToShares(800_000e18), 800_000e18 - 1, grPrime.convertToShares(800_000e18) - 1);

        // Deposit Request 9 (Partial)

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(0), ali, grPrime.convertToShares(200_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Deposit(9, ali, ali, sUSDS.convertToShares(200_000e18) + 1, 200_000e18, grPrime.convertToShares(200_000e18));

        vm.prank(operator);
        grPrime.processPendingDeposits(type(uint256).max, type(uint256).max);

        uint256 assetsDeposited = 400_000e18 + 500_000e18 + 700_000e18 + 800_000e18 + 200_000e18;  // Only ~200k of the last 1MM deposit

        vaultState.totalAssets            += assetsDeposited - 7;
        vaultState.availableCapacityValue -= assetsDeposited - 6;

        vaultState.depositRequests.pendingShareValue -= assetsDeposited - 2;
        vaultState.depositRequests.length             = 1;
        vaultState.depositRequests.firstPendingId     = 9;

        aliBalances.shareValue += 400_000e18 + 700_000e18 + 200_000e18 - 4;
        bobBalances.shareValue += 500_000e18 + 800_000e18 - 4;

        _assertVaultState();
        _assertAccountBalances(aliBalances);
        _assertAccountBalances(bobBalances);
        _assertAccountBalances(camBalances);
        _assertAccountBalances(vaultBalances);

        for (uint256 i = 0; i < 9; i++) {
            vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
            grPrime.getPendingDepositRequest(i);
        }

        _assertDepositRequest(9, ali, ali, 800_000e18 - 1);
    }

    function test_processPendingDeposits_infiniteMaxSavingsShares_limitedMaxRequests() external {
        uint256 maxRequests = 3;

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ProcessPendingDeposits(operator, type(uint256).max, maxRequests);

        // Deposit Request 3

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(0), ali, grPrime.convertToShares(400_000e18) - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Deposit(3, ali, ali, sUSDS.convertToShares(400_000e18), 400_000e18 - 1, grPrime.convertToShares(400_000e18) - 1);

        // Deposit Request 4

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(0), bob, grPrime.convertToShares(500_000e18) - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Deposit(4, bob, bob, sUSDS.convertToShares(500_000e18), 500_000e18 - 1, grPrime.convertToShares(500_000e18) - 1);

        // First 3 cancelled deposits were already skipped, so this fills 2 deposits, then skips 1 cancelled deposit.
        vm.prank(operator);
        grPrime.processPendingDeposits(type(uint256).max, maxRequests);

        uint256 assetsDeposited = 400_000e18 + 500_000e18;  // Only first 2 uncancelled deposits

        vaultState.totalAssets            += assetsDeposited - 4;
        vaultState.availableCapacityValue -= assetsDeposited - 3;

        vaultState.depositRequests.pendingShareValue -= assetsDeposited - 1;
        vaultState.depositRequests.length             = 4;
        vaultState.depositRequests.firstPendingId     = 6;

        aliBalances.shareValue += 400_000e18 - 2;
        bobBalances.shareValue += 500_000e18 - 2;

        _assertVaultState();
        _assertAccountBalances(aliBalances);
        _assertAccountBalances(bobBalances);
        _assertAccountBalances(camBalances);
        _assertAccountBalances(vaultBalances);

        for (uint256 i = 0; i < 6; i++) {
            vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
            grPrime.getPendingDepositRequest(i);
        }

        _assertDepositRequest(6, ali, ali, 700_000e18 - 1);
        _assertDepositRequest(7, bob, bob, 800_000e18 - 1);

        _assertEmptyDepositRequest(8);

        _assertDepositRequest(9, ali, ali, 1_000_000e18 - 1);
    }

    function test_processPendingDeposits_limitedMaxSavingsShares_infiniteMaxRequests() external {
        uint256 maxSavingsShares = sUSDS.convertToShares(1_200_000e18);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ProcessPendingDeposits(operator, maxSavingsShares, type(uint256).max);

        // Deposit Request 3

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(0), ali, grPrime.convertToShares(400_000e18) - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Deposit(3, ali, ali, sUSDS.convertToShares(400_000e18), 400_000e18 - 1, grPrime.convertToShares(400_000e18) - 1);

        // Deposit Request 4

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(0), bob, grPrime.convertToShares(500_000e18) - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Deposit(4, bob, bob, sUSDS.convertToShares(500_000e18), 500_000e18 - 1, grPrime.convertToShares(500_000e18) - 1);

        // Deposit Request 6 (Partial)

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(0), ali, grPrime.convertToShares(300_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Deposit(6, ali, ali, sUSDS.convertToShares(300_000e18) + 1, 300_000e18, grPrime.convertToShares(300_000e18));

        vm.prank(operator);
        grPrime.processPendingDeposits(maxSavingsShares, type(uint256).max);

        uint256 assetsDeposited = 400_000e18 + 500_000e18 + 300_000e18;  // Only ~300k of the third uncancelled 700k deposit

        vaultState.totalAssets            += assetsDeposited - 4;
        vaultState.availableCapacityValue -= assetsDeposited - 4;

        vaultState.depositRequests.pendingShareValue -= assetsDeposited - 1;
        vaultState.depositRequests.length             = 4;
        vaultState.depositRequests.firstPendingId     = 6;

        aliBalances.shareValue += 400_000e18 + 300_000e18 - 3;
        bobBalances.shareValue += 500_000e18 - 2;

        _assertVaultState();
        _assertAccountBalances(aliBalances);
        _assertAccountBalances(bobBalances);
        _assertAccountBalances(camBalances);
        _assertAccountBalances(vaultBalances);

        for (uint256 i = 0; i < 6; i++) {
            vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
            grPrime.getPendingDepositRequest(i);
        }

        _assertDepositRequest(6, ali, ali, 400_000e18 - 1);  // Partial fill
        _assertDepositRequest(7, bob, bob, 800_000e18 - 1);

        _assertEmptyDepositRequest(8);

        _assertDepositRequest(9, ali, ali, 1_000_000e18 - 1);
    }

    function _getMaxDepositableAmount(uint256 requestAmount, uint256 maxSavingsShareValue, uint256 assetsDeposited) internal pure returns (uint256) {
        return assetsDeposited + requestAmount > maxSavingsShareValue
            ? maxSavingsShareValue - assetsDeposited
            : requestAmount;
    }

    function testFuzz_processPendingDeposits(uint256 maxSavingsShareValue, uint256 maxRequests) external {
        maxSavingsShareValue = _bound(maxSavingsShareValue, 0, 2 * vaultState.depositRequests.pendingShareValue);
        maxRequests          = _bound(maxRequests,          0, 2 * vaultState.depositRequests.length);

        vm.startPrank(operator);
        grPrime.processPendingDeposits(sUSDS.convertToShares(maxSavingsShareValue), maxRequests);
        vm.stopPrank();

        uint256 assetsDeposited;

        for (uint256 i = 0; i < maxRequests; ++i) {
            if (i == 0) {
                uint256 depositAmount = _getMaxDepositableAmount(400_000e18, maxSavingsShareValue, 0);

                aliBalances.shareValue += depositAmount;
                assetsDeposited        += depositAmount;

                if (depositAmount < 400_000e18) break;
            }

            if (i == 1) {
                uint256 depositAmount = _getMaxDepositableAmount(500_000e18, maxSavingsShareValue, assetsDeposited);

                bobBalances.shareValue += depositAmount;
                assetsDeposited        += depositAmount;

                if (depositAmount < 500_000e18) break;
            }

            if (i == 3) {
                uint256 depositAmount = _getMaxDepositableAmount(700_000e18, maxSavingsShareValue, assetsDeposited);

                aliBalances.shareValue += depositAmount;
                assetsDeposited        += depositAmount;

                if (depositAmount < 700_000e18) break;
            }

            if (i == 4) {
                uint256 depositAmount = _getMaxDepositableAmount(800_000e18, maxSavingsShareValue, assetsDeposited);

                bobBalances.shareValue += depositAmount;
                assetsDeposited        += depositAmount;

                if (depositAmount < 800_000e18) break;
            }

            if (i == 6) {
                uint256 depositAmount = _getMaxDepositableAmount(200_000e18, maxSavingsShareValue, assetsDeposited);

                aliBalances.shareValue += depositAmount;
                assetsDeposited        += depositAmount;

                break; // Last deposit request can never be entirely fulfilled.
            }

            --vaultState.depositRequests.length;
            ++vaultState.depositRequests.firstPendingId;

            if (vaultState.depositRequests.length == 0) break;
        }

        vaultState.totalAssets += assetsDeposited;

        if (vaultState.availableCapacityValue < assetsDeposited) {
            vaultState.availableCapacityValue = 0;
        } else {
            vaultState.availableCapacityValue -= assetsDeposited;
        }

        if (vaultState.depositRequests.pendingShareValue < assetsDeposited) {
            vaultState.depositRequests.pendingShareValue = 0;
        } else {
            vaultState.depositRequests.pendingShareValue -= assetsDeposited;
        }

        _assertVaultState(10);
        _assertAccountBalances(aliBalances,   10);
        _assertAccountBalances(bobBalances,   10);
        _assertAccountBalances(camBalances,   10);
        _assertAccountBalances(vaultBalances, 10);
    }

    function test_processPendingDeposits_multipleCalls() external {
        uint256 maxSavingsShares = sUSDS.convertToShares(1_200_000e18);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ProcessPendingDeposits(operator, maxSavingsShares, type(uint256).max);

        // Deposit Request 3

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(0), ali, grPrime.convertToShares(400_000e18) - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Deposit(3, ali, ali, sUSDS.convertToShares(400_000e18), 400_000e18 - 1, grPrime.convertToShares(400_000e18) - 1);

        // Deposit Request 4

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(0), bob, grPrime.convertToShares(500_000e18) - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Deposit(4, bob, bob, sUSDS.convertToShares(500_000e18), 500_000e18 - 1, grPrime.convertToShares(500_000e18) - 1);

        // Deposit Request 6 (Partial)

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(0), ali, grPrime.convertToShares(300_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Deposit(6, ali, ali, sUSDS.convertToShares(300_000e18) + 1, 300_000e18, grPrime.convertToShares(300_000e18));

        vm.prank(operator);
        grPrime.processPendingDeposits(maxSavingsShares, type(uint256).max);

        uint256 assetsDeposited = 400_000e18 + 500_000e18 + 300_000e18;  // Only ~300k of the Request 6 700k deposit

        vaultState.totalAssets            += assetsDeposited - 4;
        vaultState.availableCapacityValue -= assetsDeposited - 4;

        vaultState.depositRequests.pendingShareValue -= assetsDeposited - 1;
        vaultState.depositRequests.length             = 4;
        vaultState.depositRequests.firstPendingId     = 6;

        aliBalances.shareValue += 400_000e18 + 300_000e18 - 3;
        bobBalances.shareValue += 500_000e18 - 2;

        _assertVaultState();
        _assertAccountBalances(aliBalances);
        _assertAccountBalances(bobBalances);
        _assertAccountBalances(camBalances);
        _assertAccountBalances(vaultBalances);

        for (uint256 i = 0; i < 6; i++) {
            vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
            grPrime.getPendingDepositRequest(i);
        }

        _assertDepositRequest(6, ali, ali, 400_000e18 - 1);  // Partial fill
        _assertDepositRequest(7, bob, bob, 800_000e18 - 1);

        _assertEmptyDepositRequest(8);

        _assertDepositRequest(9, ali, ali, 1_000_000e18 - 1);

        // Deposit Request 6 (Remainder)

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(0), ali, grPrime.convertToShares(400_000e18) - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Deposit(6, ali, ali, sUSDS.convertToShares(400_000e18), 400_000e18 - 1, grPrime.convertToShares(400_000e18) - 1);

        // Deposit Request 7

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(0), bob, grPrime.convertToShares(800_000e18) - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Deposit(7, bob, bob, sUSDS.convertToShares(800_000e18), 800_000e18 - 1, grPrime.convertToShares(800_000e18) - 1);

        // Deposit Request 9 (Partial)

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(0), ali, grPrime.convertToShares(200_000e18) + 3);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Deposit(9, ali, ali, sUSDS.convertToShares(200_000e18) + 4, 200_000e18 + 3, grPrime.convertToShares(200_000e18) + 3);

        vm.prank(operator);
        grPrime.processPendingDeposits(type(uint256).max, type(uint256).max);

        assetsDeposited = 400_000e18 + 800_000e18 + 200_000e18;  // Remaining ~400k of request 6, then only ~200k of the last 1MM deposit

        vaultState.totalAssets            += assetsDeposited - 1;
        vaultState.availableCapacityValue -= assetsDeposited;

        vaultState.depositRequests.pendingShareValue -= assetsDeposited + 3;
        vaultState.depositRequests.length             = 1;
        vaultState.depositRequests.firstPendingId     = 9;

        aliBalances.shareValue += 400_000e18 + 200_000e18 + 2;
        bobBalances.shareValue += 800_000e18 - 2;

        _assertVaultState();
        _assertAccountBalances(aliBalances);
        _assertAccountBalances(bobBalances);
        _assertAccountBalances(camBalances);
        _assertAccountBalances(vaultBalances);

        for (uint256 i = 0; i < 9; i++) {
            vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
            grPrime.getPendingDepositRequest(i);
        }

        _assertDepositRequest(9, ali, ali, 800_000e18 - 5);
    }

}

contract ProcessPendingDepositsCancellationsTests is GrovePrimeVaultTests {

    address internal ali = makeAddr("ali");
    address internal bob = makeAddr("bob");
    address internal cam = makeAddr("cam");
    address internal dan = makeAddr("dan");

    AccountBalances internal aliBalances;
    AccountBalances internal bobBalances;
    AccountBalances internal camBalances;
    AccountBalances internal danBalances;
    AccountBalances internal vaultBalances;

    function setUp() public override {
        super.setUp();

        vm.label(ali, "ali");
        vm.label(bob, "bob");
        vm.label(cam, "cam");
        vm.label(dan, "dan");

        _setCapacity(0);

        _requestDeposit(ali, 100_000e18);
        _requestDeposit(bob, 200_000e18);
        _requestDeposit(cam, 300_000e18);
        _requestDeposit(ali, 400_000e18);
        _requestDeposit(bob, 500_000e18);
        _requestDeposit(cam, 600_000e18);
        _requestDeposit(ali, 700_000e18);
        _requestDeposit(bob, 800_000e18);
        _requestDeposit(cam, 900_000e18);
        _requestDeposit(ali, 1_000_000e18);

        _requestDepositCancellation(ali, 0, ali, sUSDS.convertToShares(100_000e18));  // Will fail
        _requestDepositCancellation(bob, 1, bob, sUSDS.convertToShares(200_000e18));
        _requestDepositCancellation(cam, 2, cam, sUSDS.convertToShares(300_000e18));
        _requestDepositCancellation(ali, 3, dan, sUSDS.convertToShares(400_000e18));  // Will fail
        _requestDepositCancellation(bob, 4, bob, sUSDS.convertToShares(500_000e18));  // Will fail
        _requestDepositCancellation(cam, 5, cam, sUSDS.convertToShares(600_000e18));
        _requestDepositCancellation(ali, 6, ali, sUSDS.convertToShares(700_000e18));  // Will fail
        _requestDepositCancellation(bob, 7, dan, sUSDS.convertToShares(800_000e18));  // Will fail
        _requestDepositCancellation(cam, 8, cam, sUSDS.convertToShares(900_000e18));
        _requestDepositCancellation(ali, 9, ali, sUSDS.convertToShares(1_000_000e18));

        uint256 depositedAssets = 5_500_000e18;

        vaultState.rho                    = vm.getBlockTimestamp();
        vaultState.chi                    = 1.049999999999999999961070145e27;
        vaultState.totalAssets            = 0;
        vaultState.totalClaimable         = 0;
        vaultState.availableCapacityValue = 0;
        vaultState.availableLiquidAssets  = depositedAssets - 8;

        vaultState.depositRequests.pendingShareValue = 0;
        vaultState.depositRequests.length            = 0;
        vaultState.depositRequests.firstPendingId    = 10;

        vaultState.depositCancellationRequests.pendingShareValue = depositedAssets - 8;
        vaultState.depositCancellationRequests.length            = 10;
        vaultState.depositCancellationRequests.firstPendingId    = 0;

        aliBalances = AccountBalances({
            account           : ali,
            assets            : 0,
            shareValue        : 0,
            savingsShareValue : 0,
            claimableAssets   : 0
        });

        bobBalances = AccountBalances({
            account           : bob,
            assets            : 0,
            shareValue        : 0,
            savingsShareValue : 0,
            claimableAssets   : 0
        });

        camBalances = AccountBalances({
            account           : cam,
            assets            : 0,
            shareValue        : 0,
            savingsShareValue : 0,
            claimableAssets   : 0
        });

        danBalances = AccountBalances({
            account           : dan,
            assets            : 0,
            shareValue        : 0,
            savingsShareValue : 0,
            claimableAssets   : 0
        });

        vaultBalances = AccountBalances({
            account           : address(grPrime),
            assets            : 0,
            shareValue        : 0,
            savingsShareValue : depositedAssets - 8,
            claimableAssets   : 0
        });

        _assertVaultState();

        _assertAccountBalances(aliBalances);
        _assertAccountBalances(bobBalances);
        _assertAccountBalances(camBalances);
        _assertAccountBalances(danBalances);
        _assertAccountBalances(vaultBalances);

        for (uint256 i = 0; i < 10; i++) {
            vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
            grPrime.getPendingDepositRequest(i);
        }

        _assertDepositCancellationRequest(0, ali, ali, 100_000e18 - 1);
        _assertDepositCancellationRequest(1, bob, bob, 200_000e18 - 1);
        _assertDepositCancellationRequest(2, cam, cam, 300_000e18 - 2);
        _assertDepositCancellationRequest(3, ali, dan, 400_000e18 - 1);
        _assertDepositCancellationRequest(4, bob, bob, 500_000e18 - 1);
        _assertDepositCancellationRequest(5, cam, cam, 600_000e18 - 2);
        _assertDepositCancellationRequest(6, ali, ali, 700_000e18 - 1);
        _assertDepositCancellationRequest(7, bob, dan, 800_000e18 - 1);
        _assertDepositCancellationRequest(8, cam, cam, 900_000e18 - 2);
        _assertDepositCancellationRequest(9, ali, ali, 1_000_000e18 - 1);
    }

    function test_processPendingDepositCancellations_fallbackRedeemReverts() external {
        vm.mockCallRevert(
            address(sUSDS),
            abi.encodeWithSelector(ISavingsLike.redeem.selector, sUSDS.convertToShares(100_000e18), ali, address(grPrime)),
            ""
        );

        vm.mockCallRevert(
            address(sUSDS),
            abi.encodeWithSelector(ISavingsLike.redeem.selector, sUSDS.convertToShares(100_000e18), address(grPrime), address(grPrime)),
            "redeem-to-vault-reverts"
        );

        vm.expectRevert(bytes("redeem-to-vault-reverts"));
        vm.prank(operator);
        grPrime.processPendingDepositCancellations(type(uint256).max, type(uint256).max);
    }

    function test_processPendingDepositCancellations_whilePaused() external {
        _pause();

        vm.prank(operator);
        grPrime.processPendingDepositCancellations(type(uint256).max, type(uint256).max);
    }

    function _setupMockCallReverts() internal {
        vm.mockCallRevert(
            address(sUSDS),
            abi.encodeWithSelector(ISavingsLike.redeem.selector, sUSDS.convertToShares(100_000e18), ali, address(grPrime)),
            ""
        );

        vm.mockCallRevert(
            address(sUSDS),
            abi.encodeWithSelector(ISavingsLike.redeem.selector, sUSDS.convertToShares(400_000e18), dan, address(grPrime)),
            ""
        );

        vm.mockCallRevert(
            address(sUSDS),
            abi.encodeWithSelector(ISavingsLike.redeem.selector, sUSDS.convertToShares(500_000e18), bob, address(grPrime)),
            ""
        );

        vm.mockCallRevert(
            address(sUSDS),
            abi.encodeWithSelector(ISavingsLike.redeem.selector, sUSDS.convertToShares(700_000e18), ali, address(grPrime)),
            ""
        );

        vm.mockCallRevert(
            address(sUSDS),
            abi.encodeWithSelector(ISavingsLike.redeem.selector, sUSDS.convertToShares(800_000e18), dan, address(grPrime)),
            ""
        );
    }

    function test_processPendingDepositCancellations_infiniteMaxSavingsShares_infiniteMaxRequests() external {
        _setupMockCallReverts();

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ProcessPendingDepositCancellations(operator, type(uint256).max, type(uint256).max);

        // Deposit Request 0

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(ali, 100_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(0, ali, ali, sUSDS.convertToShares(100_000e18), 100_000e18 - 1);

        // Deposit Request 1

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(1, bob, bob, sUSDS.convertToShares(200_000e18), 200_000e18 - 1);

        // Deposit Request 2

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(2, cam, cam, sUSDS.convertToShares(300_000e18), 300_000e18 - 2);

        // Deposit Request 3

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(dan, 400_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(3, ali, dan, sUSDS.convertToShares(400_000e18), 400_000e18 - 1);

        // Deposit Request 4

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(bob, 500_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(4, bob, bob, sUSDS.convertToShares(500_000e18), 500_000e18 - 1);

        // Deposit Request 5

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(5, cam, cam, sUSDS.convertToShares(600_000e18), 600_000e18 - 2);

        // Deposit Request 6

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(ali, 700_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(6, ali, ali, sUSDS.convertToShares(700_000e18), 700_000e18 - 1);

        // Deposit Request 7

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(dan, 800_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(7, bob, dan, sUSDS.convertToShares(800_000e18), 800_000e18 - 1);

        // Deposit Request 8

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(8, cam, cam, sUSDS.convertToShares(900_000e18), 900_000e18 - 2);

        // Deposit Request 9

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(9, ali, ali, sUSDS.convertToShares(1_000_000e18), 1_000_000e18 - 1);

        vm.prank(operator);
        grPrime.processPendingDepositCancellations(type(uint256).max, type(uint256).max);

        uint256 totalClaimable = 100_000e18 + 400_000e18 + 500_000e18 + 700_000e18 + 800_000e18;

        vaultState.totalClaimable        += totalClaimable - 5;
        vaultState.availableLiquidAssets  = 0;

        vaultState.depositCancellationRequests.pendingShareValue = 0;
        vaultState.depositCancellationRequests.length            = 0;
        vaultState.depositCancellationRequests.firstPendingId    = 10;

        aliBalances.assets          += 1_000_000e18 - 1;
        aliBalances.claimableAssets += 100_000e18 + 700_000e18 - 2;

        bobBalances.assets          += 200_000e18 - 1;
        bobBalances.claimableAssets += 500_000e18 - 1;

        camBalances.assets += 300_000e18 + 600_000e18 + 900_000e18 - 6;

        danBalances.claimableAssets += 400_000e18 + 800_000e18 - 2;

        vaultBalances.assets            += totalClaimable - 5;
        vaultBalances.savingsShareValue  = 0;

        _assertVaultState();
        _assertAccountBalances(aliBalances);
        _assertAccountBalances(bobBalances);
        _assertAccountBalances(camBalances);
        _assertAccountBalances(danBalances);
        _assertAccountBalances(vaultBalances);

        for (uint256 i = 0; i < 10; i++) {
            vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
            grPrime.getPendingDepositCancellationRequest(i);
        }
    }

    function test_processPendingDepositCancellations_infiniteMaxSavingsShares_limitedMaxRequests() external {
        _setupMockCallReverts();

        uint256 maxRequests = 6;

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ProcessPendingDepositCancellations(operator, type(uint256).max, maxRequests);

        // Deposit Request 0

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(ali, 100_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(0, ali, ali, sUSDS.convertToShares(100_000e18), 100_000e18 - 1);

        // Deposit Request 1

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(1, bob, bob, sUSDS.convertToShares(200_000e18), 200_000e18 - 1);

        // Deposit Request 2

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(2, cam, cam, sUSDS.convertToShares(300_000e18), 300_000e18 - 2);

        // Deposit Request 3

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(dan, 400_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(3, ali, dan, sUSDS.convertToShares(400_000e18), 400_000e18 - 1);

        // Deposit Request 4

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(bob, 500_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(4, bob, bob, sUSDS.convertToShares(500_000e18), 500_000e18 - 1);

        // Deposit Request 5

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(5, cam, cam, sUSDS.convertToShares(600_000e18), 600_000e18 - 2);

        vm.prank(operator);
        grPrime.processPendingDepositCancellations(type(uint256).max, maxRequests);

        uint256 assetsWithdrawn = 100_000e18 + 200_000e18 + 300_000e18 + 400_000e18 + 500_000e18 + 600_000e18;
        uint256 totalClaimable  = 100_000e18 + 400_000e18 + 500_000e18;

        vaultState.totalClaimable        += totalClaimable - 3;
        vaultState.availableLiquidAssets -= assetsWithdrawn - 5;

        vaultState.depositCancellationRequests.pendingShareValue -= assetsWithdrawn - 5;
        vaultState.depositCancellationRequests.length            = 4;
        vaultState.depositCancellationRequests.firstPendingId    = 6;

        aliBalances.claimableAssets += 100_000e18 - 1;

        bobBalances.assets          += 200_000e18 - 1;
        bobBalances.claimableAssets += 500_000e18 - 1;

        camBalances.assets += 300_000e18 + 600_000e18 - 4;

        danBalances.claimableAssets += 400_000e18 - 1;

        vaultBalances.assets            += totalClaimable - 3;
        vaultBalances.savingsShareValue -= assetsWithdrawn - 5;

        _assertVaultState();
        _assertAccountBalances(aliBalances);
        _assertAccountBalances(bobBalances);
        _assertAccountBalances(camBalances);
        _assertAccountBalances(danBalances);
        _assertAccountBalances(vaultBalances);

        for (uint256 i = 0; i < 6; i++) {
            vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
            grPrime.getPendingDepositCancellationRequest(i);
        }

        _assertDepositCancellationRequest(6, ali, ali, 700_000e18 - 1);
        _assertDepositCancellationRequest(7, bob, dan, 800_000e18 - 1);
        _assertDepositCancellationRequest(8, cam, cam, 900_000e18 - 2);
        _assertDepositCancellationRequest(9, ali, ali, 1_000_000e18 - 1);
    }

    function test_processPendingDepositCancellations_limitedMaxSavingsShares_infiniteMaxRequests() external {
        _setupMockCallReverts();

        uint256 maxSavingsShares = sUSDS.convertToShares(2_000_000e18);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ProcessPendingDepositCancellations(operator, maxSavingsShares, type(uint256).max);

        // Deposit Request 0

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(ali, 100_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(0, ali, ali, sUSDS.convertToShares(100_000e18), 100_000e18 - 1);

        // Deposit Request 1

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(1, bob, bob, sUSDS.convertToShares(200_000e18), 200_000e18 - 1);

        // Deposit Request 2

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(2, cam, cam, sUSDS.convertToShares(300_000e18), 300_000e18 - 2);

        // Deposit Request 3

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(dan, 400_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(3, ali, dan, sUSDS.convertToShares(400_000e18), 400_000e18 - 1);

        // Deposit Request 4

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(bob, 500_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(4, bob, bob, sUSDS.convertToShares(500_000e18), 500_000e18 - 1);

        // Deposit Request 5

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(5, cam, cam, sUSDS.convertToShares(500_000e18) + 3, 500_000e18 + 2);  // Only 500k of the 600k is processed

        vm.prank(operator);
        grPrime.processPendingDepositCancellations(maxSavingsShares, type(uint256).max);

        uint256 assetsWithdrawn = 100_000e18 + 200_000e18 + 300_000e18 + 400_000e18 + 500_000e18 + 500_000e18;  // Only 500k of the last request is processed
        uint256 totalClaimable  = 100_000e18 + 400_000e18 + 500_000e18;

        vaultState.totalClaimable        += totalClaimable - 3;
        vaultState.availableLiquidAssets -= assetsWithdrawn - 1;

        vaultState.depositCancellationRequests.pendingShareValue -= assetsWithdrawn - 1;
        vaultState.depositCancellationRequests.length            = 5;
        vaultState.depositCancellationRequests.firstPendingId    = 5;

        aliBalances.claimableAssets += 100_000e18 - 1;

        bobBalances.assets          += 200_000e18 - 1;
        bobBalances.claimableAssets += 500_000e18 - 1;

        camBalances.assets += 300_000e18 + 500_000e18;

        danBalances.claimableAssets += 400_000e18 - 1;

        vaultBalances.assets            += totalClaimable - 3;
        vaultBalances.savingsShareValue -= assetsWithdrawn - 1;

        _assertVaultState();
        _assertAccountBalances(aliBalances);
        _assertAccountBalances(bobBalances);
        _assertAccountBalances(camBalances);
        _assertAccountBalances(danBalances);
        _assertAccountBalances(vaultBalances);

        for (uint256 i = 0; i < 5; i++) {
            vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
            grPrime.getPendingDepositCancellationRequest(i);
        }

        _assertDepositCancellationRequest(5, cam, cam, 100_000e18 - 4);
        _assertDepositCancellationRequest(6, ali, ali, 700_000e18 - 1);
        _assertDepositCancellationRequest(7, bob, dan, 800_000e18 - 1);
        _assertDepositCancellationRequest(8, cam, cam, 900_000e18 - 2);
        _assertDepositCancellationRequest(9, ali, ali, 1_000_000e18 - 1);
    }

    function test_processPendingDepositCancellations_multipleCalls() external {
        _setupMockCallReverts();

        uint256 maxSavingsShares = sUSDS.convertToShares(2_000_000e18);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ProcessPendingDepositCancellations(operator, maxSavingsShares, type(uint256).max);

        // Deposit Request 0

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(ali, 100_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(0, ali, ali, sUSDS.convertToShares(100_000e18), 100_000e18 - 1);

        // Deposit Request 1

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(1, bob, bob, sUSDS.convertToShares(200_000e18), 200_000e18 - 1);

        // Deposit Request 2

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(2, cam, cam, sUSDS.convertToShares(300_000e18), 300_000e18 - 2);

        // Deposit Request 3

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(dan, 400_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(3, ali, dan, sUSDS.convertToShares(400_000e18), 400_000e18 - 1);

        // Deposit Request 4

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(bob, 500_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(4, bob, bob, sUSDS.convertToShares(500_000e18), 500_000e18 - 1);

        // Deposit Request 5 (Partial)

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(5, cam, cam, sUSDS.convertToShares(500_000e18) + 3, 500_000e18 + 2);  // Only 500k of the 600k is processed

        vm.prank(operator);
        grPrime.processPendingDepositCancellations(maxSavingsShares, type(uint256).max);

        uint256 assetsWithdrawn = 100_000e18 + 200_000e18 + 300_000e18 + 400_000e18 + 500_000e18 + 500_000e18;  // Only 500k of the last request is processed
        uint256 totalClaimable  = 100_000e18 + 400_000e18 + 500_000e18;

        vaultState.totalClaimable        += totalClaimable - 3;
        vaultState.availableLiquidAssets -= assetsWithdrawn - 1;

        vaultState.depositCancellationRequests.pendingShareValue -= assetsWithdrawn - 1;
        vaultState.depositCancellationRequests.length             = 5;
        vaultState.depositCancellationRequests.firstPendingId     = 5;

        aliBalances.claimableAssets += 100_000e18 - 1;

        bobBalances.assets          += 200_000e18 - 1;
        bobBalances.claimableAssets += 500_000e18 - 1;

        camBalances.assets += 300_000e18 + 500_000e18;

        danBalances.claimableAssets += 400_000e18 - 1;

        vaultBalances.assets            += totalClaimable - 3;
        vaultBalances.savingsShareValue -= assetsWithdrawn - 1;

        _assertVaultState();
        _assertAccountBalances(aliBalances);
        _assertAccountBalances(bobBalances);
        _assertAccountBalances(camBalances);
        _assertAccountBalances(danBalances);
        _assertAccountBalances(vaultBalances);

        for (uint256 i = 0; i < 5; i++) {
            vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
            grPrime.getPendingDepositCancellationRequest(i);
        }

        _assertDepositCancellationRequest(5, cam, cam, 100_000e18 - 4);  // Partial fill
        _assertDepositCancellationRequest(6, ali, ali, 700_000e18 - 1);
        _assertDepositCancellationRequest(7, bob, dan, 800_000e18 - 1);
        _assertDepositCancellationRequest(8, cam, cam, 900_000e18 - 2);
        _assertDepositCancellationRequest(9, ali, ali, 1_000_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ProcessPendingDepositCancellations(operator, type(uint256).max, type(uint256).max);

        // Deposit Request 5 (Remainder)

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(5, cam, cam, sUSDS.convertToShares(100_000e18) - 3, 100_000e18 - 4);

        // Deposit Request 6

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(ali, 700_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(6, ali, ali, sUSDS.convertToShares(700_000e18), 700_000e18 - 1);

        // Deposit Request 7

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(dan, 800_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(7, bob, dan, sUSDS.convertToShares(800_000e18), 800_000e18 - 1);

        // Deposit Request 8

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(8, cam, cam, sUSDS.convertToShares(900_000e18), 900_000e18 - 2);

        // Deposit Request 9

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.DepositCancellation(9, ali, ali, sUSDS.convertToShares(1_000_000e18), 1_000_000e18 - 1);

        vm.prank(operator);
        grPrime.processPendingDepositCancellations(type(uint256).max, type(uint256).max);

        totalClaimable = 700_000e18 + 800_000e18;

        vaultState.totalClaimable        += totalClaimable - 2;
        vaultState.availableLiquidAssets  = 0;

        vaultState.depositCancellationRequests.pendingShareValue = 0;
        vaultState.depositCancellationRequests.length            = 0;
        vaultState.depositCancellationRequests.firstPendingId    = 10;

        aliBalances.assets          += 1_000_000e18 - 1;
        aliBalances.claimableAssets += 700_000e18 - 1;

        camBalances.assets += 100_000e18 + 900_000e18 - 6;

        danBalances.claimableAssets += 800_000e18 - 1;

        vaultBalances.assets            += totalClaimable - 2;
        vaultBalances.savingsShareValue  = 0;

        _assertVaultState();
        _assertAccountBalances(aliBalances);
        _assertAccountBalances(bobBalances);
        _assertAccountBalances(camBalances);
        _assertAccountBalances(danBalances);
        _assertAccountBalances(vaultBalances);

        for (uint256 i = 0; i < 10; i++) {
            vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
            grPrime.getPendingDepositCancellationRequest(i);
        }
    }

}

contract ProcessPendingRedeemsTests is GrovePrimeVaultTests {

    uint256 internal constant DUST = 10;

    address internal ali = makeAddr("ali");
    address internal bob = makeAddr("bob");
    address internal cam = makeAddr("cam");
    address internal dan = makeAddr("dan");

    AccountBalances internal aliBalances;
    AccountBalances internal bobBalances;
    AccountBalances internal camBalances;
    AccountBalances internal danBalances;
    AccountBalances internal vaultBalances;

    function setUp() public override {
        super.setUp();

        vm.label(ali, "ali");
        vm.label(bob, "bob");
        vm.label(cam, "cam");
        vm.label(dan, "dan");

        // All deposits will be filled instantly. Each deposit carries a few extra wei so that the
        // per-request `convertToShares` amounts below, rounded independently, never exceed the balance.

        _requestDeposit(ali, 100_000e18 + 400_000e18 + 700_000e18 + 1_000_000e18 + DUST);
        _requestDeposit(bob, 200_000e18 + 500_000e18 + 800_000e18 + DUST);
        _requestDeposit(cam, 300_000e18 + 600_000e18 + 900_000e18 + DUST);

        _requestRedeem(ali, ali, grPrime.convertToShares(100_000e18));  // Will fail
        _requestRedeem(bob, bob, grPrime.convertToShares(200_000e18));
        _requestRedeem(cam, cam, grPrime.convertToShares(300_000e18));
        _requestRedeem(ali, dan, grPrime.convertToShares(400_000e18));  // Will fail
        _requestRedeem(bob, bob, grPrime.convertToShares(500_000e18));  // Will fail
        _requestRedeem(cam, cam, grPrime.convertToShares(600_000e18));
        _requestRedeem(ali, ali, grPrime.convertToShares(700_000e18));  // Will fail
        _requestRedeem(bob, dan, grPrime.convertToShares(800_000e18));  // Will fail
        _requestRedeem(cam, cam, grPrime.convertToShares(900_000e18));
        _requestRedeem(ali, ali, grPrime.convertToShares(1_000_000e18));

        uint256 depositedAssets = 5_500_000e18 + 3 * DUST;

        uint256 targetAssets = 200_000e18 + 300_000e18 + 600_000e18 + 900_000e18 + 200_000e18;  // Only 200k of the last 1MM deposit

        _take(sUSDS.convertToShares(800_000e18));  // 800k so the last redeem cannot be fully fulfilled

        vaultState.rho                     = vm.getBlockTimestamp();
        vaultState.chi                     = 1.049999999999999999961070145e27;
        vaultState.totalAssets             = depositedAssets - 6;
        vaultState.availableCapacityValue -= depositedAssets - 6;
        vaultState.availableLiquidAssets   = depositedAssets - 800_000e18 - 2;

        vaultState.depositRequests.pendingShareValue = 0;
        vaultState.depositRequests.length            = 0;
        vaultState.depositRequests.firstPendingId    = 3;

        vaultState.redeemRequests.pendingShareValue = depositedAssets - 3 * DUST - 5;
        vaultState.redeemRequests.length            = 10;
        vaultState.redeemRequests.firstPendingId    = 0;

        aliBalances = AccountBalances({
            account           : ali,
            assets            : 0,
            shareValue        : 8,  // Leftover DUST, less rounding
            savingsShareValue : 0,
            claimableAssets   : 0
        });

        bobBalances = AccountBalances({
            account           : bob,
            assets            : 0,
            shareValue        : 9,  // Leftover DUST, less rounding
            savingsShareValue : 0,
            claimableAssets   : 0
        });

        camBalances = AccountBalances({
            account           : cam,
            assets            : 0,
            shareValue        : 10,  // Leftover DUST, less rounding
            savingsShareValue : 0,
            claimableAssets   : 0
        });

        danBalances = AccountBalances({
            account           : dan,
            assets            : 0,
            shareValue        : 0,
            savingsShareValue : 0,
            claimableAssets   : 0
        });

        vaultBalances = AccountBalances({
            account           : address(grPrime),
            assets            : 0,
            shareValue        : depositedAssets - 3 * DUST - 5,
            savingsShareValue : depositedAssets - 800_000e18 - 2,
            claimableAssets   : 0
        });

        _assertVaultState();

        _assertAccountBalances(aliBalances);
        _assertAccountBalances(bobBalances);
        _assertAccountBalances(camBalances);
        _assertAccountBalances(danBalances);
        _assertAccountBalances(vaultBalances);

        for (uint256 i = 0; i < 3; i++) {
            vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
            grPrime.getPendingDepositRequest(i);
        }

        _assertRedeemRequest(0, ali, ali, 100_000e18 - 1);
        _assertRedeemRequest(1, bob, bob, 200_000e18 - 1);
        _assertRedeemRequest(2, cam, cam, 300_000e18 - 1);
        _assertRedeemRequest(3, ali, dan, 400_000e18 - 1);
        _assertRedeemRequest(4, bob, bob, 500_000e18 - 1);
        _assertRedeemRequest(5, cam, cam, 600_000e18 - 1);
        _assertRedeemRequest(6, ali, ali, 700_000e18 - 1);
        _assertRedeemRequest(7, bob, dan, 800_000e18 - 1);
        _assertRedeemRequest(8, cam, cam, 900_000e18 - 1);
        _assertRedeemRequest(9, ali, ali, 1_000_000e18 - 1);
    }

    function test_processPendingRedeems_fallbackWithdrawReverts() external {
        vm.mockCallRevert(
            address(sUSDS),
            abi.encodeWithSelector(ISavingsLike.withdraw.selector, 100_000e18 - 1, ali, address(grPrime)),
            ""
        );

        vm.mockCallRevert(
            address(sUSDS),
            abi.encodeWithSelector(ISavingsLike.withdraw.selector, 100_000e18 - 1, address(grPrime), address(grPrime)),
            "withdraw-to-vault-reverts"
        );

        vm.expectRevert(bytes("withdraw-to-vault-reverts"));
        vm.prank(operator);
        grPrime.processPendingRedeems(type(uint256).max, type(uint256).max);
    }

    function _setupMockCallReverts() internal {
        vm.mockCallRevert(
            address(sUSDS),
            abi.encodeWithSelector(ISavingsLike.withdraw.selector, 100_000e18 - 1, ali, address(grPrime)),
            ""
        );

        vm.mockCallRevert(
            address(sUSDS),
            abi.encodeWithSelector(ISavingsLike.withdraw.selector, 400_000e18 - 1, dan, address(grPrime)),
            ""
        );

        vm.mockCallRevert(
            address(sUSDS),
            abi.encodeWithSelector(ISavingsLike.withdraw.selector, 500_000e18 - 1, bob, address(grPrime)),
            ""
        );

        vm.mockCallRevert(
            address(sUSDS),
            abi.encodeWithSelector(ISavingsLike.withdraw.selector, 700_000e18 - 1, ali, address(grPrime)),
            ""
        );

        vm.mockCallRevert(
            address(sUSDS),
            abi.encodeWithSelector(ISavingsLike.withdraw.selector, 800_000e18 - 1, dan, address(grPrime)),
            ""
        );
    }

    function test_processPendingRedeems_infiniteMaxShares_infiniteMaxRequests() external {
        _setupMockCallReverts();

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ProcessPendingRedeems(operator, type(uint256).max, type(uint256).max);

        // Redeem Request 0

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(100_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(ali, 100_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(0, ali, ali, grPrime.convertToShares(100_000e18), sUSDS.convertToShares(100_000e18), 100_000e18 - 1);

        // Redeem Request 1

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(200_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(1, bob, bob, grPrime.convertToShares(200_000e18), sUSDS.convertToShares(200_000e18), 200_000e18 - 1);

        // Redeem Request 2

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(300_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(2, cam, cam, grPrime.convertToShares(300_000e18), sUSDS.convertToShares(300_000e18) + 1, 300_000e18 - 1);

        // Redeem Request 3

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(400_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(dan, 400_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(3, ali, dan, grPrime.convertToShares(400_000e18), sUSDS.convertToShares(400_000e18), 400_000e18 - 1);

        // Redeem Request 4

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(500_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(bob, 500_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(4, bob, bob, grPrime.convertToShares(500_000e18), sUSDS.convertToShares(500_000e18), 500_000e18 - 1);

        // Redeem Request 5

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(600_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(5, cam, cam, grPrime.convertToShares(600_000e18), sUSDS.convertToShares(600_000e18) + 1, 600_000e18 - 1);

        // Redeem Request 6

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(700_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(ali, 700_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(6, ali, ali, grPrime.convertToShares(700_000e18), sUSDS.convertToShares(700_000e18), 700_000e18 - 1);

        // Redeem Request 7

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(800_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(dan, 800_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(7, bob, dan, grPrime.convertToShares(800_000e18), sUSDS.convertToShares(800_000e18), 800_000e18 - 1);

        // Redeem Request 8

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(900_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(8, cam, cam, grPrime.convertToShares(900_000e18), sUSDS.convertToShares(900_000e18) + 1, 900_000e18 - 1);

        // Redeem Request 9

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(200_000e18) + 29);  // Only ~200k of the last 1MM deposit

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(9, ali, ali, grPrime.convertToShares(200_000e18) + 29, sUSDS.convertToShares(200_000e18) + 27, 200_000e18 + 30);  // Includes the 3 * DUST

        vm.prank(operator);
        grPrime.processPendingRedeems(type(uint256).max, type(uint256).max);

        uint256 assetsRedeemed = 5_500_000e18 - 800_000e18;
        uint256 totalClaimable = 100_000e18 + 400_000e18 + 500_000e18 + 700_000e18 + 800_000e18;

        vaultState.totalAssets             = 800_000e18 - 3;
        vaultState.totalClaimable         += totalClaimable - 5;
        vaultState.availableCapacityValue += assetsRedeemed + 3 * DUST - 4;
        vaultState.availableLiquidAssets   = 1;

        vaultState.redeemRequests.pendingShareValue -= assetsRedeemed + 3 * DUST - 4;
        vaultState.redeemRequests.length             = 1;
        vaultState.redeemRequests.firstPendingId     = 9;

        aliBalances.assets          += 200_000e18 + 3 * DUST;
        aliBalances.claimableAssets += 100_000e18 + 700_000e18 - 2;

        bobBalances.assets          += 200_000e18 - 1;
        bobBalances.claimableAssets += 500_000e18 - 1;

        camBalances.assets += 300_000e18 + 600_000e18 + 900_000e18 - 3;

        danBalances.claimableAssets += 400_000e18 + 800_000e18 - 2;

        vaultBalances.assets            += totalClaimable - 5;
        vaultBalances.shareValue        -= assetsRedeemed + 3 * DUST - 4;
        vaultBalances.savingsShareValue  = 1;

        _assertVaultState();
        _assertAccountBalances(aliBalances);
        _assertAccountBalances(bobBalances);
        _assertAccountBalances(camBalances);
        _assertAccountBalances(danBalances);
        _assertAccountBalances(vaultBalances);

        for (uint256 i = 0; i < 9; i++) {
            vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
            grPrime.getPendingRedeemRequest(i);
        }

        _assertRedeemRequest(9, ali, ali, 800_000e18 - 3 * DUST - 1);  // Partial fill
    }

    function test_processPendingRedeems_infiniteMaxShares_limitedMaxRequests() external {
        _setupMockCallReverts();

        uint256 maxRequests = 6;

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ProcessPendingRedeems(operator, type(uint256).max, maxRequests);

        // Redeem Request 0

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(100_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(ali, 100_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(0, ali, ali, grPrime.convertToShares(100_000e18), sUSDS.convertToShares(100_000e18), 100_000e18 - 1);

        // Redeem Request 1

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(200_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(1, bob, bob, grPrime.convertToShares(200_000e18), sUSDS.convertToShares(200_000e18), 200_000e18 - 1);

        // Redeem Request 2

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(300_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(2, cam, cam, grPrime.convertToShares(300_000e18), sUSDS.convertToShares(300_000e18) + 1, 300_000e18 - 1);

        // Redeem Request 3

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(400_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(dan, 400_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(3, ali, dan, grPrime.convertToShares(400_000e18), sUSDS.convertToShares(400_000e18), 400_000e18 - 1);

        // Redeem Request 4

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(500_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(bob, 500_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(4, bob, bob, grPrime.convertToShares(500_000e18), sUSDS.convertToShares(500_000e18), 500_000e18 - 1);

        // Redeem Request 5

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(600_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(5, cam, cam, grPrime.convertToShares(600_000e18), sUSDS.convertToShares(600_000e18) + 1, 600_000e18 - 1);

        vm.prank(operator);
        grPrime.processPendingRedeems(type(uint256).max, maxRequests);

        uint256 assetsRedeemed = 100_000e18 + 200_000e18 + 300_000e18 + 400_000e18 + 500_000e18 + 600_000e18;
        uint256 totalClaimable = 100_000e18 + 400_000e18 + 500_000e18;

        vaultState.totalAssets            -= assetsRedeemed - 3;
        vaultState.totalClaimable         += totalClaimable - 3;
        vaultState.availableCapacityValue += assetsRedeemed - 3;
        vaultState.availableLiquidAssets  -= assetsRedeemed - 2;

        vaultState.redeemRequests.pendingShareValue -= assetsRedeemed - 3;
        vaultState.redeemRequests.length             = 4;
        vaultState.redeemRequests.firstPendingId     = 6;

        aliBalances.claimableAssets += 100_000e18 - 1;

        bobBalances.assets          += 200_000e18 - 1;
        bobBalances.claimableAssets += 500_000e18 - 1;

        camBalances.assets += 300_000e18 + 600_000e18 - 2;

        danBalances.claimableAssets += 400_000e18 - 1;

        vaultBalances.assets            += totalClaimable - 3;
        vaultBalances.shareValue        -= assetsRedeemed - 3;
        vaultBalances.savingsShareValue -= assetsRedeemed - 2;

        _assertVaultState();
        _assertAccountBalances(aliBalances);
        _assertAccountBalances(bobBalances);
        _assertAccountBalances(camBalances);
        _assertAccountBalances(danBalances);
        _assertAccountBalances(vaultBalances);

        for (uint256 i = 0; i < 6; i++) {
            vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
            grPrime.getPendingRedeemRequest(i);
        }

        _assertRedeemRequest(6, ali, ali, 700_000e18 - 1);
        _assertRedeemRequest(7, bob, dan, 800_000e18 - 1);
        _assertRedeemRequest(8, cam, cam, 900_000e18 - 1);
        _assertRedeemRequest(9, ali, ali, 1_000_000e18 - 1);
    }

    function test_processPendingRedeems_limitedMaxShares_infiniteMaxRequests() external {
        _setupMockCallReverts();

        uint256 maxShares = grPrime.convertToShares(2_000_000e18);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ProcessPendingRedeems(operator, maxShares, type(uint256).max);

        // Redeem Request 0

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(100_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(ali, 100_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(0, ali, ali, grPrime.convertToShares(100_000e18), sUSDS.convertToShares(100_000e18), 100_000e18 - 1);

        // Redeem Request 1

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(200_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(1, bob, bob, grPrime.convertToShares(200_000e18), sUSDS.convertToShares(200_000e18), 200_000e18 - 1);

        // Redeem Request 2

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(300_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(2, cam, cam, grPrime.convertToShares(300_000e18), sUSDS.convertToShares(300_000e18) + 1, 300_000e18 - 1);

        // Redeem Request 3

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(400_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(dan, 400_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(3, ali, dan, grPrime.convertToShares(400_000e18), sUSDS.convertToShares(400_000e18), 400_000e18 - 1);

        // Redeem Request 4

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(500_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(bob, 500_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(4, bob, bob, grPrime.convertToShares(500_000e18), sUSDS.convertToShares(500_000e18), 500_000e18 - 1);

        // Redeem Request 5

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(500_000e18) + 2);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(5, cam, cam, grPrime.convertToShares(500_000e18) + 2, sUSDS.convertToShares(500_000e18) + 2, 500_000e18 + 1);

        vm.prank(operator);
        grPrime.processPendingRedeems(maxShares, type(uint256).max);

        uint256 assetsRedeemed = 2_000_000e18;
        uint256 totalClaimable = 100_000e18 + 400_000e18 + 500_000e18;

        vaultState.totalAssets            -= assetsRedeemed - 1;
        vaultState.totalClaimable         += totalClaimable - 3;
        vaultState.availableCapacityValue += assetsRedeemed - 1;
        vaultState.availableLiquidAssets  -= assetsRedeemed;

        vaultState.redeemRequests.pendingShareValue -= assetsRedeemed - 1;
        vaultState.redeemRequests.length             = 5;
        vaultState.redeemRequests.firstPendingId     = 5;

        aliBalances.claimableAssets += 100_000e18 - 1;

        bobBalances.assets          += 200_000e18 - 1;
        bobBalances.claimableAssets += 500_000e18 - 1;

        camBalances.assets += 300_000e18 + 500_000e18;

        danBalances.claimableAssets += 400_000e18 - 1;

        vaultBalances.assets            += totalClaimable - 3;
        vaultBalances.shareValue        -= assetsRedeemed - 1;
        vaultBalances.savingsShareValue -= assetsRedeemed;

        _assertVaultState();
        _assertAccountBalances(aliBalances);
        _assertAccountBalances(bobBalances);
        _assertAccountBalances(camBalances);
        _assertAccountBalances(danBalances);
        _assertAccountBalances(vaultBalances);

        for (uint256 i = 0; i < 5; i++) {
            vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
            grPrime.getPendingRedeemRequest(i);
        }

        _assertRedeemRequest(5, cam, cam, 100_000e18 - 3);  // 500k out of 600k redeemed
        _assertRedeemRequest(6, ali, ali, 700_000e18 - 1);
        _assertRedeemRequest(7, bob, dan, 800_000e18 - 1);
        _assertRedeemRequest(8, cam, cam, 900_000e18 - 1);
        _assertRedeemRequest(9, ali, ali, 1_000_000e18 - 1);
    }

    function test_processPendingRedeems_multipleCalls() external {
        _setupMockCallReverts();

        uint256 maxShares = grPrime.convertToShares(2_000_000e18);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ProcessPendingRedeems(operator, maxShares, type(uint256).max);

        // Redeem Request 0

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(100_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(ali, 100_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(0, ali, ali, grPrime.convertToShares(100_000e18), sUSDS.convertToShares(100_000e18), 100_000e18 - 1);

        // Redeem Request 1

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(200_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(1, bob, bob, grPrime.convertToShares(200_000e18), sUSDS.convertToShares(200_000e18), 200_000e18 - 1);

        // Redeem Request 2

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(300_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(2, cam, cam, grPrime.convertToShares(300_000e18), sUSDS.convertToShares(300_000e18) + 1, 300_000e18 - 1);

        // Redeem Request 3

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(400_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(dan, 400_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(3, ali, dan, grPrime.convertToShares(400_000e18), sUSDS.convertToShares(400_000e18), 400_000e18 - 1);

        // Redeem Request 4

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(500_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(bob, 500_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(4, bob, bob, grPrime.convertToShares(500_000e18), sUSDS.convertToShares(500_000e18), 500_000e18 - 1);

        // Redeem Request 5 (Partial)

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(500_000e18) + 2);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(5, cam, cam, grPrime.convertToShares(500_000e18) + 2, sUSDS.convertToShares(500_000e18) + 2, 500_000e18 + 1);  // Only 500k of the 600k is processed

        vm.prank(operator);
        grPrime.processPendingRedeems(maxShares, type(uint256).max);

        uint256 assetsRedeemed = 100_000e18 + 200_000e18 + 300_000e18 + 400_000e18 + 500_000e18 + 500_000e18;  // Only 500k of the last request is processed
        uint256 totalClaimable = 100_000e18 + 400_000e18 + 500_000e18;

        vaultState.totalAssets            -= assetsRedeemed - 1;
        vaultState.totalClaimable         += totalClaimable - 3;
        vaultState.availableCapacityValue += assetsRedeemed - 1;
        vaultState.availableLiquidAssets  -= assetsRedeemed;

        vaultState.redeemRequests.pendingShareValue -= assetsRedeemed - 1;
        vaultState.redeemRequests.length             = 5;
        vaultState.redeemRequests.firstPendingId     = 5;

        aliBalances.claimableAssets += 100_000e18 - 1;

        bobBalances.assets          += 200_000e18 - 1;
        bobBalances.claimableAssets += 500_000e18 - 1;

        camBalances.assets += 300_000e18 + 500_000e18;

        danBalances.claimableAssets += 400_000e18 - 1;

        vaultBalances.assets            += totalClaimable - 3;
        vaultBalances.shareValue        -= assetsRedeemed - 1;
        vaultBalances.savingsShareValue -= assetsRedeemed;

        _assertVaultState();
        _assertAccountBalances(aliBalances);
        _assertAccountBalances(bobBalances);
        _assertAccountBalances(camBalances);
        _assertAccountBalances(danBalances);
        _assertAccountBalances(vaultBalances);

        for (uint256 i = 0; i < 5; i++) {
            vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
            grPrime.getPendingRedeemRequest(i);
        }

        _assertRedeemRequest(5, cam, cam, 100_000e18 - 3);  // Partial fill
        _assertRedeemRequest(6, ali, ali, 700_000e18 - 1);
        _assertRedeemRequest(7, bob, dan, 800_000e18 - 1);
        _assertRedeemRequest(8, cam, cam, 900_000e18 - 1);
        _assertRedeemRequest(9, ali, ali, 1_000_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ProcessPendingRedeems(operator, type(uint256).max, type(uint256).max);

        // Redeem Request 5 (Remainder)

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(100_000e18) - 2);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(5, cam, cam, grPrime.convertToShares(100_000e18) - 2, sUSDS.convertToShares(100_000e18) - 2, 100_000e18 - 3);

        // Redeem Request 6

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(700_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(ali, 700_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(6, ali, ali, grPrime.convertToShares(700_000e18), sUSDS.convertToShares(700_000e18), 700_000e18 - 1);

        // Redeem Request 7

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(800_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.ClaimableAssetsIncreased(dan, 800_000e18 - 1);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(7, bob, dan, grPrime.convertToShares(800_000e18), sUSDS.convertToShares(800_000e18), 800_000e18 - 1);

        // Redeem Request 8

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(900_000e18));

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(8, cam, cam, grPrime.convertToShares(900_000e18), sUSDS.convertToShares(900_000e18) + 1, 900_000e18 - 1);

        // Redeem Request 9 (Partial)

        vm.expectEmit(address(grPrime));
        emit IERC20.Transfer(address(grPrime), address(0), grPrime.convertToShares(200_000e18) + 30);  // Only ~200k of the last 1MM deposit

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Redeem(9, ali, ali, grPrime.convertToShares(200_000e18) + 30, sUSDS.convertToShares(200_000e18) + 28, 200_000e18 + 31);  // Includes the 3 * DUST

        vm.prank(operator);
        grPrime.processPendingRedeems(type(uint256).max, type(uint256).max);

        assetsRedeemed = 100_000e18 + 700_000e18 + 800_000e18 + 900_000e18 + 200_000e18;  // Remaining ~100k of request 5, then only ~200k of the last 1MM deposit
        totalClaimable = 700_000e18 + 800_000e18;

        vaultState.totalAssets             = 800_000e18 - 4;
        vaultState.totalClaimable         += totalClaimable - 2;
        vaultState.availableCapacityValue += assetsRedeemed + 3 * DUST - 2;
        vaultState.availableLiquidAssets   = 1;

        vaultState.redeemRequests.pendingShareValue -= assetsRedeemed + 3 * DUST - 2;
        vaultState.redeemRequests.length             = 1;
        vaultState.redeemRequests.firstPendingId     = 9;

        aliBalances.assets          += 200_000e18 + 3 * DUST + 1;
        aliBalances.claimableAssets += 700_000e18 - 1;

        camBalances.assets += 100_000e18 + 900_000e18 - 4;

        danBalances.claimableAssets += 800_000e18 - 1;

        vaultBalances.assets            += totalClaimable - 2;
        vaultBalances.shareValue        -= assetsRedeemed + 3 * DUST - 2;
        vaultBalances.savingsShareValue  = 1;

        _assertVaultState();
        _assertAccountBalances(aliBalances);
        _assertAccountBalances(bobBalances);
        _assertAccountBalances(camBalances);
        _assertAccountBalances(danBalances);
        _assertAccountBalances(vaultBalances);

        for (uint256 i = 0; i < 9; i++) {
            vm.expectRevert(IGrovePrimeVault.InvalidRequestId.selector);
            grPrime.getPendingRedeemRequest(i);
        }

        _assertRedeemRequest(9, ali, ali, 800_000e18 - 3 * DUST - 2);  // Partial fill
    }

}
