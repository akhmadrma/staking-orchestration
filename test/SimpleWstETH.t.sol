// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/mocks/MockOracle.sol";
import "../src/mocks/MockLido.sol";
import "../src/mocks/MockWstETH.sol";

contract SimpleWstETHTest is Test {
    function test_BasicDeployment() public {
        // Deploy oracle
        MockOracle oracle = new MockOracle();

        // Deploy lido
        MockLido lido = new MockLido(address(oracle));

        // Deploy wstETH - this should work
        MockWstETH wstETH = new MockWstETH(address(lido));

        // Basic checks
        assertTrue(address(wstETH) != address(0));
        assertTrue(address(lido) != address(0));
        assertTrue(address(oracle) != address(0));

        // Check wstETH points to correct lido
        assertEq(wstETH.getStETHAddress(), address(lido));

        // Check basic ERC20 properties
        assertEq(wstETH.name(), "Mock Wrapped Staked Ether");
        assertEq(wstETH.symbol(), "wstETH");
    }

    function test_WrapUnwrapBasic() public {
        // Setup contracts like in the original test
        address owner = address(0x1);
        address user = address(0x2);

        vm.startPrank(owner);

        // Deploy oracle and lido contracts
        MockOracle oracle = new MockOracle();
        MockLido lido = new MockLido(address(oracle));
        MockWstETH wstETH = new MockWstETH(address(lido));

        vm.stopPrank();

        // Set initial oracle mock values (bypass rate limits for testing)
        vm.startPrank(owner);
        oracle.setMockValidatorBalanceForTesting(32 ether, true);
        oracle.setMockActiveBalanceForTesting(32 ether, true);
        vm.stopPrank();

        // Give user ETH and get stETH
        vm.deal(user, 200 ether);
        uint256 LARGE_AMOUNT = 1000 ether;

        vm.startPrank(user);
        lido.submit{value: LARGE_AMOUNT}(address(0));

        // Approve wstETH to use stETH - this might be the issue
        lido.approve(address(wstETH), type(uint256).max);
        vm.stopPrank();

        // Now test wrap
        vm.startPrank(user);
        uint256 STETH_AMOUNT = 10 ether;
        uint256 wstethReceived = wstETH.wrap(STETH_AMOUNT);
        assertEq(wstethReceived, STETH_AMOUNT);

        // Test unwrap
        uint256 stethReturned = wstETH.unwrap(wstethReceived);
        assertEq(stethReturned, STETH_AMOUNT);
        vm.stopPrank();
    }
}
