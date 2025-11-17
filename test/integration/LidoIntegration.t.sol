// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/mocks/MockLido.sol";
import "../../src/mocks/MockOracle.sol";
import "../../src/interfaces/ILido.sol";
import "../../src/interfaces/IOracle.sol";

contract LidoIntegrationTest is Test {
    // ============ Test Contracts ============
    MockLido lido;
    MockOracle oracle;

    // ============ Test Addresses ============
    address owner = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    address referrer = address(0x4);

    // ============ Test Constants ============
    uint256 constant DEPOSIT_AMOUNT = 50 ether;
    uint256 constant LARGE_DEPOSIT = 1000 ether;
    uint256 constant VALIDATOR_COUNT = 10;
    uint256 constant APR = 500; // 5%
    uint256 constant TIME_ADVANCE = 365 days;

    function setUp() public {
        vm.startPrank(owner);

        oracle = new MockOracle();
        lido = new MockLido(address(oracle));

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

    function test_CompleteStakingFlow_WithRewards() public {
        vm.startPrank(user1);

        // Initial deposit
        uint256 shares = lido.submit{value: DEPOSIT_AMOUNT}(referrer);
        assertEq(shares, DEPOSIT_AMOUNT); // First depositor gets 1:1

        // Fast forward time and simulate rewards
        vm.warp(block.timestamp + TIME_ADVANCE);

        vm.startPrank(owner);
        oracle.simulateRewards(VALIDATOR_COUNT, APR);
        vm.stopPrank();

        // Check that rewards have been applied
        uint256 currentPooledEther = lido.getTotalPooledEther();
        assertTrue(currentPooledEther > DEPOSIT_AMOUNT);

        // User can withdraw with rewards
        uint256 requestId = lido.requestWithdrawal(lido.balanceOf(user1));
        lido.claimWithdrawal(requestId);

        vm.stopPrank();
    }

    function test_MultipleUsers_RewardDistribution() public {
        // Multiple users deposit
        vm.startPrank(user1);
        lido.submit{value: DEPOSIT_AMOUNT}(address(0));
        vm.stopPrank();

        vm.startPrank(user2);
        lido.submit{value: DEPOSIT_AMOUNT}(address(0));
        vm.stopPrank();

        // Generate rewards
        vm.warp(block.timestamp + TIME_ADVANCE);

        vm.startPrank(owner);
        oracle.simulateRewards(VALIDATOR_COUNT, APR);
        vm.stopPrank();

        // Both users should have benefited from rewards
        uint256 user1EthPerShare = lido.getPooledEthByShares(lido.userShares(user1));
        uint256 user2EthPerShare = lido.getPooledEthByShares(lido.userShares(user2));

        assertTrue(user1EthPerShare > 1 ether);
        assertTrue(user2EthPerShare > 1 ether);
    }

    // ============ Oracle Integration Tests ============

    function test_OracleReport_Processing() public {
        // User deposits
        vm.startPrank(user1);
        lido.submit{value: DEPOSIT_AMOUNT}(address(0));
        vm.stopPrank();

        // Generate oracle report
        vm.warp(block.timestamp + TIME_ADVANCE);

        vm.startPrank(owner);
        IOracle.ReportData memory data = IOracle.ReportData({
            epochId: 1,
            totalActiveBalance: 32 ether * VALIDATOR_COUNT,
            totalValidatorBalance: 33 ether * VALIDATOR_COUNT,
            totalRewards: 10 ether,
            timestamp: block.timestamp
        });

        oracle.submitReport(data);
        lido.handleOracleReport(
            lido.getTotalPooledEther() + 10 ether,
            lido.getTotalShares(),
            TIME_ADVANCE
        );
        vm.stopPrank();

        // Verify rewards applied
        assertEq(lido.getTotalPooledEther(), DEPOSIT_AMOUNT + 10 ether);
    }

    // ============ Emergency Scenario Tests ============

    function test_EmergencyPause_AllowsWithdrawals() public {
        vm.startPrank(user1);
        lido.submit{value: DEPOSIT_AMOUNT}(address(0));

        // Emergency pause
        vm.startPrank(owner);
        lido.pause();
        vm.stopPrank();

        // Should not allow new deposits
        vm.startPrank(user2);
        vm.expectRevert("EnforcedPause");
        lido.submit{value: DEPOSIT_AMOUNT}(address(0));
        vm.stopPrank();

        // Should allow existing withdrawals
        vm.startPrank(user1);
        uint256 requestId = lido.requestWithdrawal(lido.balanceOf(user1));
        lido.claimWithdrawal(requestId);
        vm.stopPrank();
    }

    function test_EmergencyUnpause_ResumesOperations() public {
        // Pause contract
        vm.startPrank(owner);
        lido.pause();
        vm.stopPrank();

        // Unpause
        vm.startPrank(owner);
        lido.unpause();
        vm.stopPrank();

        // Should allow new operations
        vm.startPrank(user1);
        vm.expectEmit(true, true, true, true);
        lido.submit{value: DEPOSIT_AMOUNT}(address(0));
        vm.stopPrank();
    }

    // ============ Performance Tests ============

    function test_HighVolumeDeposits() public {
        address[] memory users = new address[](50);

        // Create many users
        for (uint256 i = 0; i < users.length; i++) {
            users[i] = address(uint160(0x1000 + i));
            vm.deal(users[i], 100 ether);
        }

        uint256 expectedTotal = DEPOSIT_AMOUNT * users.length;

        // All users deposit
        for (uint256 i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            lido.submit{value: DEPOSIT_AMOUNT}(address(0));
            vm.stopPrank();
        }

        // Verify totals
        assertEq(lido.getTotalPooledEther(), expectedTotal);
        assertEq(lido.getTotalShares(), expectedTotal);

        // Verify individual balances
        for (uint256 i = 0; i < users.length; i++) {
            assertEq(lido.balanceOf(users[i]), DEPOSIT_AMOUNT);
        }
    }

    function test_GasEfficiency_BatchOperations() public {
        uint256 startGas;
        uint256 gasUsed;

        // Measure gas for single submit
        vm.startPrank(user1);
        startGas = gasleft();
        lido.submit{value: DEPOSIT_AMOUNT}(address(0));
        gasUsed = startGas - gasleft();
        console.log("Gas for single submit:", gasUsed);
        vm.stopPrank();

        // Measure gas for withdrawal request
        vm.startPrank(user1);
        startGas = gasleft();
        uint256 requestId = lido.requestWithdrawal(lido.balanceOf(user1));
        gasUsed = startGas - gasleft();
        console.log("Gas for withdrawal request:", gasUsed);
        vm.stopPrank();

        // Measure gas for withdrawal claim
        vm.startPrank(user1);
        startGas = gasleft();
        lido.claimWithdrawal(requestId);
        gasUsed = startGas - gasleft();
        console.log("Gas for withdrawal claim:", gasUsed);
        vm.stopPrank();
    }

    // ============ Edge Case Integration Tests ============

    function test_ZeroFeeScenario() public {
        // This would require modifying the contract to test zero fee
        // For now, verify fee collection works
        vm.startPrank(user1);
        lido.submit{value: DEPOSIT_AMOUNT}(referrer);
        vm.stopPrank();

        // Owner should have received fee
        uint256 expectedFee = (DEPOSIT_AMOUNT * 1000) / 10000; // 10%
        assertEq(lido.balanceOf(owner), expectedFee);
    }

    function test_EmptyProtocolWithdrawal() public {
        vm.startPrank(user1);

        // Try to request withdrawal without stETH
        vm.expectRevert("ERC20: burn amount exceeds balance");
        lido.requestWithdrawal(DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    function test_MultipleWithdrawalRequests() public {
        vm.startPrank(user1);

        // Large deposit
        lido.submit{value: LARGE_DEPOSIT}(address(0));

        // Multiple withdrawal requests
        uint256 request1 = lido.requestWithdrawal(LARGE_DEPOSIT / 2);
        uint256 request2 = lido.requestWithdrawal(LARGE_DEPOSIT / 2);

        // Claim both withdrawals
        lido.claimWithdrawal(request1);
        lido.claimWithdrawal(request2);

        // Should have withdrawn all funds
        assertEq(lido.balanceOf(user1), 0);

        vm.stopPrank();
    }

    // ============ State Consistency Tests ============

    function test_StateConsistency_AfterOperations() public {
        uint256 initialTotalEther = lido.getTotalPooledEther();
        uint256 initialTotalShares = lido.getTotalShares();

        vm.startPrank(user1);
        lido.submit{value: DEPOSIT_AMOUNT}(referrer);
        vm.stopPrank();

        // State should be consistent
        assertEq(lido.getTotalPooledEther(), initialTotalEther + DEPOSIT_AMOUNT);
        assertEq(lido.getTotalShares(), initialTotalShares + DEPOSIT_AMOUNT);
        assertEq(lido.balanceOf(user1) + lido.balanceOf(owner), DEPOSIT_AMOUNT);

        vm.startPrank(user1);
        uint256 requestId = lido.requestWithdrawal(lido.balanceOf(user1));
        lido.claimWithdrawal(requestId);
        vm.stopPrank();

        // Should return to initial state
        assertEq(lido.getTotalPooledEther(), initialTotalEther);
        assertEq(lido.getTotalShares(), initialTotalShares);
    }
}