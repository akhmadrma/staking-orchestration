// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILido
 * @dev Interface for MockLido liquid staking contract
 * @notice This interface defines the core functions for liquid staking
 * @dev Based on Lido Finance's liquid staking protocol specifications
 */
interface ILido {
    /**
     * @notice Submits ETH to the staking pool and receives stETH shares
     * @param _referral Address of the referrer (can be zero address)
     * @return shares Amount of shares minted to the caller
     */
    function submit(address _referral) external payable returns (uint256 shares);

    /**
     * @notice Converts shares to the corresponding amount of pooled ETH
     * @param shares Number of shares to convert
     * @return ethAmount Equivalent amount of ETH
     */
    function getPooledEthByShares(uint256 shares) external view returns (uint256 ethAmount);

    /**
     * @notice Converts ETH amount to corresponding number of shares
     * @param ethAmount Amount of ETH to convert
     * @return shares Equivalent number of shares
     */
    function getSharesByPooledEth(uint256 ethAmount) external view returns (uint256 shares);

    /**
     * @notice Gets the total amount of ETH pooled in the contract
     * @return totalPooledEther Total pooled ETH amount
     */
    function getTotalPooledEther() external view returns (uint256 totalPooledEther);

    /**
     * @notice Gets the total number of shares issued
     * @return totalShares Total number of shares
     */
    function getTotalShares() external view returns (uint256 totalShares);

    /**
     * @notice Requests withdrawal of stETH for ETH
     * @param stethAmount Amount of stETH to withdraw
     * @return requestId ID of the withdrawal request
     */
    function requestWithdrawal(uint256 stethAmount) external returns (uint256 requestId);

    /**
     * @notice Claims a previously requested withdrawal
     * @param requestId ID of the withdrawal request to claim
     */
    function claimWithdrawal(uint256 requestId) external;

    /**
     * @notice Emitted when ETH is submitted for staking
     * @param sender Address that submitted the ETH
     * @param referral Referral address used
     * @param amount Amount of ETH submitted
     * @param shares Number of shares received
     */
    event Submitted(address indexed sender, address indexed referral, uint256 amount, uint256 shares);

    /**
     * @notice Emitted when a withdrawal is requested
     * @param owner Address of the withdrawal requester
     * @param amount Amount of stETH to withdraw
     * @param requestId ID of the withdrawal request
     */
    event WithdrawalRequested(address indexed owner, uint256 amount, uint256 requestId);

    /**
     * @notice Emitted when a withdrawal is claimed
     * @param owner Address that claimed the withdrawal
     * @param amount Amount of ETH received
     * @param requestId ID of the withdrawal request
     */
    event WithdrawalClaimed(address indexed owner, uint256 amount, uint256 requestId);
}