// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

interface IPriceOracle {
    function getAmountsOutByHoney(
        uint256 amountA
    ) external view returns (uint256);
    function getAmountsOutByLick(
        uint256 amountA
    ) external view returns (uint256);
    function getPrice(
        address tokenA,
        address tokenB,
        uint256 amountA
    ) external view returns (uint256 price);
}
