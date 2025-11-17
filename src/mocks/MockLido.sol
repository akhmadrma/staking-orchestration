// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/ILido.sol";
import "../interfaces/IOracle.sol";

/**
 * @title MockLido
 * @dev Mock implementation of Lido's liquid staking protocol
 * @notice This contract simulates the core functionality of Lido's liquid staking system
 * @dev Implements ETH → stETH conversion with reward tracking and withdrawal capabilities
 * @author DeFi Restaking Project
 * @custom:security-level This is a mock implementation for testing purposes only
 */
contract MockLido is ERC20, Ownable, Pausable, ReentrancyGuard, ILido {
    // ============ State Variables ============

    /// @notice Total amount of ETH pooled in the contract
    uint256 public totalPooledEther;

    /// @notice Total number of shares issued
    uint256 public totalShares;

    /// @notice Oracle contract for reward reporting
    IOracle public immutable oracle;

    /// @notice Protocol fee in basis points (10% = 1000 basis points)
    uint256 public constant FEE_BPS = 1000;

    /// @notice Maximum fee basis points (100% = 10000 basis points)
    uint256 public constant MAX_FEE_BPS = 10000;

    /// @notice Reward APR for simulation (5% = 500 basis points)
    uint256 public constant REWARD_APR = 500;

    /// @notice Timestamp of last reward distribution
    uint256 public lastRewardTimestamp;

    /// @notice User shares mapping
    mapping(address => uint256) public userShares;

    /// @notice Withdrawal requests mapping
    mapping(uint256 => WithdrawalRequest) public withdrawalRequests;

    /// @notice Next withdrawal request ID
    uint256 public nextWithdrawalRequestId;

    // ============ Structs ============

    /**
     * @dev Withdrawal request structure
     * @param owner Address of the withdrawal requester
     * @param stethAmount Amount of stETH to withdraw
     * @param ethAmount Amount of ETH to receive (may vary with rewards)
     * @param timestamp Request timestamp
     * @param claimed Whether the withdrawal has been claimed
     */
    struct WithdrawalRequest {
        address owner;
        uint256 stethAmount;
        uint256 ethAmount;
        uint256 timestamp;
        bool claimed;
    }

    // ============ Additional Events ============

    /**
     * @notice Emitted when rewards are distributed
     * @param amount Amount of rewards distributed
     * @param timestamp Distribution timestamp
     */
    event RewardsDistributed(uint256 amount, uint256 timestamp);

    /**
     * @notice Emitted when protocol fee is collected
     * @param owner Address receiving the fee
     * @param amount Fee amount collected
     */
    event FeeCollected(address indexed owner, uint256 amount);

    // ============ Errors ============

    error MockLido_ZeroAmount();
    error MockLido_InsufficientShares();
    error MockLido_InvalidOracle();
    error MockLido_InvalidRewardAmount();
    error MockLido_WithdrawalNotFound();
    error MockLido_AlreadyClaimed();
    error MockLido_NotOwner();

    // ============ Modifiers ============

    /**
     * @dev Restricts function calls to oracle contract only
     */
    modifier onlyOracle() {
        if (msg.sender != address(oracle)) revert MockLido_InvalidOracle();
        _;
    }

    // ============ Constructor ============

    /**
     * @notice Initializes the MockLido contract
     * @param _oracle Address of the oracle contract
     */
    constructor(address _oracle)
        ERC20("Mock Staked Ether", "stETH")
        Ownable(msg.sender)
    {
        if (_oracle == address(0)) revert MockLido_InvalidOracle();
        oracle = IOracle(_oracle);
        lastRewardTimestamp = block.timestamp;
        nextWithdrawalRequestId = 1;
    }

    // ============ Core Functions ============

    /**
     * @notice Submits ETH to the staking pool and receives stETH shares
     * @param _referral Address of the referrer (can be zero address)
     * @return shares Amount of shares minted to the caller
     * @dev Implements shares-based accounting similar to real Lido
     */
    function submit(address _referral)
        external
        payable
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        if (msg.value == 0) revert MockLido_ZeroAmount();

        // Calculate shares based on current ratio
        shares = _calculateShares(msg.value);

        // Update state
        totalPooledEther += msg.value;
        totalShares += shares;
        userShares[msg.sender] += shares;

        // Mint stETH to user (1:1 ratio with submitted ETH initially)
        _mint(msg.sender, msg.value);

        // Handle protocol fee
        uint256 fee = (msg.value * FEE_BPS) / MAX_FEE_BPS;
        if (fee > 0) {
            _mint(owner(), fee);
            emit FeeCollected(owner(), fee);
        }

        // Simulate rewards after submission
        _simulateRewards();

        emit Submitted(msg.sender, _referral, msg.value, shares);
    }

    /**
     * @notice Requests withdrawal of stETH for ETH
     * @param stethAmount Amount of stETH to withdraw
     * @return requestId ID of the withdrawal request
     * @dev In real Lido, this would queue the withdrawal for processing
     */
    function requestWithdrawal(uint256 stethAmount)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 requestId)
    {
        if (stethAmount == 0) revert MockLido_ZeroAmount();
        if (balanceOf(msg.sender) < stethAmount) revert MockLido_InsufficientShares();

        requestId = nextWithdrawalRequestId++;
        uint256 ethAmount = _getEthBySteth(stethAmount);

        // Create withdrawal request
        withdrawalRequests[requestId] = WithdrawalRequest({
            owner: msg.sender,
            stethAmount: stethAmount,
            ethAmount: ethAmount,
            timestamp: block.timestamp,
            claimed: false
        });

        // Burn stETH from user
        _burn(msg.sender, stethAmount);

        emit WithdrawalRequested(msg.sender, stethAmount, requestId);
    }

    /**
     * @notice Claims a previously requested withdrawal
     * @param requestId ID of the withdrawal request to claim
     * @dev For simulation, this immediately transfers ETH to the user
     */
    function claimWithdrawal(uint256 requestId) external nonReentrant {
        WithdrawalRequest storage request = withdrawalRequests[requestId];

        if (request.owner == address(0)) revert MockLido_WithdrawalNotFound();
        if (request.claimed) revert MockLido_AlreadyClaimed();
        if (request.owner != msg.sender) revert MockLido_NotOwner();

        // Mark as claimed
        request.claimed = true;

        // Update total pooled ETH and shares
        totalPooledEther -= request.ethAmount;
        uint256 sharesToBurn = _getSharesByEth(request.ethAmount);
        totalShares -= sharesToBurn;
        userShares[request.owner] -= sharesToBurn;

        // Transfer ETH to user (in simulation, this would be from validator withdrawals)
        payable(request.owner).transfer(request.ethAmount);

        emit WithdrawalClaimed(request.owner, request.ethAmount, requestId);
    }

    /**
     * @notice Handles oracle report for real reward data
     * @param postTotalPooledEther New total pooled ETH after rewards
     * @param newTotalShares New total shares (if changed)
     * @param timeElapsed Time elapsed since last report
     */
    function handleOracleReport(
        uint256 postTotalPooledEther,
        uint256 newTotalShares,
        uint256 timeElapsed
    ) external onlyOracle {
        if (postTotalPooledEther < totalPooledEther) revert MockLido_InvalidRewardAmount();

        uint256 rewards = postTotalPooledEther - totalPooledEther;
        if (rewards > 0) {
            totalPooledEther = postTotalPooledEther;
            totalShares = newTotalShares;
            lastRewardTimestamp = block.timestamp;
            emit RewardsDistributed(rewards, block.timestamp);
        }
    }

    // ============ View Functions ============

    /**
     * @notice Converts shares to the corresponding amount of pooled ETH
     * @param shares Number of shares to convert
     * @return ethAmount Equivalent amount of ETH
     */
    function getPooledEthByShares(uint256 shares) external view returns (uint256 ethAmount) {
        return _getEthByShares(shares);
    }

    /**
     * @notice Converts ETH amount to corresponding number of shares
     * @param ethAmount Amount of ETH to convert
     * @return shares Equivalent number of shares
     */
    function getSharesByPooledEth(uint256 ethAmount) external view returns (uint256 shares) {
        return _getSharesByEth(ethAmount);
    }

    /**
     * @notice Gets the total amount of ETH pooled in the contract
     * @return totalPooledEther Total pooled ETH amount
     */
    function getTotalPooledEther() external view returns (uint256) {
        return totalPooledEther;
    }

    /**
     * @notice Gets the total number of shares issued
     * @return totalShares Total number of shares
     */
    function getTotalShares() external view returns (uint256) {
        return totalShares;
    }

    // ============ Internal Functions ============

    /**
     * @notice Calculates shares for a given ETH amount
     * @param ethAmount Amount of ETH to convert
     * @return shares Equivalent number of shares
     * @dev First depositor gets 1:1 ratio, subsequent deposits share rewards
     */
    function _calculateShares(uint256 ethAmount) internal view returns (uint256 shares) {
        if (totalPooledEther == 0 || totalShares == 0) {
            return ethAmount; // First depositor gets 1:1
        }
        return (ethAmount * totalShares) / totalPooledEther;
    }

    /**
     * @notice Converts ETH amount to shares (internal view)
     * @param ethAmount Amount of ETH to convert
     * @return shares Equivalent number of shares
     */
    function _getSharesByEth(uint256 ethAmount) internal view returns (uint256 shares) {
        if (totalPooledEther == 0) return ethAmount;
        return (ethAmount * totalShares) / totalPooledEther;
    }

    /**
     * @notice Converts shares to ETH amount (internal view)
     * @param shares Number of shares to convert
     * @return ethAmount Equivalent amount of ETH
     */
    function _getEthByShares(uint256 shares) internal view returns (uint256 ethAmount) {
        if (totalShares == 0) return 0;
        return (shares * totalPooledEther) / totalShares;
    }

    /**
     * @notice Converts stETH amount to ETH amount (for withdrawals)
     * @param stethAmount Amount of stETH to convert
     * @return ethAmount Equivalent amount of ETH
     */
    function _getEthBySteth(uint256 stethAmount) internal view returns (uint256 ethAmount) {
        // Since stETH tracks ETH 1:1 in our simulation, this is straightforward
        // In real Lido, this would account for accumulated rewards
        return stethAmount;
    }

    /**
     * @notice Simulates reward distribution
     * @dev This simulates the oracle reporting rewards to the contract
     */
    function _simulateRewards() internal {
        uint256 timeSinceLastReward = block.timestamp - lastRewardTimestamp;
        if (timeSinceLastReward > 0 && totalPooledEther > 0) {
            uint256 rewards = (totalPooledEther * REWARD_APR * timeSinceLastReward) / (MAX_FEE_BPS * 365 days);

            if (rewards > 0) {
                totalPooledEther += rewards;
                lastRewardTimestamp = block.timestamp;
                emit RewardsDistributed(rewards, block.timestamp);
            }
        }
    }

    // ============ Owner Functions ============

    /**
     * @notice Pauses the contract (emergency stop)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency function to simulate oracle rewards
     * @param validatorCount Number of validators to simulate
     * @param apr Annual percentage rate (in basis points)
     */
    function emergencySimulateRewards(uint256 validatorCount, uint256 apr) external onlyOwner {
        oracle.simulateRewards(validatorCount, apr);
        _simulateRewards();
    }

    /**
     * @notice Receive ETH function for direct ETH transfers
     */
    receive() external payable {
        // Allow direct ETH transfers for testing
        if (msg.value > 0) {
            this.submit(address(0));
        }
    }

    /**
     * @notice Fallback function for unhandled calls
     */
    fallback() external payable {
        revert("MockLido: fallback not supported");
    }
}