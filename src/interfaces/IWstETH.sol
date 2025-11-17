// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IWstETH
 * @dev Interface for MockWstETH wrapper contract
 * @notice This interface defines the functions for wrapping and unwrapping stETH
 * @dev Based on Lido Finance's wrapped stETH (wstETH) specifications
 */
interface IWstETH {
    /**
     * @notice Wraps stETH tokens into wstETH tokens
     * @param stethAmount Amount of stETH tokens to wrap
     * @return wstethAmount Amount of wstETH tokens received
     */
    function wrap(uint256 stethAmount) external returns (uint256 wstethAmount);

    /**
     * @notice Unwraps wstETH tokens back to stETH tokens
     * @param wstethAmount Amount of wstETH tokens to unwrap
     * @return stethAmount Amount of stETH tokens received
     */
    function unwrap(uint256 wstethAmount) external returns (uint256 stethAmount);

    /**
     * @notice Gets the current ratio of stETH per wstETH
     * @return ratio Amount of stETH tokens represented by 1 wstETH token
     */
    function stETHPerWstETH() external view returns (uint256 ratio);

    /**
     * @notice Gets the current ratio of wstETH per stETH
     * @return ratio Amount of wstETH tokens represented by 1 stETH token
     */
    function wstETHPerStETH() external view returns (uint256 ratio);

    /**
     * @notice Converts wstETH amount to equivalent stETH amount
     * @param wstethAmount Amount of wstETH tokens to convert
     * @return stethAmount Equivalent amount of stETH tokens
     */
    function getStETHByWstETH(uint256 wstethAmount) external view returns (uint256 stethAmount);

    /**
     * @notice Converts stETH amount to equivalent wstETH amount
     * @param stethAmount Amount of stETH tokens to convert
     * @return wstethAmount Equivalent amount of wstETH tokens
     */
    function getWstETHByStETH(uint256 stethAmount) external view returns (uint256 wstethAmount);

    /**
     * @notice Gets the address of the underlying stETH token
     * @return stethContract Address of the stETH contract
     */
    function getStETHAddress() external view returns (address stethContract);

    /**
     * @notice Emitted when stETH tokens are wrapped into wstETH
     * @param caller Address that initiated the wrapping
     * @param stethAmount Amount of stETH tokens wrapped
     * @param wstethAmount Amount of wstETH tokens received
     */
    event Wrapped(address indexed caller, uint256 stethAmount, uint256 wstethAmount);

    /**
     * @notice Emitted when wstETH tokens are unwrapped back to stETH
     * @param caller Address that initiated the unwrapping
     * @param wstethAmount Amount of wstETH tokens unwrapped
     * @param stethAmount Amount of stETH tokens received
     */
    event Unwrapped(address indexed caller, uint256 wstethAmount, uint256 stethAmount);
}
