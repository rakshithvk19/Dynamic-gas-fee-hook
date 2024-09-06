# Dynamic Gas Fee Hook

## Core concept
When we change dynamic fees, we are actually changing the LP fees charged and paid to the LP. 
We are not changing the Protocol fees and the custom fee that we pay for the individual hook. 

## Overview

## Mechanism Design

## Assumptions
1. We are using `movingAverageGapPrice` to track the changes in gas fee. BUT this variable tracks the gasFees only on transaction done on this pool and does not consider transactions done outside this pool. 

2. We are tracking changes in the gasPrice, only duing `afterSwap`. To get the most accurate gasPrice updates based on the txs happening in this pool, we need to enable all the hooks and track the gasPrice throughout the lifecycle of the pool.

## Potential Improvements
1. Update `movingAverageGasPrice` by tracking gasPrice throughout the lifecycle of the pool. 


## Workflow
Initially the gas price is the base fee

Before the first swap, the dynamic fee is the base fee
and after the first swap, the movingAverageFee and the movingAverageCount gets updated

As more Tx happen, the movingAverageCount gets updated, beforeSwap increases the fee and swap fee gets updated.
after the swap is done, the movingAverageFee and movingAverageCount is updated