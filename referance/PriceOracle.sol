// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IUniswapV2Pair, IUniswapV2Factory, IUniswapV2Router01} from "../interfaces/IUniswapV2.sol";

contract PriceOracle is Initializable, OwnableUpgradeable {
    address public factory;
    address public lick;
    address public honey;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _factory,
        address _lick,
        address _honey,
        address _owner
    ) public initializer {
        factory = _factory;
        lick = _lick;
        honey = _honey;
        __Ownable_init(_owner);
    }

    /**
     * @notice Returns the price of 1 LICK in HONEY
     */
    function getAmountsOutByHoney(
        uint256 amountA
    ) public view returns (uint256) {
        return getPrice(lick, honey, amountA);
    }

    /**
     * @notice Returns how much LICK you get for 1 HONEY
     */
    function getAmountsOutByLick(
        uint256 amountA
    ) public view returns (uint256) {
        return getPrice(honey, lick, amountA);
    }

    /**
     * @notice Fetch the value of `amountA` tokens of `tokenA` in terms of `tokenB`
     * @param tokenA The address of the token to fetch the value for
     * @param tokenB The address of the token used as a reference
     * @param amountA The amount of `tokenA` to convert to `tokenB`
     * @return price The equivalent value of `amountA` in `tokenB`
     */
    function getPrice(
        address tokenA,
        address tokenB,
        uint256 amountA
    ) public view returns (uint256 price) {
        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "Pair does not exist");

        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pair)
            .getReserves();
        (address token0, ) = sortTokens(tokenA, tokenB);

        if (token0 == tokenA)
            return (amountA * uint256(reserve1)) / uint256(reserve0);
        else return (amountA * uint256(reserve0)) / uint256(reserve1);
    }

    /**
     * @notice Sorts token addresses to ensure a consistent order
     */
    function sortTokens(
        address tokenA,
        address tokenB
    ) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "Identical addresses");
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
    }

    /**
     * @notice Allows the owner to update the Uniswap factory, LICK, or HONEY addresses
     */
    function setFactory(address _factory) external onlyOwner {
        factory = _factory;
    }

    function setTokens(address _lick, address _honey) external onlyOwner {
        lick = _lick;
        honey = _honey;
    }
}
