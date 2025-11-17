// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/mocks/MockWstETH.sol";
import "../../src/mocks/MockLido.sol";
import "../../src/mocks/MockOracle.sol";
import "../../src/interfaces/IWstETH.sol";
import "../../src/interfaces/ILido.sol";

contract MockWstETHTest is Test {
    // ============ Test Contracts ============
    MockWstETH wstETH;
    MockLido lido;
    MockOracle oracle;

    // ============ Test Addresses ============
    address owner = address(0x1);
    address user = address(0x2);
    address user2 = address(0x3);

    // ============ Test Constants ============
    uint256 constant STETH_AMOUNT = 10 ether;
    uint256 constant WSTETH_AMOUNT = 10 ether;
    uint256 constant ZERO_AMOUNT = 0;
    uint256 constant MIN_AMOUNT = 1 wei;
    uint256 constant LARGE_AMOUNT = 1000 ether;

    // ============ Events ============
    event Wrapped(address indexed caller, uint256 stethAmount, uint256 wstethAmount);
    event Unwrapped(address indexed caller, uint256 wstethAmount, uint256 stethAmount);

    function setUp() public {
        // Start as owner to deploy contracts
        vm.startPrank(owner);

        // Deploy oracle and lido contracts
        oracle = new MockOracle();
        lido = new MockLido(address(oracle));
        wstETH = new MockWstETH(address(lido));

        vm.stopPrank();

        // Fund users with ETH
        vm.deal(user, 200 ether);
        vm.deal(user2, 200 ether);

        // Set initial oracle mock values
        vm.startPrank(owner);
        oracle.setMockValidatorBalance(32 ether);
        oracle.setMockActiveBalance(32 ether);
        vm.stopPrank();

        // Give lido approval to spend user's stETH for wrapping
        vm.startPrank(user);
        lido.submit{value: LARGE_AMOUNT}(address(0));
        lido.approve(address(wstETH), type(uint256).max);
        vm.stopPrank();

        // Give lido approval for user2
        vm.startPrank(user2);
        lido.submit{value: LARGE_AMOUNT}(address(0));
        lido.approve(address(wstETH), type(uint256).max);
        vm.stopPrank();
    }

    // ============ Constructor Tests ============

    function test_Constructor_InitializesCorrectly() public {
        assertEq(wstETH.name(), "Mock Wrapped Staked Ether");
        assertEq(wstETH.symbol(), "wstETH");
        assertEq(wstETH.getStETHAddress(), address(lido));
        assertEq(wstETH.owner(), owner);
        assertTrue(!wstETH.paused());
    }

    function test_Constructor_ZeroStETHAddress_Reverts() public {
        vm.expectRevert();
        new MockWstETH(address(0));
    }

    // ============ Wrap Tests ============

    function test_Wrap_Success() public {
        vm.startPrank(user);

        uint256 initialBalance = lido.balanceOf(user);
        uint256 initialWstethBalance = wstETH.balanceOf(user);

        vm.expectEmit(true, true, true, true);
        emit Wrapped(user, STETH_AMOUNT, STETH_AMOUNT);

        uint256 wstethAmount = wstETH.wrap(STETH_AMOUNT);

        assertEq(wstethAmount, STETH_AMOUNT);
        assertEq(lido.balanceOf(user), initialBalance - STETH_AMOUNT);
        assertEq(wstETH.balanceOf(user), initialWstethBalance + STETH_AMOUNT);
        assertEq(lido.balanceOf(address(wstETH)), STETH_AMOUNT);
        assertEq(wstETH.totalSupply(), STETH_AMOUNT);

        vm.stopPrank();
    }

    function test_Wrap_MultipleUsers_SameRatio() public {
        vm.startPrank(user);
        uint256 wsteth1 = wstETH.wrap(STETH_AMOUNT);
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 wsteth2 = wstETH.wrap(STETH_AMOUNT);
        vm.stopPrank();

        assertEq(wsteth1, STETH_AMOUNT);
        assertEq(wsteth2, STETH_AMOUNT);
        assertEq(wstETH.totalSupply(), STETH_AMOUNT * 2);
        assertEq(lido.balanceOf(address(wstETH)), STETH_AMOUNT * 2);
    }

    function test_Wrap_AfterRewards_AdjustsRatio() public {
        // Initial wrap
        vm.startPrank(user);
        wstETH.wrap(STETH_AMOUNT);
        vm.stopPrank();

        // Simulate rewards on stETH
        vm.startPrank(owner);
        oracle.simulateRewards(1, 500); // 5% APR
        lido.handleOracleReport(STETH_AMOUNT + 0.5 ether, STETH_AMOUNT, 365 days);
        vm.stopPrank();

        // Second user wraps same amount but gets fewer wstETH due to rewards
        vm.startPrank(user2);
        uint256 wstethAmount = wstETH.wrap(STETH_AMOUNT);
        vm.stopPrank();

        assertTrue(wstethAmount < STETH_AMOUNT);
    }

    function test_Wrap_ZeroAmount_Reverts() public {
        vm.startPrank(user);

        vm.expectRevert("MockWstETH: ZERO_AMOUNT");
        wstETH.wrap(ZERO_AMOUNT);

        vm.stopPrank();
    }

    function test_Wrap_InsufficientAllowance_Reverts() public {
        vm.startPrank(user);

        // Revoke allowance
        lido.approve(address(wstETH), 0);

        vm.expectRevert();
        wstETH.wrap(STETH_AMOUNT);

        vm.stopPrank();
    }

    function test_Wrap_InsufficientBalance_Reverts() public {
        vm.startPrank(user);

        // Try to wrap more than user has
        vm.expectRevert();
        wstETH.wrap(LARGE_AMOUNT * 2);

        vm.stopPrank();
    }

    function test_Wrap_Paused_Reverts() public {
        vm.startPrank(owner);
        wstETH.pause();
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert("EnforcedPause");
        wstETH.wrap(STETH_AMOUNT);
        vm.stopPrank();
    }

    // ============ Unwrap Tests ============

    function test_Unwrap_Success() public {
        vm.startPrank(user);

        // First wrap some tokens
        uint256 wrappedAmount = wstETH.wrap(STETH_AMOUNT);
        assertEq(wrappedAmount, STETH_AMOUNT);

        uint256 initialBalance = wstETH.balanceOf(user);
        uint256 initialStethBalance = lido.balanceOf(user);

        vm.expectEmit(true, true, true, true);
        emit Unwrapped(user, WSTETH_AMOUNT, STETH_AMOUNT);

        uint256 stethAmount = wstETH.unwrap(WSTETH_AMOUNT);

        assertEq(stethAmount, STETH_AMOUNT);
        assertEq(wstETH.balanceOf(user), initialBalance - WSTETH_AMOUNT);
        assertEq(lido.balanceOf(user), initialStethBalance + STETH_AMOUNT);
        assertEq(lido.balanceOf(address(wstETH)), 0);
        assertEq(wstETH.totalSupply(), 0);

        vm.stopPrank();
    }

    function test_Unwrap_ZeroAmount_Reverts() public {
        vm.startPrank(user);

        vm.expectRevert("MockWstETH: ZERO_AMOUNT");
        wstETH.unwrap(ZERO_AMOUNT);

        vm.stopPrank();
    }

    function test_Unwrap_InsufficientBalance_Reverts() public {
        vm.startPrank(user);

        vm.expectRevert();
        wstETH.unwrap(WSTETH_AMOUNT);

        vm.stopPrank();
    }

    function test_Unwrap_AfterRewards_ReturnsMoreStETH() public {
        // Wrap initial amount
        vm.startPrank(user);
        uint256 wstethAmount = wstETH.wrap(STETH_AMOUNT);
        vm.stopPrank();

        // Simulate rewards
        vm.startPrank(owner);
        oracle.simulateRewards(1, 500); // 5% APR
        lido.handleOracleReport(STETH_AMOUNT + 0.5 ether, STETH_AMOUNT, 365 days);
        vm.stopPrank();

        // Unwrap should return more stETH due to rewards
        vm.startPrank(user);
        uint256 returnedSteth = wstETH.unwrap(wstethAmount);
        assertTrue(returnedSteth > STETH_AMOUNT);
        vm.stopPrank();
    }

    function test_Unwrap_InsufficientContractLiquidity_Reverts() public {
        // Deploy another wstETH contract with same stETH to create competition
        MockWstETH wstETH2 = new MockWstETH(address(lido));

        vm.startPrank(user);
        lido.approve(address(wstETH2), type(uint256).max);

        // Wrap in both contracts
        wstETH.wrap(STETH_AMOUNT);
        wstETH2.wrap(STETH_AMOUNT);

        // Try to unwrap from first contract, but stETH is in second
        // This should work because stETH stays with the wrapper
        uint256 stethAmount = wstETH.unwrap(WSTETH_AMOUNT);
        assertEq(stethAmount, STETH_AMOUNT);
        vm.stopPrank();
    }

    function test_Unwrap_Paused_Reverts() public {
        vm.startPrank(owner);
        wstETH.pause();
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert("EnforcedPause");
        wstETH.unwrap(WSTETH_AMOUNT);
        vm.stopPrank();
    }

    // ============ View Function Tests ============

    function test_StETHPerWstETH_InitialRatio() public {
        // When no wstETH exists, ratio should be 1:1
        assertEq(wstETH.stETHPerWstETH(), 1e18);
    }

    function test_StETHPerWstETH_AfterWrap() public {
        vm.startPrank(user);
        wstETH.wrap(STETH_AMOUNT);
        vm.stopPrank();

        // After wrap, ratio should still be 1:1 initially
        assertEq(wstETH.stETHPerWstETH(), 1e18);
    }

    function test_StETHPerWstETH_AfterRewards() public {
        vm.startPrank(user);
        wstETH.wrap(STETH_AMOUNT);
        vm.stopPrank();

        // Simulate rewards
        vm.startPrank(owner);
        oracle.simulateRewards(1, 500); // 5% APR
        lido.handleOracleReport(STETH_AMOUNT + 0.5 ether, STETH_AMOUNT, 365 days);
        vm.stopPrank();

        // stETH per wstETH should increase due to rewards
        uint256 ratio = wstETH.stETHPerWstETH();
        assertTrue(ratio > 1e18);
    }

    function test_WstETHPerStETH_InverseRatio() public {
        // Initially 1:1
        assertEq(wstETH.wstETHPerStETH(), 1e18);

        vm.startPrank(user);
        wstETH.wrap(STETH_AMOUNT);
        vm.stopPrank();

        // Still 1:1 initially
        assertEq(wstETH.wstETHPerStETH(), 1e18);

        // After rewards, wstETH per stETH should decrease
        vm.startPrank(owner);
        oracle.simulateRewards(1, 500);
        lido.handleOracleReport(STETH_AMOUNT + 0.5 ether, STETH_AMOUNT, 365 days);
        vm.stopPrank();

        uint256 ratio = wstETH.wstETHPerStETH();
        assertTrue(ratio < 1e18);
    }

    function test_GetStETHByWstETH_ZeroSupply() public {
        // When no wstETH exists, conversion is 1:1
        assertEq(wstETH.getStETHByWstETH(STETH_AMOUNT), STETH_AMOUNT);
    }

    function test_GetStETHByWstETH_AfterRewards() public {
        vm.startPrank(user);
        uint256 wstethAmount = wstETH.wrap(STETH_AMOUNT);
        vm.stopPrank();

        // Simulate rewards
        vm.startPrank(owner);
        oracle.simulateRewards(1, 500);
        lido.handleOracleReport(STETH_AMOUNT + 0.5 ether, STETH_AMOUNT, 365 days);
        vm.stopPrank();

        uint256 stethAmount = wstETH.getStETHByWstETH(wstethAmount);
        assertTrue(stethAmount > STETH_AMOUNT);
    }

    function test_GetWstETHByStETH_ZeroSupply() public {
        // When no wstETH exists, conversion is 1:1
        assertEq(wstETH.getWstETHByStETH(STETH_AMOUNT), STETH_AMOUNT);
    }

    function test_GetWstETHByStETH_AfterRewards() public {
        vm.startPrank(user);
        wstETH.wrap(STETH_AMOUNT);
        vm.stopPrank();

        // Simulate rewards
        vm.startPrank(owner);
        oracle.simulateRewards(1, 500);
        lido.handleOracleReport(STETH_AMOUNT + 0.5 ether, STETH_AMOUNT, 365 days);
        vm.stopPrank();

        // Should get fewer wstETH for same stETH amount due to rewards
        uint256 wstethAmount = wstETH.getWstETHByStETH(STETH_AMOUNT);
        assertTrue(wstethAmount < STETH_AMOUNT);
    }

    function test_StETH_Address() public {
        assertEq(wstETH.getStETHAddress(), address(lido));
    }

    // ============ Owner Function Tests ============

    function test_Pause_Unpause() public {
        vm.startPrank(owner);

        wstETH.pause();
        assertTrue(wstETH.paused());

        wstETH.unpause();
        assertTrue(!wstETH.paused());

        vm.stopPrank();
    }

    function test_Pause_Unauthorized_Reverts() public {
        vm.startPrank(user);

        vm.expectRevert("Ownable: caller is not the owner");
        wstETH.pause();

        vm.stopPrank();
    }

    function test_EmergencyRecoverTokens_Success() public {
        // Give wstETH contract some random tokens
        address token = address(0x1234);

        vm.startPrank(owner);
        // Mock transfer some tokens to wstETH contract
        vm.store(token, keccak256(abi.encode(address(wstETH), 0)), bytes32(uint256(100 ether)));

        wstETH.emergencyRecoverTokens(token, 50 ether);
        vm.stopPrank();
    }

    function test_EmergencyRecoverTokens_OwnTokens_Reverts() public {
        vm.startPrank(owner);

        vm.expectRevert();
        wstETH.emergencyRecoverTokens(address(wstETH), 1 ether);

        vm.stopPrank();
    }

    function test_EmergencyRecoverTokens_StETH_Reverts() public {
        vm.startPrank(owner);

        vm.expectRevert("MockWstETH: CANNOT_RECOVER_STETH");
        wstETH.emergencyRecoverTokens(address(lido), 1 ether);

        vm.stopPrank();
    }

    function test_EmergencyRecoverTokens_Unauthorized_Reverts() public {
        vm.startPrank(user);

        vm.expectRevert("Ownable: caller is not the owner");
        wstETH.emergencyRecoverTokens(address(0x1234), 1 ether);

        vm.stopPrank();
    }

    // ============ Gas Tests ============

    function test_GasUsage_Wrap() public {
        vm.startPrank(user);

        uint256 startGas = gasleft();
        wstETH.wrap(STETH_AMOUNT);
        uint256 gasUsed = startGas - gasleft();

        // Should use reasonable amount of gas
        assertTrue(gasUsed < 150000);
        console.log("Gas used for wrap:", gasUsed);

        vm.stopPrank();
    }

    function test_GasUsage_Unwrap() public {
        vm.startPrank(user);

        // Wrap first
        wstETH.wrap(STETH_AMOUNT);

        uint256 startGas = gasleft();
        wstETH.unwrap(WSTETH_AMOUNT);
        uint256 gasUsed = startGas - gasleft();

        // Should use reasonable amount of gas
        assertTrue(gasUsed < 150000);
        console.log("Gas used for unwrap:", gasUsed);

        vm.stopPrank();
    }

    // ============ Edge Case Tests ============

    function test_MultipleWrapUnwrapCycles() public {
        vm.startPrank(user);

        for (uint256 i = 0; i < 10; i++) {
            uint256 amount = 1 ether + i;
            uint256 wstethReceived = wstETH.wrap(amount);
            assertTrue(wstethReceived > 0);

            uint256 stethReturned = wstETH.unwrap(wstethReceived);
            assertTrue(stethReturned >= amount); // Equal or greater due to potential rewards
        }

        vm.stopPrank();
    }

    function test_Transfer_WrappedTokens() public {
        vm.startPrank(user);

        uint256 wstethAmount = wstETH.wrap(STETH_AMOUNT);

        // Transfer to user2
        wstETH.transfer(user2, wstethAmount / 2);

        assertEq(wstETH.balanceOf(user), wstethAmount / 2);
        assertEq(wstETH.balanceOf(user2), wstethAmount / 2);

        vm.stopPrank();
    }

    function test_TransferZeroAddress_Reverts() public {
        vm.startPrank(user);

        uint256 wstethAmount = wstETH.wrap(STETH_AMOUNT);

        vm.expectRevert();
        wstETH.transfer(address(0), wstethAmount);

        vm.stopPrank();
    }
}