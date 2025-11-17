// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IWstETH.sol";
import "../interfaces/ILido.sol";

/**
 * @title MockWstETH
 * @dev Mock implementation of Lido's wrapped stETH (wstETH) token
 * @notice This contract simulates the wstETH wrapper token that represents shares of stETH
 * @dev Implements wstETH as a non-rebasing ERC20 token where each token represents a share of stETH
 * @author DeFi Restaking Project
 * @custom:security-level This is a mock implementation for testing purposes only
 */
contract MockWstETH is ERC20, Ownable, Pausable, ReentrancyGuard, IWstETH {
    // ============ State Variables ============

    /// @notice The underlying stETH token contract
    ILido public immutable stETH;

    /// @notice Scaling factor for precision (18 decimals)
    uint256 private constant PRECISION = 1e18;

    /// @notice Minimum amount for wrap/unwrap operations
    uint256 public constant MIN_AMOUNT = 1 wei;

    // ============ Constructor ============

    /**
     * @notice Initializes the MockWstETH contract
     * @param _steth Address of the underlying stETH token contract
     */
    constructor(address _steth) ERC20("Mock Wrapped Staked Ether", "wstETH") Ownable(msg.sender) {
        if (_steth == address(0)) revert MockWstETH_ZeroStETHAddress();
        stETH = ILido(_steth);
    }

    // ============ Core Functions ============

    /**
     * @notice Wraps stETH tokens into wstETH tokens
     * @dev Transfers stETH from caller and mints wstETH 1:1 based on current shares
     * @param stethAmount Amount of stETH tokens to wrap
     * @return wstethAmount Amount of wstETH tokens received
     */
    function wrap(uint256 stethAmount)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 wstethAmount)
    {
        if (stethAmount < MIN_AMOUNT) revert MockWstETH_ZeroAmount();

        // Calculate equivalent wstETH amount based on current ratio
        if (totalSupply() == 0) {
            wstethAmount = stethAmount; // 1:1 when no wstETH exists
        } else {
            uint256 stethBalance = IERC20(address(stETH)).balanceOf(address(this));
            if (stethBalance == 0) {
                revert MockWstETH_ZeroWstETHReturned();
            }
            // Prevent zero-division and ensure reasonable input
            require(stethBalance >= MIN_AMOUNT, "MockWstETH: Insufficient contract balance");
            require(stethAmount <= stethBalance, "MockWstETH: Amount exceeds contract balance");

            wstethAmount = (stethAmount * totalSupply()) / stethBalance;

            // Ensure minimum return amount
            if (wstethAmount == 0) {
                revert MockWstETH_ZeroWstETHReturned();
            }
        }

        // Additional sanity checks
        require(wstethAmount > 0, "MockWstETH: Zero wstETH amount returned");
        require(wstethAmount <= totalSupply() + stethAmount, "MockWstETH: Excessive wstETH amount");

        // Transfer stETH from caller to this contract
        IERC20(address(stETH)).transferFrom(msg.sender, address(this), stethAmount);

        // Mint wstETH to caller
        _mint(msg.sender, wstethAmount);

        emit Wrapped(msg.sender, stethAmount, wstethAmount);
    }

    /**
     * @notice Unwraps wstETH tokens back to stETH tokens
     * @dev Burns wstETH and transfers equivalent stETH back to caller
     * @param wstethAmount Amount of wstETH tokens to unwrap
     * @return stethAmount Amount of stETH tokens received
     */
    function unwrap(uint256 wstethAmount)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 stethAmount)
    {
        if (wstethAmount < MIN_AMOUNT) revert MockWstETH_ZeroAmount();

        // Calculate equivalent stETH amount based on current ratio
        if (totalSupply() == 0) {
            stethAmount = wstethAmount; // 1:1 when no wstETH exists
        } else {
            stethAmount = (wstethAmount * IERC20(address(stETH)).balanceOf(address(this))) / totalSupply();
        }

        if (stethAmount == 0) revert MockWstETH_ZeroStETHReturned();

        // Check contract has enough stETH
        if (IERC20(address(stETH)).balanceOf(address(this)) < stethAmount) {
            revert MockWstETH_InsufficientLiquidity();
        }

        // Burn wstETH from caller
        _burn(msg.sender, wstethAmount);

        // Transfer stETH to caller
        IERC20(address(stETH)).transfer(msg.sender, stethAmount);

        emit Unwrapped(msg.sender, wstethAmount, stethAmount);
    }

    // ============ View Functions ============

    /**
     * @notice Gets the current ratio of stETH per wstETH
     * @dev Returns the amount of stETH represented by 1 wstETH token
     * @return ratio Amount of stETH tokens per wstETH token
     */
    function stETHPerWstETH() external view returns (uint256 ratio) {
        if (totalSupply() == 0) {
            // When no wstETH exists, 1 wstETH = 1 stETH
            return PRECISION;
        }
        return (IERC20(address(stETH)).balanceOf(address(this)) * PRECISION) / totalSupply();
    }

    /**
     * @notice Gets the current ratio of wstETH per stETH
     * @dev Returns the amount of wstETH represented by 1 stETH token
     * @return ratio Amount of wstETH tokens per stETH token
     */
    function wstETHPerStETH() external view returns (uint256 ratio) {
        uint256 stethPerWsteth;
        if (totalSupply() == 0) {
            stethPerWsteth = PRECISION;
        } else {
            stethPerWsteth = (IERC20(address(stETH)).balanceOf(address(this)) * PRECISION) / totalSupply();
        }

        if (stethPerWsteth == 0) {
            return 0;
        }
        return (PRECISION * PRECISION) / stethPerWsteth;
    }

    /**
     * @notice Converts wstETH amount to equivalent stETH amount
     * @param wstethAmount Amount of wstETH tokens to convert
     * @return stethAmount Equivalent amount of stETH tokens
     */
    function getStETHByWstETH(uint256 wstethAmount) external view returns (uint256 stethAmount) {
        if (totalSupply() == 0) {
            // When no wstETH exists, conversion is 1:1
            return wstethAmount;
        }
        return (wstethAmount * IERC20(address(stETH)).balanceOf(address(this))) / totalSupply();
    }

    /**
     * @notice Converts stETH amount to equivalent wstETH amount
     * @param stethAmount Amount of stETH tokens to convert
     * @return wstethAmount Equivalent amount of wstETH tokens
     */
    function getWstETHByStETH(uint256 stethAmount) external view returns (uint256 wstethAmount) {
        if (stethAmount == 0) return 0;

        if (totalSupply() == 0) {
            // When no wstETH exists, conversion is 1:1
            return stethAmount;
        }
        uint256 stethBalance = IERC20(address(stETH)).balanceOf(address(this));
        if (stethBalance == 0) {
            return 0;
        }
        // Safe division with zero-division protection
        return (stethAmount * totalSupply()) / stethBalance;
    }

    /**
     * @notice Gets the address of the underlying stETH token
     * @return stethContract Address of the stETH contract
     */
    function getStETHAddress() external view returns (address stethContract) {
        return address(stETH);
    }

    // ============ Internal Functions ============

    /**
     * @notice Hook called before any token transfer
     * @dev Prevents transfers to zero address
     * @param from Address tokens are transferred from
     * @param to Address tokens are transferred to
     * @param amount Amount of tokens to transfer
     */
    function _update(address from, address to, uint256 amount) internal virtual override {
        // Allow burns (where to == address(0) and from != address(0))
        // Only prevent regular transfers to zero address
        if (to == address(0) && from != address(0)) {
            // This is a burn operation, allow it
        } else if (to == address(0)) {
            revert MockWstETH_TransferToZeroAddress();
        }
        super._update(from, to, amount);
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
     * @notice Emergency recovery of stuck tokens
     * @param token Address of the token to recover
     * @param amount Amount of tokens to recover
     */
    function emergencyRecoverTokens(address token, uint256 amount) external onlyOwner {
        if (token == address(this)) {
            revert MockWstETH_CannotRecoverOwnTokens();
        }
        if (token == address(stETH)) {
            revert MockWstETH_CannotRecoverStETH();
        }

        IERC20 tokenContract = IERC20(token);
        tokenContract.transfer(owner(), amount);
    }

    // ============ Events ============
    // Events are declared in IWstETH interface

    // ============ Custom Errors ============

    error MockWstETH_ZeroAmount();
    error MockWstETH_ZeroWstETHReturned();
    error MockWstETH_ZeroStETHReturned();
    error MockWstETH_InsufficientLiquidity();
    error MockWstETH_TransferToZeroAddress();
    error MockWstETH_CannotRecoverOwnTokens();
    error MockWstETH_CannotRecoverStETH();
    error MockWstETH_ZeroStETHAddress();
    error MockWstETH_UnauthorizedCall();
}