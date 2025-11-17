// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IOracle
 * @dev Interface for MockOracle reward tracking and reporting
 * @notice This interface defines the oracle functions for tracking staking rewards
 */
interface IOracle {
    struct ReportData {
        uint256 epochId; // Epoch identifier
        uint256 totalActiveBalance; // Total active validator balance
        uint256 totalValidatorBalance; // Total validator balance
        uint256 totalRewards; // Total rewards for the epoch
        uint256 timestamp; // Report timestamp
    }

    /**
     * @notice Submits oracle report for rewards
     * @param data Report data containing reward information
     */
    function submitReport(ReportData calldata data) external;

    /**
     * @notice Simulates rewards for testing purposes
     * @param validatorCount Number of validators to simulate
     * @param apr Annual percentage rate (in basis points)
     */
    function simulateRewards(uint256 validatorCount, uint256 apr) external;

    /**
     * @notice Gets the last oracle report
     * @return data Last reported data
     */
    function getLastReport() external view returns (ReportData memory data);

    /**
     * @notice Emitted when a report is submitted
     * @param epochId ID of the epoch
     * @param totalRewards Total rewards reported
     * @param timestamp Report timestamp
     */
    event ReportSubmitted(uint256 indexed epochId, uint256 totalRewards, uint256 timestamp);
}
