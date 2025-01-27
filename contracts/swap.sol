// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

    import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
interface ICrocQuery {
    function queryPrice(
        address base,
        address quote,
        uint256 poolIdx
    ) external view returns (uint128);
}

    interface ICrocSwapDex{
    function multiSwap (
        SwapStep[] memory _steps,
        uint128 _amount,
        uint128 _minOut
    ) external  payable returns (uint128 out);
    struct SwapStep {
        uint256 poolIdx;
        address base;
        address quote;
        bool isBuy;
    }   
    }

contract CrocQueryPriceFetcher {
    IERC20 public token;
    ICrocQuery public crocQuery;
    ICrocSwapDex public crocSwapDex;
    address public baseToken;
    address public quoteToken;
    uint256 public poolIdx;

    constructor() {
        crocQuery = ICrocQuery(0x8685CE9Db06D40CBa73e3d09e6868FE476B5dC89);
        baseToken = 0x0E4aaF1351de4c0264C5c7056Ef3777b41BD8e03; //Honey
        quoteToken = 0x7507c1dc16935B82698e4C63f2746A2fCf994dF8; //Lick
        poolIdx = 36000;
        crocSwapDex = ICrocSwapDex(0x21e2C0AFd058A89FCf7caf3aEA3cB84Ae977B73D);
    }

    function getPrice() public view returns (uint256) {
        uint128 priceRoot = crocQuery.queryPrice(
            baseToken,
            quoteToken,
            poolIdx
        );

        uint256 sq = (uint256(priceRoot) * 1e18) / (2 ** 64);
        uint256 honeyPerLick = (sq * sq) / 1e18;

        return honeyPerLick;
    }
    function swapToken(uint256 ozFee, address _token) public {
        IERC20(_token).approve(address(crocSwapDex), ozFee);
        
        ICrocSwapDex.SwapStep[] memory steps = new ICrocSwapDex.SwapStep[](1);
        steps[0] = ICrocSwapDex.SwapStep({
            poolIdx: poolIdx,
            base: _token,
            quote: baseToken,
            isBuy: false
        });
    
        ICrocSwapDex(0x21e2C0AFd058A89FCf7caf3aEA3cB84Ae977B73D).multiSwap(steps, uint128(ozFee), 0);

    }

}
