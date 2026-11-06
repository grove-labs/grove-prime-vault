// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { stdError }               from "../lib/forge-std/src/StdError.sol";
import { stdStorage, StdStorage } from "../lib/forge-std/src/StdStorage.sol";

import { IAccessControl } from "../lib/oz/contracts/access/IAccessControl.sol";
import { IERC1967 }       from "../lib/oz/contracts/interfaces/IERC1967.sol";

import { TestBase } from "./TestBase.t.sol";

import { IGrovePrimeVault } from "../src/IGrovePrimeVault.sol";
import { GrovePrimeVault }  from "../src/GrovePrimeVault.sol";

contract RoleBasedTests is TestBase {

    using stdStorage for StdStorage;

    address internal user         = makeAddr("user");
    address internal unauthorized = makeAddr("unauthorized");

    function _notAuthorized(address account, bytes32 role) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            account,
            role
        );
    }

    /**********************************************************************************************/
    /*** grantRole tests                                                                        ***/
    /**********************************************************************************************/

    function test_grantRole_notAdmin() external {
        vm.expectRevert(_notAuthorized(unauthorized, DEFAULT_ADMIN_ROLE));
        vm.prank(unauthorized);
        grPrime.grantRole(OPERATOR_ROLE, operator);
    }

    function test_grantRole() external {
        address account = makeAddr("account");

        assertEq(grPrime.hasRole(OPERATOR_ROLE, account), false);

        vm.expectEmit(address(grPrime));
        emit IAccessControl.RoleGranted(OPERATOR_ROLE, account, admin);

        vm.prank(admin);
        grPrime.grantRole(OPERATOR_ROLE, account);

        assertEq(grPrime.hasRole(OPERATOR_ROLE, account), true);
    }

    /**********************************************************************************************/
    /*** revokeRole tests                                                                       ***/
    /**********************************************************************************************/

    function test_revokeRole_notAdmin() external {
        vm.expectRevert(_notAuthorized(unauthorized, DEFAULT_ADMIN_ROLE));
        vm.prank(unauthorized);
        grPrime.revokeRole(PAUSER_ROLE, pauser);
    }

    function test_revokeRole() external {
        assertEq(grPrime.hasRole(PAUSER_ROLE, pauser), true);

        vm.expectEmit(address(grPrime));
        emit IAccessControl.RoleRevoked(PAUSER_ROLE, pauser, admin);

        vm.prank(admin);
        grPrime.revokeRole(PAUSER_ROLE, pauser);

        assertEq(grPrime.hasRole(PAUSER_ROLE, pauser), false);
    }

    /**********************************************************************************************/
    /*** upgradeToAndCall tests                                                                 ***/
    /**********************************************************************************************/

    function test_upgradeToAndCall_notAdmin() external {
        address newImplementation = address(new GrovePrimeVault());

        vm.expectRevert(_notAuthorized(unauthorized, DEFAULT_ADMIN_ROLE));
        vm.prank(unauthorized);
        grPrime.upgradeToAndCall(newImplementation, "");
    }

    function test_upgradeToAndCall() external {
        address newImplementation = address(new GrovePrimeVault());

        assertNotEq(grPrime.implementation(), newImplementation);

        vm.expectEmit(address(grPrime));
        emit IERC1967.Upgraded(newImplementation);

        vm.prank(admin);
        grPrime.upgradeToAndCall(newImplementation, "");

        assertEq(grPrime.implementation(), newImplementation);
    }

    /**********************************************************************************************/
    /*** adjustTotalAssets tests                                                                ***/
    /**********************************************************************************************/

    function test_adjustTotalAssets_notLossManager() external {
        vm.expectRevert(_notAuthorized(user, LOSS_MANAGER_ROLE));
        vm.prank(user);
        grPrime.adjustTotalAssets(-1e18);
    }

    function test_adjustTotalAssets_isNotPaused() external {
        vm.expectRevert(IGrovePrimeVault.IsNotPaused.selector);
        vm.prank(lossManager);
        grPrime.adjustTotalAssets(-1e18);
    }

    function test_adjustTotalAssets_zeroDeltaTotalAssets() external {
        _pause();

        vm.expectRevert(IGrovePrimeVault.ZeroDeltaTotalAssets.selector);
        vm.prank(lossManager);
        grPrime.adjustTotalAssets(0);
    }

    function test_adjustTotalAssets_lossTooHighBoundary() external {
        _requestDeposit(user, 1_000_000e18);
        _pause();

        assertEq(grPrime.totalAssets(), 1_000_000e18 - 1);  // Rounding

        vm.expectRevert(IGrovePrimeVault.LossTooHigh.selector);
        vm.prank(lossManager);
        grPrime.adjustTotalAssets(-(1_000_000e18 - 1));

        vm.prank(lossManager);
        grPrime.adjustTotalAssets(-(1_000_000e18 - 2));
    }

    function test_adjustTotalAssets_zeroSupply() external {
        _pause();

        vm.expectRevert(stdError.divisionError);
        vm.prank(lossManager);
        grPrime.adjustTotalAssets(1e18);
    }

    function test_adjustTotalAssets_chiTooLowBoundary() external {
        _pause();

        // Inflate supply so that `totalAssets * RAY / totalSupply` can round down to zero.
        uint256 supply = 1e28;

        stdstore.target(address(grPrime)).sig("totalSupply()").checked_write(supply);

        int256 totalAssets = int256(grPrime.totalAssets());

        assertEq(uint256(totalAssets), supply);  // chi == RAY

        // totalAssets -> 9: chi = 9e27 / 1e28 = 0
        vm.expectRevert(IGrovePrimeVault.ChiTooLow.selector);
        vm.prank(lossManager);
        grPrime.adjustTotalAssets(-(totalAssets - 9));

        // totalAssets -> 10: chi = 10e27 / 1e28 = 1
        vm.prank(lossManager);
        grPrime.adjustTotalAssets(-(totalAssets - 10));

        assertEq(grPrime.chi(), 1);
    }

    function test_adjustTotalAssets_chiTooHighBoundary() external {
        _pause();

        // Small supply so that `totalAssets * RAY / totalSupply` can exceed uint256.max / RAY.
        uint256 supply = 1e8;

        stdstore.target(address(grPrime)).sig("totalSupply()").checked_write(supply);

        int256 totalAssets = int256(grPrime.totalAssets());

        assertEq(uint256(totalAssets), supply);  // chi == RAY

        // Largest totalAssets for which chi still does not exceed uint256.max / RAY.
        int256 maxTotalAssets = int256(type(uint256).max / RAY * supply / RAY);

        assertEq(uint256(maxTotalAssets), 11579208923731619542357098.500868e6);

        // chi = (maxTotalAssets + 1) * RAY / supply > uint256.max / RAY
        vm.expectRevert(IGrovePrimeVault.ChiTooHigh.selector);
        vm.prank(lossManager);
        grPrime.adjustTotalAssets(maxTotalAssets + 1 - totalAssets);

        // chi = maxTotalAssets * RAY / supply <= uint256.max / RAY
        vm.prank(lossManager);
        grPrime.adjustTotalAssets(maxTotalAssets - totalAssets);
    }

    function test_adjustTotalAssets_loss() external {
        uint256 loss = 100_000e18;

        _requestDeposit(user, 1_000_000e18);
        _pause();

        skip(365 days);

        uint192 chiBefore    = grPrime.nowChi();
        uint256 assetsBefore = grPrime.totalAssets();
        uint256 supply       = grPrime.totalSupply();

        // Drip is pending, adjustTotalAssets must settle it before writing chi down.
        assertEq(chiBefore,    1.049999999999999999961070145e27);  // ~5% APY
        assertEq(supply,       1_000_000e18 - 1);  // Rounding
        assertEq(assetsBefore, 1_050_000e18 - 38_931);  // Rounding, ~5% yield accrued

        assertEq(grPrime.rho(),          vm.getBlockTimestamp() - 365 days);
        assertEq(grPrime.assetsOf(user), assetsBefore);

        uint192 expectedChi = uint192(((assetsBefore - loss) * RAY) / supply);

        assertEq(expectedChi, 0.949999999999999999961069949e27);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.TotalAssetsAdjusted(lossManager, expectedChi, -int256(loss));

        vm.prank(lossManager);
        grPrime.adjustTotalAssets(-int256(loss));

        assertEq(grPrime.chi(),          expectedChi);
        assertEq(grPrime.rho(),          vm.getBlockTimestamp());
        assertEq(grPrime.totalAssets(),  950_000e18 - 38_932);  // Rounding, 100k loss incurred
        assertEq(grPrime.assetsOf(user), 950_000e18 - 38_932);  // Rounding, 100k loss incurred

        assertEq(grPrime.totalAssets(), assetsBefore - loss - 1);  // Rounding
    }

    function test_adjustTotalAssets_gain() external {
        uint256 gain = 100_000e18;

        _requestDeposit(user, 1_000_000e18);
        _pause();

        skip(365 days);

        uint192 chiBefore    = grPrime.nowChi();
        uint256 assetsBefore = grPrime.totalAssets();
        uint256 supply       = grPrime.totalSupply();

        // Drip is pending, adjustTotalAssets must settle it before writing chi up.
        assertEq(chiBefore,    1.049999999999999999961070145e27);  // ~5% APY
        assertEq(supply,       1_000_000e18 - 1);  // Rounding
        assertEq(assetsBefore, 1_050_000e18 - 38_931);  // Rounding, ~5% yield accrued

        assertEq(grPrime.rho(),          vm.getBlockTimestamp() - 365 days);
        assertEq(grPrime.assetsOf(user), assetsBefore);

        uint192 expectedChi = uint192(((assetsBefore + gain) * RAY) / supply);

        assertEq(expectedChi, 1.149999999999999999961070149e27);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.TotalAssetsAdjusted(lossManager, expectedChi, int256(gain));

        vm.prank(lossManager);
        grPrime.adjustTotalAssets(int256(gain));

        assertEq(grPrime.chi(),          expectedChi);
        assertEq(grPrime.rho(),          vm.getBlockTimestamp());
        assertEq(grPrime.totalAssets(),  1_150_000e18 - 38_932);  // Rounding, 100k gain realized
        assertEq(grPrime.assetsOf(user), 1_150_000e18 - 38_932);  // Rounding, 100k gain realized

        assertEq(grPrime.totalAssets(), assetsBefore + gain - 1);  // Rounding
    }

    function test_adjustTotalAssets_accrualContinuesFromNewChi() external {
        uint256 loss = 100_000e18;

        _requestDeposit(user, 1_000_000e18);
        _pause();

        uint192 chiBefore    = grPrime.nowChi();
        uint256 assetsBefore = grPrime.totalAssets();
        uint256 supply       = grPrime.totalSupply();

        // No time has passed, nothing to drip.
        assertEq(chiBefore,    1e27);
        assertEq(supply,       1_000_000e18 - 1);  // Rounding
        assertEq(assetsBefore, 1_000_000e18 - 1);  // Rounding

        assertEq(grPrime.rho(),          vm.getBlockTimestamp());
        assertEq(grPrime.assetsOf(user), assetsBefore);

        uint192 expectedChi = uint192(((assetsBefore - loss) * RAY) / supply);

        assertEq(expectedChi, 0.899999999999999999999999899e27);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.TotalAssetsAdjusted(lossManager, expectedChi, -int256(loss));

        vm.prank(lossManager);
        grPrime.adjustTotalAssets(-int256(loss));

        assertEq(grPrime.chi(),          expectedChi);
        assertEq(grPrime.rho(),          vm.getBlockTimestamp());
        assertEq(grPrime.totalAssets(),  900_000e18 - 2);  // Rounding, 100k loss incurred
        assertEq(grPrime.assetsOf(user), 900_000e18 - 2);  // Rounding, 100k loss incurred

        skip(365 days);

        grPrime.drip();

        // 5% APY over one year, compounding on the new chi
        assertEq(grPrime.chi(),          0.944999999999999999964963024e27);
        assertEq(grPrime.rho(),          vm.getBlockTimestamp());
        assertEq(grPrime.totalAssets(),  945_000e18 - 35_038);  // Rounding, 5% yield on 900k
        assertEq(grPrime.assetsOf(user), 945_000e18 - 35_038);  // Rounding, 5% yield on 900k

        assertEq(grPrime.chi(), 1.049999999999999999961070145e27 * expectedChi / RAY);
    }

    function test_adjustTotalAssets_redeemReflectsLoss() external {
        uint256 loss = 100_000e18;

        _requestDeposit(user, 1_000_000e18);
        _pause();

        uint192 chiBefore    = grPrime.nowChi();
        uint256 assetsBefore = grPrime.totalAssets();
        uint256 supply       = grPrime.totalSupply();

        // No time has passed, nothing to drip.
        assertEq(chiBefore,    1e27);
        assertEq(supply,       1_000_000e18 - 1);  // Rounding
        assertEq(assetsBefore, 1_000_000e18 - 1);  // Rounding

        assertEq(grPrime.rho(),          vm.getBlockTimestamp());
        assertEq(grPrime.assetsOf(user), assetsBefore);

        uint192 expectedChi = uint192(((assetsBefore - loss) * RAY) / supply);

        assertEq(expectedChi, 0.899999999999999999999999899e27);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.TotalAssetsAdjusted(lossManager, expectedChi, -int256(loss));

        vm.prank(lossManager);
        grPrime.adjustTotalAssets(-int256(loss));

        assertEq(grPrime.chi(),          expectedChi);
        assertEq(grPrime.rho(),          vm.getBlockTimestamp());
        assertEq(grPrime.totalAssets(),  900_000e18 - 2);  // Rounding, 100k loss incurred
        assertEq(grPrime.assetsOf(user), 900_000e18 - 2);  // Rounding, 100k loss incurred

        _unpause();

        assertEq(grPrime.balanceOf(user),       supply);
        assertEq(grPrime.pendingRedeemShares(), 0);
        assertEq(usds.balanceOf(user),          0);

        _requestRedeem(user, supply);

        assertEq(grPrime.balanceOf(user),       0);
        assertEq(grPrime.pendingRedeemShares(), supply);
        assertEq(usds.balanceOf(user),          0);

        _processPendingRedeems();

        // User receives the post-loss value of their shares, not the 1M deposited.
        assertEq(grPrime.balanceOf(user),       0);
        assertEq(grPrime.pendingRedeemShares(), 0);
        assertEq(grPrime.totalSupply(),         0);
        assertEq(grPrime.totalAssets(),         0);
        assertEq(usds.balanceOf(user),          900_000e18 - 2);  // Rounding, 100k loss incurred
    }

    /**********************************************************************************************/
    /*** setCapacity tests                                                                      ***/
    /**********************************************************************************************/

    function test_setCapacity_notOperator() external {
        vm.expectRevert(_notAuthorized(unauthorized, OPERATOR_ROLE));
        vm.prank(unauthorized);
        grPrime.setCapacity(2_000_000e18);
    }

    function test_setCapacity() external {
        assertEq(grPrime.maxCapacity(),       100_000_000e18);
        assertEq(grPrime.availableCapacity(), 100_000_000e18);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.CapacitySet(operator, 2_000_000e18);

        vm.prank(operator);
        grPrime.setCapacity(2_000_000e18);

        assertEq(grPrime.maxCapacity(),       2_000_000e18);
        assertEq(grPrime.availableCapacity(), 2_000_000e18);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.CapacitySet(operator, type(uint256).max);

        vm.prank(operator);
        grPrime.setCapacity(type(uint256).max);

        assertEq(grPrime.maxCapacity(),       type(uint256).max);
        assertEq(grPrime.availableCapacity(), type(uint256).max);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.CapacitySet(operator, 0);

        vm.prank(operator);
        grPrime.setCapacity(0);

        assertEq(grPrime.maxCapacity(),       0);
        assertEq(grPrime.availableCapacity(), 0);
    }

    /**********************************************************************************************/
    /*** setMaxRedeemFeeRate tests                                                              ***/
    /**********************************************************************************************/

    function test_setMaxRedeemFeeRate_notAdmin() external {
        vm.expectRevert(_notAuthorized(unauthorized, DEFAULT_ADMIN_ROLE));
        vm.prank(unauthorized);
        grPrime.setMaxRedeemFeeRate(0.01e18);
    }

    function test_setMaxRedeemFeeRate_maxFeeTooHighBoundary() external {
        vm.expectRevert(IGrovePrimeVault.MaxFeeTooHigh.selector);
        vm.prank(admin);
        grPrime.setMaxRedeemFeeRate(0.01e18 + 1);

        vm.prank(admin);
        grPrime.setMaxRedeemFeeRate(0.01e18);  // MAX_REDEEM_FEE is 1%
    }

    function test_setMaxRedeemFeeRate() external {
        assertEq(grPrime.maxRedeemFeeRate(), 0);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.MaxRedeemFeeRateSet(admin, 0.01e18);

        vm.prank(admin);
        grPrime.setMaxRedeemFeeRate(0.01e18);

        assertEq(grPrime.maxRedeemFeeRate(), 0.01e18);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.MaxRedeemFeeRateSet(admin, 0);

        vm.prank(admin);
        grPrime.setMaxRedeemFeeRate(0);

        assertEq(grPrime.maxRedeemFeeRate(), 0);
    }

    /**********************************************************************************************/
    /*** setMinDeposit tests                                                                    ***/
    /**********************************************************************************************/

    function test_setMinDeposit_notAdmin() external {
        vm.expectRevert(_notAuthorized(unauthorized, DEFAULT_ADMIN_ROLE));
        vm.prank(unauthorized);
        grPrime.setMinDeposit(100e18);
    }

    function test_setMinDeposit_zeroMinDeposit() external {
        vm.expectRevert(IGrovePrimeVault.ZeroMinDeposit.selector);
        vm.prank(admin);
        grPrime.setMinDeposit(0);
    }

    function test_setMinDeposit() external {
        assertEq(grPrime.minDeposit(), MINIMUM_DEPOSIT);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.MinDepositSet(admin, 100e18);

        vm.prank(admin);
        grPrime.setMinDeposit(100e18);

        assertEq(grPrime.minDeposit(), 100e18);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.MinDepositSet(admin, 1);

        vm.prank(admin);
        grPrime.setMinDeposit(1);

        assertEq(grPrime.minDeposit(), 1);
    }

    /**********************************************************************************************/
    /*** setMinDepositCancellation tests                                                        ***/
    /**********************************************************************************************/

    function test_setMinDepositCancellation_notAdmin() external {
        vm.expectRevert(_notAuthorized(unauthorized, DEFAULT_ADMIN_ROLE));
        vm.prank(unauthorized);
        grPrime.setMinDepositCancellation(100e18);
    }

    function test_setMinDepositCancellation_zeroMinDepositCancellation() external {
        vm.expectRevert(IGrovePrimeVault.ZeroMinDepositCancellation.selector);
        vm.prank(admin);
        grPrime.setMinDepositCancellation(0);
    }

    function test_setMinDepositCancellation() external {
        assertEq(grPrime.minDepositCancellation(), MINIMUM_DEPOSIT_CANCELLATION);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.MinDepositCancellationSet(admin, 200e18);

        vm.prank(admin);
        grPrime.setMinDepositCancellation(200e18);

        assertEq(grPrime.minDepositCancellation(), 200e18);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.MinDepositCancellationSet(admin, 1);

        vm.prank(admin);
        grPrime.setMinDepositCancellation(1);

        assertEq(grPrime.minDepositCancellation(), 1);
    }

    /**********************************************************************************************/
    /*** setMinRedeem tests                                                                     ***/
    /**********************************************************************************************/

    function test_setMinRedeem_notAdmin() external {
        vm.expectRevert(_notAuthorized(unauthorized, DEFAULT_ADMIN_ROLE));
        vm.prank(unauthorized);
        grPrime.setMinRedeem(100e18);
    }

    function test_setMinRedeem_zeroMinRedeem() external {
        vm.expectRevert(IGrovePrimeVault.ZeroMinRedeem.selector);
        vm.prank(admin);
        grPrime.setMinRedeem(0);
    }

    function test_setMinRedeem() external {
        assertEq(grPrime.minRedeem(), MINIMUM_REDEEM);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.MinRedeemSet(admin, 100e18);

        vm.prank(admin);
        grPrime.setMinRedeem(100e18);

        assertEq(grPrime.minRedeem(), 100e18);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.MinRedeemSet(admin, 1);

        vm.prank(admin);
        grPrime.setMinRedeem(1);

        assertEq(grPrime.minRedeem(), 1);
    }

    /**********************************************************************************************/
    /*** setVSRBounds tests                                                                     ***/
    /**********************************************************************************************/

    function test_setVSRBounds_notAdmin() external {
        vm.expectRevert(_notAuthorized(unauthorized, DEFAULT_ADMIN_ROLE));
        vm.prank(unauthorized);
        grPrime.setVSRBounds({ minVSR_ : RAY, maxVSR_ : FOUR_PCT_VSR });
    }

    function test_setVSRBounds_minVSRTooLowBoundary() external {
        vm.expectRevert(IGrovePrimeVault.MinVSRTooLow.selector);
        vm.prank(admin);
        grPrime.setVSRBounds({ minVSR_ : RAY - 1, maxVSR_ : FOUR_PCT_VSR });

        vm.prank(admin);
        grPrime.setVSRBounds({ minVSR_ : RAY, maxVSR_ : FOUR_PCT_VSR });
    }

    function test_setVSRBounds_maxVSRTooHighBoundary() external {
        uint256 maxVsr = grPrime.MAX_VSR();

        vm.expectRevert(IGrovePrimeVault.MaxVSRTooHigh.selector);
        vm.prank(admin);
        grPrime.setVSRBounds({ minVSR_ : RAY, maxVSR_ : maxVsr + 1 });

        vm.prank(admin);
        grPrime.setVSRBounds({ minVSR_ : RAY, maxVSR_ : maxVsr });
    }

    function test_setVSRBounds_minVSRGtMaxVSRBoundary() external {
        vm.expectRevert(IGrovePrimeVault.MinVSRGtMaxVSR.selector);
        vm.prank(admin);
        grPrime.setVSRBounds({ minVSR_ : FOUR_PCT_VSR + 1, maxVSR_ : FOUR_PCT_VSR });

        vm.prank(admin);
        grPrime.setVSRBounds({ minVSR_ : FOUR_PCT_VSR, maxVSR_ : FOUR_PCT_VSR });
    }

    function test_setVSRBounds() external {
        assertEq(grPrime.minVSR(), RAY);
        assertEq(grPrime.maxVSR(), grPrime.MAX_VSR());

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.VSRBoundsSet(admin, ONE_PCT_VSR, FOUR_PCT_VSR);

        vm.prank(admin);
        grPrime.setVSRBounds({ minVSR_ : ONE_PCT_VSR, maxVSR_ : FOUR_PCT_VSR });

        assertEq(grPrime.minVSR(), ONE_PCT_VSR);
        assertEq(grPrime.maxVSR(), FOUR_PCT_VSR);
    }

    /**********************************************************************************************/
    /*** unpause tests                                                                          ***/
    /**********************************************************************************************/

    function test_unpause_notAuthorized() external {
        vm.expectRevert(_notAuthorized(unauthorized, UNPAUSER_ROLE));
        vm.prank(unauthorized);
        grPrime.unpause();
    }

    function test_unpause_pauserCannotUnpause() external {
        vm.expectRevert(_notAuthorized(pauser, UNPAUSER_ROLE));
        vm.prank(pauser);
        grPrime.unpause();
    }

    function test_unpause() external {
        _pause();

        assertEq(grPrime.paused(), true);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Unpaused(unpauser);

        vm.prank(unpauser);
        grPrime.unpause();

        assertEq(grPrime.paused(), false);
    }

    /**********************************************************************************************/
    /*** setVSR tests                                                                           ***/
    /**********************************************************************************************/

    function test_setVSR_notSetter() external {
        vm.expectRevert(_notAuthorized(unauthorized, OPERATOR_ROLE));
        vm.prank(unauthorized);
        grPrime.setVSR(ONE_PCT_VSR);
    }

    function test_setVSR_vsrTooLowBoundary() external {
        vm.prank(admin);
        grPrime.setVSRBounds(ONE_PCT_VSR, FOUR_PCT_VSR);

        vm.expectRevert(IGrovePrimeVault.VSRTooLow.selector);
        vm.prank(operator);
        grPrime.setVSR(ONE_PCT_VSR - 1);

        vm.prank(operator);
        grPrime.setVSR(ONE_PCT_VSR);
    }

    function test_setVSR_vsrTooHighBoundary() external {
        vm.prank(admin);
        grPrime.setVSRBounds(RAY, FOUR_PCT_VSR);

        vm.expectRevert(IGrovePrimeVault.VSRTooHigh.selector);
        vm.prank(operator);
        grPrime.setVSR(FOUR_PCT_VSR + 1);

        vm.prank(operator);
        grPrime.setVSR(FOUR_PCT_VSR);
    }

    function test_setVSR() external {
        uint256 deployTimestamp = vm.getBlockTimestamp();

        skip(10 days);

        assertEq(uint256(grPrime.chi()), RAY);
        assertEq(uint256(grPrime.rho()), deployTimestamp);
        assertEq(grPrime.vsr(),          1.000000001547125957863212448e27);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Drip(uint192(1.001337610630706965934046250e27), 0);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.VSRSet(operator, FOUR_PCT_VSR);

        vm.prank(operator);
        grPrime.setVSR(FOUR_PCT_VSR);

        assertEq(uint256(grPrime.chi()), 1.001337610630706965934046250e27);
        assertEq(uint256(grPrime.rho()), vm.getBlockTimestamp());
        assertEq(grPrime.vsr(),          FOUR_PCT_VSR);
    }

    /**********************************************************************************************/
    /*** take tests                                                                             ***/
    /**********************************************************************************************/

    function test_take_notAuthorized() external {
        vm.expectRevert(_notAuthorized(unauthorized, TAKER_ROLE));
        vm.prank(unauthorized);
        grPrime.take(1_000_000e18);
    }

    function test_take_insufficientSharesBoundary() external {
        _requestDeposit(user, 1_000_000e18);  // Instant fill

        uint256 vaultBalance = sUSDS.balanceOf(address(grPrime));

        vm.expectRevert(IGrovePrimeVault.InsufficientShares.selector);
        vm.prank(taker);
        grPrime.take(vaultBalance + 1);

        vm.prank(taker);
        grPrime.take(vaultBalance);
    }

    function test_take() external {
        uint256 expectedSavingsShares = sUSDS.convertToShares(1_000_000e18);

        _requestDeposit(user, 1_000_000e18);  // Instant fill

        assertEq(sUSDS.balanceOf(address(grPrime)), expectedSavingsShares);
        assertEq(sUSDS.balanceOf(taker),            0);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Take(taker, expectedSavingsShares);

        vm.prank(taker);
        grPrime.take(expectedSavingsShares);

        assertEq(sUSDS.balanceOf(address(grPrime)), 0);
        assertEq(sUSDS.balanceOf(taker),            expectedSavingsShares);
    }

    /**********************************************************************************************/
    /*** setRedeemFeeRate tests                                                                 ***/
    /**********************************************************************************************/

    function test_setRedeemFeeRate_notAuthorized() external {
        vm.expectRevert(_notAuthorized(unauthorized, REDEEM_FEE_SETTER_ROLE));
        vm.prank(unauthorized);
        grPrime.setRedeemFeeRate(0.005e18);
    }

    function test_setRedeemFeeRate_feeTooHighBoundary() external {
        vm.expectRevert(IGrovePrimeVault.FeeTooHigh.selector);
        vm.prank(redeemFeeSetter);
        grPrime.setRedeemFeeRate(1);  // Can't set a fee until admin sets the max fee

        vm.prank(redeemFeeSetter);
        grPrime.setRedeemFeeRate(0);  // Max is 0 on deployment

        vm.prank(admin);
        grPrime.setMaxRedeemFeeRate(0.005e18);

        vm.expectRevert(IGrovePrimeVault.FeeTooHigh.selector);
        vm.prank(redeemFeeSetter);
        grPrime.setRedeemFeeRate(0.005e18 + 1);

        vm.prank(redeemFeeSetter);
        grPrime.setRedeemFeeRate(0.005e18);
    }

    function test_setRedeemFeeRate() external {
        vm.prank(admin);
        grPrime.setMaxRedeemFeeRate(0.01e18);

        assertEq(grPrime.redeemFeeRate(), 0);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.RedeemFeeRateSet(redeemFeeSetter, 0.01e18);

        vm.prank(redeemFeeSetter);
        grPrime.setRedeemFeeRate(0.01e18);

        assertEq(grPrime.redeemFeeRate(), 0.01e18);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.RedeemFeeRateSet(redeemFeeSetter, 0);

        vm.prank(redeemFeeSetter);
        grPrime.setRedeemFeeRate(0);

        assertEq(grPrime.redeemFeeRate(), 0);
    }

    /**********************************************************************************************/
    /*** pause tests                                                                            ***/
    /**********************************************************************************************/

    function test_pause_notAuthorized() external {
        vm.expectRevert(_notAuthorized(unauthorized, PAUSER_ROLE));
        vm.prank(unauthorized);
        grPrime.pause();
    }

    function test_pause() external {
        assertEq(grPrime.paused(), false);

        vm.expectEmit(address(grPrime));
        emit IGrovePrimeVault.Paused(pauser);

        vm.prank(pauser);
        grPrime.pause();

        assertEq(grPrime.paused(), true);
    }

}
