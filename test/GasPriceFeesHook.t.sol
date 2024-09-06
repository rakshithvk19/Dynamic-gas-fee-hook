// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {GasPriceFeesHook} from "../src/GasPriceFeesHook.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {console} from "forge-std/console.sol";

contract GasPriceFeesHookTest is Test, Deployers {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    GasPriceFeesHook hook;

    function setUp() public {
        //Deploy v4-core
        deployFreshManagerAndRouters();

        //Deploy, mint and approve all periphery contract for the two tokens
        deployMintAndApprove2Currencies();

        //Deploy the hooks with proper flags.
        address hookAddress =
            address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_FLAG));

        //Setting the initial gas price to 10 gwei since foundry's default is 0 gwei
        vm.txGasPrice(10 gwei);
        deployCodeTo("GasPriceFeesHook", abi.encode(manager), hookAddress);
        hook = GasPriceFeesHook(hookAddress);

        //Initializing the pool and enabling dynamic fee flag
        (key,) = initPool(currency0, currency1, hook, LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1, ZERO_BYTES);

        //Adding initial liquidity
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 100 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function test_feeUpdatesWithGasPrice() public {
        //Initializing swapParams and swapTest settings.
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -0.00001 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        //Verifying initial state variables in our hook contract.
        uint128 gasPrice = uint128(tx.gasprice);
        uint128 movingAverageGasPrice = hook.movingAverageGasPrice();
        uint128 movingAverageGasPriceCount = hook.movingAverageGasPriceCount();
        assertEq(gasPrice, 10 gwei);
        assertEq(movingAverageGasPrice, 10 gwei);
        assertEq(movingAverageGasPriceCount, 1);

        /**
         * Swaping at gasPrice = 10 gwei
         */
        //verifying initial token balances.
        uint256 balanceOfToken1Before = currency1.balanceOfSelf();

        //performing the swap
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        //capturing token balances after the swap.
        uint256 balanceOfToken1After = currency1.balanceOfSelf();

        //Verifying the swap is successful
        assertGt(balanceOfToken1After, balanceOfToken1Before);

        //What is this for???
        uint256 outputFromBaseFeeSwap = (balanceOfToken1After - balanceOfToken1Before);

        //Asserting the changes in movingAverageGasPrice and movingAverageGasPriceCount
        movingAverageGasPrice = hook.movingAverageGasPrice();
        movingAverageGasPriceCount = hook.movingAverageGasPriceCount();
        assertEq(movingAverageGasPrice, 10 gwei);
        assertEq(movingAverageGasPriceCount, 2);

        /**
         * Performing the swap at gasPrice = 4 gwei
         */
        vm.txGasPrice(4 gwei);

        balanceOfToken1Before = currency1.balanceOfSelf();
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        balanceOfToken1After = currency1.balanceOfSelf();

        //Asserting the swap is successful.
        assertGt(balanceOfToken1After, balanceOfToken1Before);

        //Whats this??
        uint256 outputFromIncreasedFeeSwap = (balanceOfToken1After - balanceOfToken1Before);

        /**
         * MovingAverageGasPrice = ((10 * 2) + 4 )/ 3 = 8
         */

        //Asserting the changes in movingAverageGasPrice and movingAverageGasPriceCount
        movingAverageGasPrice = hook.movingAverageGasPrice();
        movingAverageGasPriceCount = hook.movingAverageGasPriceCount();
        assertEq(movingAverageGasPrice, 8 gwei);
        assertEq(movingAverageGasPriceCount, 3);

        /**
         * Performing swap at gasPrice = 12 gwei
         */
        vm.txGasPrice(12 gwei);

        //Performing swap and capturing token balances
        balanceOfToken1Before = currency1.balanceOfSelf();
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        balanceOfToken1After = currency1.balanceOfSelf();

        //Asserting the swap is successful.
        assertGt(balanceOfToken1After, balanceOfToken1Before);

        //What is this?
        uint256 outputFromDecreasedFeeSwap = (balanceOfToken1After - balanceOfToken1Before);

        /**
         * MovingAverageGasPrice = ((8 * 3) + 12) / 3 + 1 = 9
         */
        movingAverageGasPrice = hook.movingAverageGasPrice();
        movingAverageGasPriceCount = hook.movingAverageGasPriceCount();
        assertEq(movingAverageGasPrice, 9 gwei);
        assertEq(movingAverageGasPriceCount, 4);

        //Check all the output amounts

        console.log("Base Fee Output", outputFromBaseFeeSwap);
        console.log("Increased Fee Output", outputFromIncreasedFeeSwap);
        console.log("Decreased Fee Output", outputFromDecreasedFeeSwap);

        assertGt(outputFromDecreasedFeeSwap, outputFromBaseFeeSwap);
        assertGt(outputFromBaseFeeSwap, outputFromIncreasedFeeSwap);
    }
}
