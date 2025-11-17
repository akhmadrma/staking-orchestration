// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/mocks/MockWstETH.sol";
import "../../src/mocks/MockLido.sol";
import "../../src/mocks/MockOracle.sol";
import "../../src/interfaces/IWstETH.sol";
import "../../src/interfaces/ILido.sol";

contract WstETHIntegrationTest is Test {
    // ============ Test Contracts ============
    MockWstETH wstETH;
    MockLido lido;
    MockOracle oracle;

    // ============ Test Addresses ============
    address owner = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    address referrer = address(0x4);

    // ============ Test Constants ============
    uint256 constant ETH_AMOUNT = 50 ether;
    uint256 constant LARGE_DEPOSIT = 1000 ether;
    uint256 constant VALIDATOR_COUNT = 10;
    uint256 constant APR = 500; // 5%
    uint256 constant TIME_ADVANCE = 365 days;

    function setUp() public {
        vm.startPrank(owner);

        oracle = new MockOracle();
        lido = new MockLido(address(oracle));
        wstETH = new MockWstETH(address(lido));

        // Setup oracle
        oracle.setMockValidatorBalance(32 ether);
        oracle.setMockActiveBalance(32 ether);

        vm.stopPrank();

        // Fund users
        vm.deal(user1, 200 ether);
        vm.deal(user2, 200 ether);
        vm.deal(referrer, 100 ether);
    }

    // ============ Complete Flow Tests ============

    function test_CompleteFlow_ETHToWstETH_WithRewards() public {
        vm.startPrank(user1);

        // 1. Stake ETH to get stETH
        uint256 initialETH = user1.balance;
        uint256 stethAmount = lido.submit{value: ETH_AMOUNT}(referrer);
        assertEq(stethAmount, ETH_AMOUNT); // First depositor gets 1:1
        assertEq(user1.balance, initialETH - ETH_AMOUNT);

        // 2. Approve wstETH contract to spend stETH
        lido.approve(address(wstETH), stethAmount);

        // 3. Wrap stETH to get wstETH
        uint256 wstethAmount = wstETH.wrap(stethAmount);
        assertEq(wstethAmount, ETH_AMOUNT); // 1:1 when no rewards yet

        // 4. Simulate time advancement and rewards
        vm.warp(block.timestamp + TIME_ADVANCE);

        vm.startPrank(owner);
        oracle.simulateRewards(VALIDATOR_COUNT, APR);
        lido.handleOracleReport(
            lido.getTotalPooledEther() + 5 ether, // +5% rewards
            lido.getTotalShares(),
            TIME_ADVANCE
        );
        vm.stopPrank();

        // 5. Unwrap wstETH back to stETH (should get more due to rewards)
        vm.startPrank(user1);
        uint256 returnedSteth = wstETH.unwrap(wstethAmount);
        assertTrue(returnedSteth > stethAmount); // Should have earned rewards

        vm.stopPrank();
    }

    function test_MultipleUsers_ShareRewardsFairly() public {
        // User 1 stakes and wraps
        vm.startPrank(user1);
        lido.submit{value: ETH_AMOUNT}(address(0));
        lido.approve(address(wstETH), ETH_AMOUNT);
        uint256 wsteth1 = wstETH.wrap(ETH_AMOUNT);
        vm.stopPrank();

        // User 2 stakes and wraps
        vm.startPrank(user2);
        lido.submit{value: ETH_AMOUNT}(address(0));
        lido.approve(address(wstETH), ETH_AMOUNT);
        uint256 wsteth2 = wstETH.wrap(ETH_AMOUNT);
        vm.stopPrank();

        // Generate rewards
        vm.warp(block.timestamp + TIME_ADVANCE);

        vm.startPrank(owner);
        oracle.simulateRewards(VALIDATOR_COUNT, APR);
        uint256 rewardAmount = 10 ether;
        lido.handleOracleReport(
            lido.getTotalPooledEther() + rewardAmount,
            lido.getTotalShares(),
            TIME_ADVANCE
        );
        vm.stopPrank();

        // Both users should benefit proportionally from rewards
        vm.startPrank(user1);
        uint256 steth1 = wstETH.unwrap(wsteth1);
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 steth2 = wstETH.unwrap(wsteth2);
        vm.stopPrank();

        // Each should get their original + half of rewards
        uint256 expectedReturn = ETH_AMOUNT + (rewardAmount / 2);
        assertEq(steth1, expectedReturn);
        assertEq(steth2, expectedReturn);
    }

    function test_WrapUnwrapFlow_DuringRewardPeriod() public {
        // Initial stake and wrap
        vm.startPrank(user1);
        uint256 stethAmount = lido.submit{value: ETH_AMOUNT}(referrer);
        lido.approve(address(wstETH), stethAmount);
        uint256 initialWsteth = wstETH.wrap(stethAmount);
        vm.stopPrank();

        // Generate rewards
        vm.warp(block.timestamp + TIME_ADVANCE / 2);

        vm.startPrank(owner);
        oracle.simulateRewards(VALIDATOR_COUNT, APR);
        lido.handleOracleReport(
            lido.getTotalPooledEther() + 2 ether,
            lido.getTotalShares(),
            TIME_ADVANCE / 2
        );
        vm.stopPrank();

        // User 2 wraps later (gets fewer wstETH for same stETH)
        vm.startPrank(user2);
        lido.submit{value: ETH_AMOUNT}(address(0));
        lido.approve(address(wstETH), ETH_AMOUNT);
        uint256 laterWsteth = wstETH.wrap(ETH_AMOUNT);
        assertTrue(laterWsteth < initialWsteth);
        vm.stopPrank();

        // More rewards
        vm.warp(block.timestamp + TIME_ADVANCE / 2);

        vm.startPrank(owner);
        oracle.simulateRewards(VALIDATOR_COUNT, APR);
        lido.handleOracleReport(
            lido.getTotalPooledEther() + 3 ether,
            lido.getTotalShares(),
            TIME_ADVANCE / 2
        );
        vm.stopPrank();

        // Both unwrap - user1 should get proportionally more rewards
        vm.startPrank(user1);
        uint256 finalSteth1 = wstETH.unwrap(initialWsteth);
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 finalSteth2 = wstETH.unwrap(laterWsteth);
        vm.stopPrank();

        assertTrue(finalSteth1 > finalSteth2);
        assertTrue(finalSteth1 > ETH_AMOUNT);
        assertTrue(finalSteth2 > ETH_AMOUNT);
    }

    // ============ Ratio Consistency Tests ============

    function test_RatioConsistency_AfterOperations() public {
        vm.startPrank(user1);

        // Submit and wrap
        lido.submit{value: ETH_AMOUNT}(address(0));
        lido.approve(address(wstETH), ETH_AMOUNT);
        wstETH.wrap(ETH_AMOUNT);

        // Verify ratios are consistent
        uint256 stethPerWsteth = wstETH.stETHPerWstETH();
        uint256 wstethPerSteth = wstETH.wstETHPerStETH();

        // Inverse should be approximately equal (allowing for precision)
        uint256 calculatedInverse = (1e18 * 1e18) / stethPerWsteth;
        assertEq(wstethPerSteth, calculatedInverse);

        // Test conversions are inverses
        uint256 testAmount = 1 ether;
        uint256 wstFromSteth = wstETH.getWstETHByStETH(testAmount);
        uint256 stethFromWsteth = wstETH.getStETHByWstETH(wstFromSteth);
        assertEq(stethFromWsteth, testAmount);

        vm.stopPrank();
    }

    function test_RatioAccuracy_WithMultipleUsers() public {
        address[] memory users = new address[](5);
        for (uint256 i = 0; i < users.length; i++) {
            users[i] = address(uint160(0x1000 + i));
            vm.deal(users[i], 50 ether);
        }

        // Multiple users stake different amounts
        uint256[] memory amounts = new uint256[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            amounts[i] = (i + 1) * 1 ether;

            vm.startPrank(users[i]);
            lido.submit{value: amounts[i]}(address(0));
            lido.approve(address(wstETH), amounts[i]);
            wstETH.wrap(amounts[i]);
            vm.stopPrank();
        }

        // Generate rewards
        vm.warp(block.timestamp + TIME_ADVANCE);
        vm.startPrank(owner);
        oracle.simulateRewards(VALIDATOR_COUNT, APR);
        lido.handleOracleReport(
            lido.getTotalPooledEther() + 20 ether,
            lido.getTotalShares(),
            TIME_ADVANCE
        );
        vm.stopPrank();

        // Verify ratio consistency after rewards
        uint256 totalSteth = lido.balanceOf(address(wstETH));
        uint256 totalWsteth = wstETH.totalSupply();

        assertEq(wstETH.getStETHByWstETH(totalWsteth), totalSteth);
        assertEq(wstETH.getWstETHByStETH(totalSteth), totalWsteth);
    }

    // ============ Performance Tests ============

    function test_HighVolumeWrapping() public {
        address[] memory users = new address[](20);

        // Create users
        for (uint256 i = 0; i < users.length; i++) {
            users[i] = address(uint160(0x2000 + i));
            vm.deal(users[i], 100 ether);
        }

        uint256 wrapAmount = 1 ether;
        uint256 expectedTotalWsteth = wrapAmount * users.length;

        // All users wrap
        for (uint256 i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            lido.submit{value: wrapAmount}(address(0));
            lido.approve(address(wstETH), wrapAmount);
            wstETH.wrap(wrapAmount);
            vm.stopPrank();
        }

        // Verify totals
        assertEq(wstETH.totalSupply(), expectedTotalWsteth);
        assertEq(lido.balanceOf(address(wstETH)), expectedTotalWsteth);

        // Verify individual balances
        for (uint256 i = 0; i < users.length; i++) {
            assertEq(wstETH.balanceOf(users[i]), wrapAmount);
        }
    }

    function test_GasEfficiency_CompleteFlow() public {
        uint256 startGas;
        uint256 gasUsed;

        vm.startPrank(user1);

        // Measure gas for complete flow
        startGas = gasleft();

        // Submit to Lido
        lido.submit{value: ETH_AMOUNT}(address(0));

        // Approve wstETH
        lido.approve(address(wstETH), ETH_AMOUNT);

        // Wrap
        wstETH.wrap(ETH_AMOUNT);

        // Unwrap
        wstETH.unwrap(ETH_AMOUNT);

        gasUsed = startGas - gasleft();
        console.log("Gas for complete ETH->stETH->wstETH->stETH flow:", gasUsed);

        assertTrue(gasUsed < 500000);

        vm.stopPrank();
    }

    // ============ Edge Case Integration Tests ============

    function test_ZeroBalanceState_AfterCompleteUnwrap() public {
        vm.startPrank(user1);

        // Complete flow
        lido.submit{value: ETH_AMOUNT}(address(0));
        lido.approve(address(wstETH), ETH_AMOUNT);
        uint256 wstethAmount = wstETH.wrap(ETH_AMOUNT);
        wstETH.unwrap(wstethAmount);

        // Verify clean state
        assertEq(wstETH.balanceOf(user1), 0);
        assertEq(wstETH.totalSupply(), 0);
        assertEq(lido.balanceOf(address(wstETH)), 0);

        // Ratios should return to 1:1
        assertEq(wstETH.stETHPerWstETH(), 1e18);
        assertEq(wstETH.wstETHPerStETH(), 1e18);

        vm.stopPrank();
    }

    function test_TransferWrappedTokens_WithPendingRewards() public {
        vm.startPrank(user1);

        // Wrap tokens
        lido.submit{value: ETH_AMOUNT}(address(0));
        lido.approve(address(wstETH), ETH_AMOUNT);
        uint256 wstethAmount = wstETH.wrap(ETH_AMOUNT);

        // Transfer to user2
        wstETH.transfer(user2, wstethAmount);

        assertEq(wstETH.balanceOf(user1), 0);
        assertEq(wstETH.balanceOf(user2), wstethAmount);

        vm.stopPrank();

        // Generate rewards
        vm.warp(block.timestamp + TIME_ADVANCE);
        vm.startPrank(owner);
        oracle.simulateRewards(VALIDATOR_COUNT, APR);
        lido.handleOracleReport(
            lido.getTotalPooledEther() + 5 ether,
            lido.getTotalShares(),
            TIME_ADVANCE
        );
        vm.stopPrank();

        // User2 can unwrap and receive rewards
        vm.startPrank(user2);
        uint256 returnedSteth = wstETH.unwrap(wstethAmount);
        assertTrue(returnedSteth > ETH_AMOUNT);
        vm.stopPrank();
    }

    function test_MultipleWrapUnwrapCycles_WithRecurringRewards() public {
        vm.startPrank(user1);

        uint256 initialDeposit = 20 ether;
        lido.submit{value: initialDeposit}(address(0));
        lido.approve(address(wstETH), initialDeposit);

        uint256 totalStethReceived = 0;

        // Perform multiple wrap-unwrap cycles with rewards in between
        for (uint256 i = 0; i < 3; i++) {
            // Wrap
            uint256 wstethAmount = wstETH.wrap(initialDeposit / 3);

            // Advance time and generate rewards
            vm.warp(block.timestamp + TIME_ADVANCE / 3);
            vm.startPrank(owner);
            oracle.simulateRewards(VALIDATOR_COUNT, APR);
            lido.handleOracleReport(
                lido.getTotalPooledEther() + 2 ether,
                lido.getTotalShares(),
                TIME_ADVANCE / 3
            );
            vm.stopPrank();

            // Unwrap
            uint256 stethReturned = wstETH.unwrap(wstethAmount);
            totalStethReceived += stethReturned;
        }

        // Should have received original deposit plus all rewards
        assertTrue(totalStethReceived > initialDeposit);

        vm.stopPrank();
    }

    // ============ Error Recovery Tests ============

    function test_PauseResume_DuringRewards() public {
        vm.startPrank(user1);

        // Wrap tokens
        lido.submit{value: ETH_AMOUNT}(address(0));
        lido.approve(address(wstETH), ETH_AMOUNT);
        wstETH.wrap(ETH_AMOUNT);

        vm.stopPrank();

        // Pause contract
        vm.startPrank(owner);
        wstETH.pause();
        vm.stopPrank();

        // Generate rewards while paused
        vm.warp(block.timestamp + TIME_ADVANCE);
        vm.startPrank(owner);
        oracle.simulateRewards(VALIDATOR_COUNT, APR);
        lido.handleOracleReport(
            lido.getTotalPooledEther() + 5 ether,
            lido.getTotalShares(),
            TIME_ADVANCE
        );
        vm.stopPrank();

        // Operations should fail while paused
        vm.startPrank(user1);
        vm.expectRevert("EnforcedPause");
        wstETH.wrap(1 ether);

        vm.expectRevert("EnforcedPause");
        wstETH.unwrap(1 ether);
        vm.stopPrank();

        // Unpause and verify operations work
        vm.startPrank(owner);
        wstETH.unpause();
        vm.stopPrank();

        vm.startPrank(user1);
        uint256 returnedSteth = wstETH.unwrap(ETH_AMOUNT);
        assertTrue(returnedSteth > ETH_AMOUNT); // Should include rewards
        vm.stopPrank();
    }
}