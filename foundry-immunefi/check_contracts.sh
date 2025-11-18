#!/bin/bash

# Chainstack RPC endpoint
RPC_URL="https://ethereum-mainnet.core.chainstack.com/8a29cb0f1c249f976eec5cf3cad3ae6d"

# Contract addresses
SPLITTER_03FD="0x03fd3d61423e6d46dcc3917862fbc57653dc3eb0"
SPLITTER_3234="0x323498d3fb02594ac3e0a11b2dea337893ecabbe"

echo "=== Checking Threshold Network Splitter Contracts on Mainnet ==="
echo ""

# Function to get ETH balance
get_balance() {
    local address=$1
    local name=$2

    echo "Checking $name ($address)..."

    # Get balance using eth_getBalance
    local result=$(curl -s -X POST $RPC_URL \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$address\",\"latest\"],\"id\":1}")

    local balance_hex=$(echo $result | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

    if [ -n "$balance_hex" ]; then
        # Convert hex to decimal using printf
        local balance_wei=$(printf "%d" "$balance_hex" 2>/dev/null)
        if [ -n "$balance_wei" ]; then
            # Convert wei to ETH (divide by 10^18)
            local balance_eth=$(echo "scale=18; $balance_wei / 1000000000000000000" | bc -l 2>/dev/null || echo "0")
            echo "  Balance: $balance_wei wei ($balance_eth ETH)"

            if [ "$balance_wei" -gt "0" ]; then
                echo "  ⚠️  WARNING: Contract has stuck ETH! Vulnerable to theft via insufficient msg.value attack!"
            fi
        else
            echo "  Balance: $balance_hex (hex)"
        fi
    else
        echo "  Error getting balance: $result"
    fi

    # Get contract code to verify it exists
    local code_result=$(curl -s -X POST $RPC_URL \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getCode\",\"params\":[\"$address\",\"latest\"],\"id\":1}")

    local code=$(echo $code_result | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

    if [ "$code" = "0x" ]; then
        echo "  Status: No contract deployed at this address"
    else
        local code_length=${#code}
        echo "  Status: Contract exists (bytecode length: $code_length chars)"
    fi

    echo ""
}

# Check both contracts
get_balance "$SPLITTER_03FD" "Splitter_03fd"
get_balance "$SPLITTER_3234" "Splitter_3234"

echo "=== Analysis Complete ==="
echo ""
echo "KEY FINDINGS:"
echo "1. If either contract has ETH balance > 0, funds are at risk"
echo "2. Splitter_3234 has NO withdrawal function - any stuck funds are permanent"
echo "3. Splitter_03fd has withdrawal function - owner can withdraw, but time window vulnerability exists"
echo ""
echo "VULNERABILITY: Both contracts lack msg.value validation in _payWhitehatNative()"
echo "IMPACT: Attackers can pay insufficient msg.value and steal stuck ETH from contract"
echo ""
