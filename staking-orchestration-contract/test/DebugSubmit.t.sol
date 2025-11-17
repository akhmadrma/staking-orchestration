// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/mocks/MockOracle.sol";
import "../src/mocks/MockLido.sol";
import "../src/mocks/MockWstETH.sol";

contract DebugSubmitTest is Test {
    function test_SimpleSubmit() public {
        // Deploy oracle
        MockOracle oracle = new MockOracle();
        oracle.setMockValidatorBalanceForTesting(32 ether, true);
        oracle.setMockActiveBalanceForTesting(32 ether, true);

        // Deploy lido
        MockLido lido = new MockLido(address(oracle));

        // Give user ETH
        address user = address(0x2);
        vm.deal(user, 200 ether);

        // Test submit
        vm.startPrank(user);
        uint256 shares = lido.submit{value: 1 ether}(address(0));
        console.log("Shares received:", shares);
        console.log("User stETH balance:", lido.balanceOf(user));
        vm.stopPrank();
    }
}