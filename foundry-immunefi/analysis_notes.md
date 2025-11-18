# Threshold Network Splitter Audit

## Contract Overview

### Splitter_03fd (0x03fd3d61423e6d46dcc3917862fbc57653dc3eb0)
- Has configurable `fee` state variable (can be changed by owner)
- Inherits from `Withdrawable` (allows owner to withdraw stuck funds)
- Fee is stored and used from state

### Splitter_3234 (0x323498d3fb02594ac3e0a11b2dea337893ecabbe)
- Fee is passed as parameter to `payWhitehat()`
- Does NOT inherit from `Withdrawable`
- No mechanism to withdraw stuck funds

## Key Functionality
Both contracts facilitate bounty payments by:
1. Transferring ERC20 tokens from caller to whitehat + fee recipient
2. Transferring native ETH from caller to whitehat + fee recipient
3. Refunding excess ETH to caller

## Initial Observations

### Critical Differences:
1. **Withdrawable**: Only 03fd has withdrawal functionality
2. **Fee mechanism**: 03fd uses state variable, 3234 uses parameter

### Potential Issues to Investigate:
1. Missing msg.value validation in _payWhitehatNative()
2. Permanent freezing in Splitter_3234 (no withdrawal)
3. Fee-on-transfer token compatibility
4. Integer arithmetic (fee calculations)
5. Gas griefing via whitehat revert
