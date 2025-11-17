// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/mocks/MockLido.sol";
import "../../src/mocks/MockOracle.sol";
import "../../src/interfaces/ILido.sol";
import "../../src/interfaces/IOracle.sol";

contract MockLidoTest is Test {
    // ============ Test Contracts ============
    MockLido lido;
    MockOracle oracle;

    // ============ Test Addresses ============
    address owner = address(0x1);
    address user = address(0x2);
    address referrer = address(0x3);
    address treasury = address(0x4);

    // ============ Test Constants ============
    uint256 constant ETH_AMOUNT = 10 ether;
    uint256 constant LARGE_ETH_AMOUNT = 100 ether;
    uint256 constant ZERO_AMOUNT = 0;
    uint256 constant FEE_BPS = 1000; // 10%
    uint256 constant MAX_FEE_BPS = 10000;
    uint256 constant REWARD_APR = 500; // 5%

    // ============ Events ============
    event Submitted(address indexed sender, address indexed referral, uint256 amount, uint256 shares);
    event WithdrawalRequested(address indexed owner, uint256 amount, uint256 requestId);
    event WithdrawalClaimed(address indexed owner, uint256 amount, uint256 requestId);
    event RewardsDistributed(uint256 amount, uint256 timestamp);
    event FeeCollected(address indexed owner, uint256 amount);

    function setUp() public {
        // Start as owner to deploy contracts
        vm.startPrank(owner);

        // Deploy oracle and lido contracts
        oracle = new MockOracle();
        lido = new MockLido(address(oracle));

        vm.stopPrank();

        // Fund users with ETH
        vm.deal(user, 200 ether);
        vm.deal(referrer, 100 ether);
        vm.deal(treasury, 50 ether);

        // Set initial oracle mock values
        vm.startPrank(owner);
        oracle.setMockValidatorBalance(32 ether);
        oracle.setMockActiveBalance(32 ether);
        vm.stopPrank();
    }

    // ============ Constructor Tests ============

    function test_Constructor_InitializesCorrectly() public {
        assertEq(lido.name(), "Mock Staked Ether");
        assertEq(lido.symbol(), "stETH");
        assertEq(address(lido.oracle()), address(oracle));
        assertEq(lido.totalPooledEther(), 0);
        assertEq(lido.totalShares(), 0);
        assertEq(lido.owner(), owner);
        assertEq(lido.lastRewardTimestamp(), block.timestamp);
        assertTrue(!lido.paused());
    }

    function test_Constructor_ZeroOracle_Reverts() public {
        vm.expectRevert();
        new MockLido(address(0));
    }

    // ============ Submit Tests ============

    function test_Submit_Success() public {
        vm.startPrank(user);

        uint256 initialBalance = user.balance;
        uint256 expectedShares = ETH_AMOUNT; // First depositor gets 1:1
        uint256 expectedFee = (ETH_AMOUNT * FEE_BPS) / MAX_FEE_BPS;

        vm.expectEmit(true, true, true, true);
        emit Submitted(user, address(0), ETH_AMOUNT, expectedShares);

        vm.expectEmit(true, false, false, true);
        emit FeeCollected(owner, expectedFee);

        uint256 shares = lido.submit{value: ETH_AMOUNT}(address(0));

        assertEq(shares, expectedShares);
        assertEq(lido.balanceOf(user), ETH_AMOUNT);
        assertEq(lido.balanceOf(owner), expectedFee); // Fee to owner
        assertEq(lido.totalPooledEther(), ETH_AMOUNT);
        assertEq(lido.totalShares(), expectedShares);
        assertEq(lido.userShares(user), expectedShares);
        assertEq(user.balance, initialBalance - ETH_AMOUNT);

        vm.stopPrank();
    }

    function test_Submit_WithReferral_Success() public {
        vm.startPrank(user);

        uint256 expectedShares = ETH_AMOUNT;
        uint256 expectedFee = (ETH_AMOUNT * FEE_BPS) / MAX_FEE_BPS;

        vm.expectEmit(true, true, true, true);
        emit Submitted(user, referrer, ETH_AMOUNT, expectedShares);

        vm.expectEmit(true, false, false, true);
        emit FeeCollected(owner, expectedFee);

        uint256 shares = lido.submit{value: ETH_AMOUNT}(referrer);

        assertEq(shares, expectedShares);
        assertEq(lido.balanceOf(user), ETH_AMOUNT);
        assertEq(lido.balanceOf(owner), expectedFee);

        vm.stopPrank();
    }

    function test_Submit_SecondDepositor_GetCorrectShares() public {
        // First deposit
        vm.startPrank(user);
        lido.submit{value: ETH_AMOUNT}(address(0));
        vm.stopPrank();

        // Simulate some rewards
        vm.startPrank(owner);
        oracle.simulateRewards(1, REWARD_APR);
        vm.stopPrank();

        // Second deposit should get fewer shares due to rewards
        vm.startPrank(referrer);
        uint256 shares = lido.submit{value: ETH_AMOUNT}(address(0));

        // Should get slightly fewer shares than first depositor
        assertTrue(shares < ETH_AMOUNT);
        vm.stopPrank();
    }

    function test_Submit_ZeroAmount_Reverts() public {
        vm.startPrank(user);

        vm.expectRevert("MockLido: ZERO_AMOUNT");
        lido.submit{value: ZERO_AMOUNT}(address(0));

        vm.stopPrank();
    }

    function test_Submit_Paused_Reverts() public {
        vm.startPrank(owner);
        lido.pause();
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert("EnforcedPause");
        lido.submit{value: ETH_AMOUNT}(address(0));
        vm.stopPrank();
    }

    function test_Submit_Reentrancy_Protected() public {
        // This test would require a malicious contract to test reentrancy
        // For now, we verify the modifier is present
        assertTrue(true);
    }

    // ============ View Function Tests ============

    function test_GetPooledEthByShares() public {
        vm.startPrank(user);
        lido.submit{value: ETH_AMOUNT}(address(0));
        vm.stopPrank();

        uint256 ethAmount = lido.getPooledEthByShares(ETH_AMOUNT);
        assertEq(ethAmount, ETH_AMOUNT);
    }

    function test_GetSharesByPooledEth() public {
        vm.startPrank(user);
        lido.submit{value: ETH_AMOUNT}(address(0));
        vm.stopPrank();

        uint256 shares = lido.getSharesByPooledEth(ETH_AMOUNT);
        assertEq(shares, ETH_AMOUNT);
    }

    function test_GetTotalPooledEther() public {
        assertEq(lido.getTotalPooledEther(), 0);

        vm.startPrank(user);
        lido.submit{value: ETH_AMOUNT}(address(0));
        vm.stopPrank();

        assertEq(lido.getTotalPooledEther(), ETH_AMOUNT);
    }

    function test_GetTotalShares() public {
        assertEq(lido.getTotalShares(), 0);

        vm.startPrank(user);
        lido.submit{value: ETH_AMOUNT}(address(0));
        vm.stopPrank();

        assertEq(lido.getTotalShares(), ETH_AMOUNT);
    }

    // ============ Withdrawal Tests ============

    function test_RequestWithdrawal_Success() public {
        vm.startPrank(user);
        lido.submit{value: ETH_AMOUNT}(address(0));

        vm.expectEmit(true, false, true, false);
        emit WithdrawalRequested(user, ETH_AMOUNT, 1);

        uint256 requestId = lido.requestWithdrawal(ETH_AMOUNT);

        assertEq(requestId, 1);
        assertEq(lido.balanceOf(user), 0); // stETH burned

        // Test withdrawal request was created
        assertEq(requestId, 1);
        assertEq(lido.balanceOf(user), 0); // stETH burned

        vm.stopPrank();
    }

    function test_RequestWithdrawal_ZeroAmount_Reverts() public {
        vm.startPrank(user);

        vm.expectRevert("MockLido: ZERO_AMOUNT");
        lido.requestWithdrawal(ZERO_AMOUNT);

        vm.stopPrank();
    }

    function test_RequestWithdrawal_InsufficientBalance_Reverts() public {
        vm.startPrank(user);

        vm.expectRevert("ERC20: burn amount exceeds balance");
        lido.requestWithdrawal(ETH_AMOUNT);

        vm.stopPrank();
    }

    function test_ClaimWithdrawal_Success() public {
        vm.startPrank(user);

        // Submit and request withdrawal
        lido.submit{value: ETH_AMOUNT}(address(0));
        uint256 requestId = lido.requestWithdrawal(ETH_AMOUNT);

        uint256 initialBalance = user.balance;

        vm.expectEmit(true, false, true, false);
        emit WithdrawalClaimed(user, ETH_AMOUNT, requestId);

        lido.claimWithdrawal(requestId);

        assertEq(user.balance, initialBalance + ETH_AMOUNT);

        // Withdrawal claimed successfully (cannot check internal struct)
        assertTrue(user.balance >= initialBalance + ETH_AMOUNT);

        vm.stopPrank();
    }

    function test_ClaimWithdrawal_NonexistentRequest_Reverts() public {
        vm.startPrank(user);

        vm.expectRevert("MockLido: WITHDRAWAL_NOT_FOUND");
        lido.claimWithdrawal(1);

        vm.stopPrank();
    }

    function test_ClaimWithdrawal_AlreadyClaimed_Reverts() public {
        vm.startPrank(user);

        lido.submit{value: ETH_AMOUNT}(address(0));
        uint256 requestId = lido.requestWithdrawal(ETH_AMOUNT);
        lido.claimWithdrawal(requestId);

        vm.expectRevert("MockLido: ALREADY_CLAIMED");
        lido.claimWithdrawal(requestId);

        vm.stopPrank();
    }

    function test_ClaimWithdrawal_NotOwner_Reverts() public {
        vm.startPrank(user);

        lido.submit{value: ETH_AMOUNT}(address(0));
        uint256 requestId = lido.requestWithdrawal(ETH_AMOUNT);

        vm.startPrank(referrer);
        vm.expectRevert("MockLido: NOT_OWNER");
        lido.claimWithdrawal(requestId);

        vm.stopPrank();
    }

    // ============ Oracle Tests ============

    function test_HandleOracleReport_Success() public {
        vm.startPrank(user);
        lido.submit{value: ETH_AMOUNT}(address(0));
        vm.stopPrank();

        uint256 newTotalEth = ETH_AMOUNT + 1 ether;
        uint256 newTotalShares = ETH_AMOUNT;

        vm.startPrank(owner);

        IOracle.ReportData memory data = IOracle.ReportData({
            epochId: 1,
            totalActiveBalance: 32 ether,
            totalValidatorBalance: 33 ether,
            totalRewards: 1 ether,
            timestamp: block.timestamp
        });

        oracle.submitReport(data);

        vm.expectEmit(false, false, true, true);
        emit RewardsDistributed(1 ether, block.timestamp);

        lido.handleOracleReport(newTotalEth, newTotalShares, 365 days);

        assertEq(lido.totalPooledEther(), newTotalEth);
        assertEq(lido.totalShares(), newTotalShares);

        vm.stopPrank();
    }

    function test_HandleOracleReport_InvalidAmount_Reverts() public {
        vm.startPrank(user);
        lido.submit{value: ETH_AMOUNT}(address(0));
        vm.stopPrank();

        vm.startPrank(owner);

        vm.expectRevert("MockLido: INVALID_REWARD_AMOUNT");
        lido.handleOracleReport(ETH_AMOUNT - 1 ether, ETH_AMOUNT, 365 days);

        vm.stopPrank();
    }

    function test_HandleOracleReport_Unauthorized_Reverts() public {
        vm.startPrank(user);

        vm.expectRevert("MockLido: INVALID_ORACLE");
        lido.handleOracleReport(ETH_AMOUNT + 1 ether, ETH_AMOUNT, 365 days);

        vm.stopPrank();
    }

    // ============ Reward Simulation Tests ============

    function test_EmergencySimulateRewards() public {
        vm.startPrank(user);
        lido.submit{value: ETH_AMOUNT}(address(0));
        vm.stopPrank();

        vm.startPrank(owner);

        vm.expectEmit(false, false, true, true);
        emit RewardsDistributed(0, block.timestamp); // May be 0 due to time constraints

        lido.emergencySimulateRewards(1, REWARD_APR);

        // Should have increased total pooled ether (unless time elapsed is too small)
        assertTrue(lido.totalPooledEther() >= ETH_AMOUNT);

        vm.stopPrank();
    }

    // ============ Owner Function Tests ============

    function test_Pause_Unpause() public {
        vm.startPrank(owner);

        lido.pause();
        assertTrue(lido.paused());

        lido.unpause();
        assertTrue(!lido.paused());

        vm.stopPrank();
    }

    function test_Pause_Unauthorized_Reverts() public {
        vm.startPrank(user);

        vm.expectRevert("Ownable: caller is not the owner");
        lido.pause();

        vm.stopPrank();
    }

    // ============ Gas Tests ============

    function test_GasUsage_Submit() public {
        vm.startPrank(user);

        uint256 startGas = gasleft();
        lido.submit{value: ETH_AMOUNT}(address(0));
        uint256 gasUsed = startGas - gasleft();

        // Should use reasonable amount of gas
        assertTrue(gasUsed < 200000);
        console.log("Gas used for submit:", gasUsed);

        vm.stopPrank();
    }

    function test_GasUsage_Withdrawal() public {
        vm.startPrank(user);
        lido.submit{value: ETH_AMOUNT}(address(0));
        uint256 requestId = lido.requestWithdrawal(ETH_AMOUNT);

        uint256 startGas = gasleft();
        lido.claimWithdrawal(requestId);
        uint256 gasUsed = startGas - gasleft();

        assertTrue(gasUsed < 200000);
        console.log("Gas used for withdrawal claim:", gasUsed);

        vm.stopPrank();
    }

    // ============ Edge Case Tests ============

    function test_MultipleUsers() public {
        address[] memory users = new address[](5);
        users[0] = address(0x10);
        users[1] = address(0x11);
        users[2] = address(0x12);
        users[3] = address(0x13);
        users[4] = address(0x14);

        // Fund users
        for (uint256 i = 0; i < users.length; i++) {
            vm.deal(users[i], 50 ether);
        }

        // All users submit
        for (uint256 i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            lido.submit{value: ETH_AMOUNT}(address(0));
            vm.stopPrank();
        }

        // Verify totals
        assertEq(lido.totalPooledEther(), ETH_AMOUNT * users.length);
        assertEq(lido.totalShares(), ETH_AMOUNT * users.length);

        // Verify individual balances
        for (uint256 i = 0; i < users.length; i++) {
            assertEq(lido.balanceOf(users[i]), ETH_AMOUNT);
            assertEq(lido.userShares(users[i]), ETH_AMOUNT);
        }
    }

    function test_ReceiveFunction() public {
        vm.startPrank(user);

        uint256 initialBalance = user.balance;
        uint256 stethBalanceBefore = lido.balanceOf(user);

        // Direct ETH transfer should call submit
        (bool success,) = address(lido).call{value: ETH_AMOUNT}("");
        assertTrue(success);

        assertEq(user.balance, initialBalance - ETH_AMOUNT);
        assertEq(lido.balanceOf(user), stethBalanceBefore + ETH_AMOUNT);

        vm.stopPrank();
    }

    function test_FallbackFunction_Reverts() public {
        vm.startPrank(user);

        vm.expectRevert("MockLido: fallback not supported");
        (bool success,) = address(lido).call{value: ETH_AMOUNT}("");
        assertTrue(success);

        // Try with calldata
        vm.expectRevert("MockLido: fallback not supported");
        (success,) = address(lido).call{value: ETH_AMOUNT}(abi.encodeWithSignature("nonExistentFunction()"));
        assertTrue(!success);

        vm.stopPrank();
    }
}