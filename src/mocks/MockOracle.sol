// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/IOracle.sol";

/**
 * @title MockOracle
 * @dev Mock implementation of Lido's oracle system for reward tracking
 * @notice This contract simulates oracle reports for testing purposes
 * @author DeFi Restaking Project
 * @custom:security-level This is a mock implementation for testing purposes only
 */
contract MockOracle is Ownable, Pausable, IOracle {
    // ============ State Variables ============

    /// @notice Current epoch ID
    uint256 public currentEpoch;

    /// @notice Timestamp of last report
    uint256 public lastReportTimestamp;

    /// @notice Mapping of epoch to report data
    mapping(uint256 => ReportData) public reports;

    /// @notice Mock validator balance for simulations
    uint256 public mockValidatorBalance;

    /// @notice Mock active balance for simulations
    uint256 public mockActiveBalance;

    /// @notice Maximum balance change per transaction (10% cap)
    uint256 public constant MAX_BALANCE_CHANGE_BPS = 1000;

    /// @notice Minimum time between balance updates (1 hour)
    uint256 public constant MIN_UPDATE_INTERVAL = 1 hours;

    /// @notice Timestamp of last balance update
    uint256 public lastBalanceUpdateTime;

    // ============ Constructor ============

    /**
     * @notice Initializes the MockOracle contract
     */
    constructor() Ownable(msg.sender) {
        currentEpoch = 0;
        lastReportTimestamp = block.timestamp;
        lastBalanceUpdateTime = block.timestamp;
        mockValidatorBalance = 32 ether; // Standard validator stake
        mockActiveBalance = 32 ether;
    }

    // ============ Core Functions ============

    /**
     * @notice Submits oracle report for rewards
     * @param data Report data containing reward information
     */
    function submitReport(ReportData calldata data) external override onlyOwner whenNotPaused {
        require(data.timestamp > lastReportTimestamp, "MockOracle: Invalid timestamp");

        reports[data.epochId] = data;
        currentEpoch = data.epochId;
        lastReportTimestamp = data.timestamp;

        emit ReportSubmitted(data.epochId, data.totalRewards, data.timestamp);
    }

    /**
     * @notice Simulates rewards for testing purposes
     * @param validatorCount Number of validators to simulate
     * @param apr Annual percentage rate (in basis points)
     */
    function simulateRewards(uint256 validatorCount, uint256 apr) external override onlyOwner whenNotPaused {
        require(validatorCount > 0, "MockOracle: Invalid validator count");
        require(apr > 0 && apr <= 10000, "MockOracle: Invalid APR");

        uint256 timeElapsed = block.timestamp - lastReportTimestamp;
        uint256 totalBalance = mockActiveBalance * validatorCount;
        uint256 rewards = (totalBalance * apr * timeElapsed) / (10000 * 365 days);

        ReportData memory data = ReportData({
            epochId: currentEpoch + 1,
            totalActiveBalance: totalBalance,
            totalValidatorBalance: totalBalance,
            totalRewards: rewards,
            timestamp: block.timestamp
        });

        // Inline the submitReport logic to avoid recursion
        reports[data.epochId] = data;
        currentEpoch = data.epochId;
        lastReportTimestamp = data.timestamp;

        emit ReportSubmitted(data.epochId, data.totalRewards, data.timestamp);
    }

    /**
     * @notice Gets the last oracle report
     * @return data Last reported data
     */
    function getLastReport() external view override returns (ReportData memory data) {
        return reports[currentEpoch];
    }

    // ============ View Functions ============

    /**
     * @notice Gets report data for a specific epoch
     * @param epochId ID of the epoch to query
     * @return data Report data for the epoch
     */
    function getReport(uint256 epochId) external view returns (ReportData memory data) {
        return reports[epochId];
    }

    /**
     * @notice Gets current mock validator balance
     * @return balance Mock validator balance
     */
    function getMockValidatorBalance() external view returns (uint256 balance) {
        return mockValidatorBalance;
    }

    /**
     * @notice Gets current mock active balance
     * @return balance Mock active balance
     */
    function getMockActiveBalance() external view returns (uint256 balance) {
        return mockActiveBalance;
    }

    // ============ Owner Functions ============

    /**
     * @notice Sets mock validator balance for testing
     * @param balance New mock validator balance
     */
    function setMockValidatorBalance(uint256 balance) external onlyOwner {
        require(balance > 0, "MockOracle: Balance must be greater than 0");
        require(block.timestamp >= lastBalanceUpdateTime + MIN_UPDATE_INTERVAL, "MockOracle: Rate limited");

        uint256 maxChange = (mockValidatorBalance * MAX_BALANCE_CHANGE_BPS) / 10000;
        uint256 actualChange = balance > mockValidatorBalance ? balance - mockValidatorBalance : mockValidatorBalance - balance;
        require(actualChange <= maxChange, "MockOracle: Balance change too large");

        mockValidatorBalance = balance;
        lastBalanceUpdateTime = block.timestamp;
    }

    /**
     * @notice Sets mock active balance for testing
     * @param balance New mock active balance
     */
    function setMockActiveBalance(uint256 balance) external onlyOwner {
        require(balance > 0, "MockOracle: Balance must be greater than 0");
        require(block.timestamp >= lastBalanceUpdateTime + MIN_UPDATE_INTERVAL, "MockOracle: Rate limited");

        uint256 maxChange = (mockActiveBalance * MAX_BALANCE_CHANGE_BPS) / 10000;
        uint256 actualChange = balance > mockActiveBalance ? balance - mockActiveBalance : mockActiveBalance - balance;
        require(actualChange <= maxChange, "MockOracle: Balance change too large");

        mockActiveBalance = balance;
        lastBalanceUpdateTime = block.timestamp;
    }

    /**
     * @notice Sets mock validator balance for testing (bypasses rate limits)
     * @param balance New mock validator balance
     * @param bypassRateLimit Whether to bypass rate limit checks
     */
    function setMockValidatorBalanceForTesting(uint256 balance, bool bypassRateLimit) external onlyOwner {
        require(balance > 0, "MockOracle: Balance must be greater than 0");

        if (!bypassRateLimit) {
            require(block.timestamp >= lastBalanceUpdateTime + MIN_UPDATE_INTERVAL, "MockOracle: Rate limited");

            uint256 maxChange = (mockValidatorBalance * MAX_BALANCE_CHANGE_BPS) / 10000;
            uint256 actualChange = balance > mockValidatorBalance ? balance - mockValidatorBalance : mockValidatorBalance - balance;
            require(actualChange <= maxChange, "MockOracle: Balance change too large");
        }

        mockValidatorBalance = balance;
        lastBalanceUpdateTime = block.timestamp;
    }

    /**
     * @notice Sets mock active balance for testing (bypasses rate limits)
     * @param balance New mock active balance
     * @param bypassRateLimit Whether to bypass rate limit checks
     */
    function setMockActiveBalanceForTesting(uint256 balance, bool bypassRateLimit) external onlyOwner {
        require(balance > 0, "MockOracle: Balance must be greater than 0");

        if (!bypassRateLimit) {
            require(block.timestamp >= lastBalanceUpdateTime + MIN_UPDATE_INTERVAL, "MockOracle: Rate limited");

            uint256 maxChange = (mockActiveBalance * MAX_BALANCE_CHANGE_BPS) / 10000;
            uint256 actualChange = balance > mockActiveBalance ? balance - mockActiveBalance : mockActiveBalance - balance;
            require(actualChange <= maxChange, "MockOracle: Balance change too large");
        }

        mockActiveBalance = balance;
        lastBalanceUpdateTime = block.timestamp;
    }

    /**
     * @notice Pauses the oracle (emergency stop)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the oracle
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Resets oracle state for testing
     */
    function reset() external onlyOwner {
        currentEpoch = 0;
        lastReportTimestamp = block.timestamp;
        mockValidatorBalance = 32 ether;
        mockActiveBalance = 32 ether;
    }
}