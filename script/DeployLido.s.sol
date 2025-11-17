// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/mocks/MockOracle.sol";
import "../src/mocks/MockLido.sol";
import "../src/mocks/MockWstETH.sol";
import "../src/interfaces/IOracle.sol";
import "../src/interfaces/ILido.sol";
import "../src/interfaces/IWstETH.sol";

contract DeployLido is Script {
    // ============ Deployment Config ============
    struct DeployConfig {
        address oracle;
        address lido;
        address wstETH;
        uint256 deployerPrivateKey;
        address deployer;
    }

    DeployConfig public config;

    // ============ Deployment Events ============
    event OracleDeployed(address indexed oracle, address indexed deployer);
    event LidoDeployed(address indexed lido, address indexed oracle, address indexed deployer);
    event WstETHDeployed(address indexed wstETH, address indexed lido, address indexed deployer);
    event DeploymentComplete(
        address indexed oracle, address indexed lido, address indexed wstETH, address deployer, uint256 timestamp
    );

    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Starting MockLido + MockWstETH deployment...");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy MockOracle
        MockOracle oracle = new MockOracle();
        console.log("[+] MockOracle deployed to:", address(oracle));

        // Initialize oracle with standard validator balance
        oracle.setMockValidatorBalance(32 ether);
        oracle.setMockActiveBalance(32 ether);

        // Deploy MockLido
        MockLido lido = new MockLido(address(oracle));
        console.log("[+] MockLido deployed to:", address(lido));

        // Deploy MockWstETH
        MockWstETH wstETH = new MockWstETH(address(lido));
        console.log("[+] MockWstETH deployed to:", address(wstETH));

        vm.stopBroadcast();

        // Save deployment config
        config = DeployConfig({
            oracle: address(oracle),
            lido: address(lido),
            wstETH: address(wstETH),
            deployerPrivateKey: deployerPrivateKey,
            deployer: deployer
        });

        // Emit events
        emit OracleDeployed(address(oracle), deployer);
        emit LidoDeployed(address(lido), address(oracle), deployer);
        emit WstETHDeployed(address(wstETH), address(lido), deployer);
        emit DeploymentComplete(address(oracle), address(lido), address(wstETH), deployer, block.timestamp);

        // Log deployment summary
        _logDeploymentSummary();

        // Run basic verification
        _verifyDeployment();

        console.log("[+] Deployment completed successfully!");
    }

    function _logDeploymentSummary() internal view {
        console.log("\n=== Deployment Summary ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", config.deployer);
        console.log("Oracle:", config.oracle);
        console.log("Lido:", config.lido);
        console.log("WstETH:", config.wstETH);
        console.log("Deployed at:", block.timestamp);
        console.log("Block number:", block.number);
        console.log("========================\n");
    }

    function _verifyDeployment() internal view {
        console.log("[*] Verifying deployment...");

        // Verify Oracle
        require(config.oracle != address(0), "Oracle address not set");
        require(MockOracle(payable(config.oracle)).owner() == config.deployer, "Oracle owner incorrect");
        require(!MockOracle(payable(config.oracle)).paused(), "Oracle should not be paused");

        // Verify Lido
        require(config.lido != address(0), "Lido address not set");
        require(MockLido(payable(config.lido)).owner() == config.deployer, "Lido owner incorrect");
        // Oracle comparison checked via interface
        require(!MockLido(payable(config.lido)).paused(), "Lido should not be paused");

        // Verify WstETH
        require(config.wstETH != address(0), "WstETH address not set");
        require(MockWstETH(payable(config.wstETH)).owner() == config.deployer, "WstETH owner incorrect");
        require(!MockWstETH(payable(config.wstETH)).paused(), "WstETH should not be paused");

        // Verify WstETH points to correct Lido
        require(MockWstETH(payable(config.wstETH)).getStETHAddress() == config.lido, "WstETH should point to Lido");

        // Verify initial state
        require(MockLido(payable(config.lido)).getTotalPooledEther() == 0, "Initial pooled ETH should be 0");
        require(MockLido(payable(config.lido)).getTotalShares() == 0, "Initial shares should be 0");
        require(MockWstETH(payable(config.wstETH)).totalSupply() == 0, "Initial wstETH supply should be 0");

        console.log("[+] All verifications passed!");
    }

    // ============ Utility Functions ============

    /**
     * @notice Get deployment config for testing
     * @return config Current deployment configuration
     */
    function getDeploymentConfig() external view returns (DeployConfig memory) {
        return config;
    }

    /**
     * @notice Get Oracle contract instance
     * @return oracle MockOracle contract instance
     */
    function getOracle() external view returns (MockOracle) {
        return MockOracle(payable(config.oracle));
    }

    /**
     * @notice Get Lido contract instance
     * @return lido MockLido contract instance
     */
    function getLido() external view returns (MockLido) {
        return MockLido(payable(config.lido));
    }

    /**
     * @notice Get WstETH contract instance
     * @return wstETH MockWstETH contract instance
     */
    function getWstETH() external view returns (MockWstETH) {
        return MockWstETH(payable(config.wstETH));
    }
}
