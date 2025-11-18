#!/bin/bash

# Chainstack RPC endpoint
RPC_URL="https://ethereum-mainnet.core.chainstack.com/8a29cb0f1c249f976eec5cf3cad3ae6d"

# Contract addresses
SPLITTER_03FD="0x03fd3d61423e6d46dcc3917862fbc57653dc3eb0"
SPLITTER_3234="0x323498d3fb02594ac3e0a11b2dea337893ecabbe"

# Common tokens to check (USDT, USDC, T, NU, KEEP)
declare -A TOKENS
TOKENS["USDT"]="0xdac17f958d2ee523a2206206994597c13d831ec7"
TOKENS["USDC"]="0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
TOKENS["T"]="0xcdf7028ceab81fa0c6971208e83fa7872994bee5"  # Threshold Network Token
TOKENS["NU"]="0x4fe83213d56308330ec302a8bd641f1d0113a4cc"   # NuCypher
TOKENS["KEEP"]="0x85eee30c52b0b379b046fb0f85f4f3dc3009afec" # Keep Network
TOKENS["WETH"]="0xc02aaa39b223fe8d0a5c4f27ead9083c756cc2c"
TOKENS["DAI"]="0x6b175474e89094c44da98b954eedeac495271d0f"

echo "=== Checking ERC20 Token Balances in Splitter Contracts ==="
echo ""

# Function to check token balance
check_token_balance() {
    local contract=$1
    local contract_name=$2
    local token=$3
    local token_name=$4

    # ERC20 balanceOf function signature: balanceOf(address) -> 0x70a08231
    # Encode the call: 0x70a08231 + padded address
    local padded_address=$(echo $contract | sed 's/0x/000000000000000000000000/')
    local data="0x70a08231${padded_address}"

    local result=$(curl -s -X POST $RPC_URL \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"$token\",\"data\":\"$data\"},\"latest\"],\"id\":1}")

    local balance_hex=$(echo $result | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

    if [ -n "$balance_hex" ] && [ "$balance_hex" != "0x" ]; then
        local balance_dec=$(printf "%d" "$balance_hex" 2>/dev/null)
        if [ "$balance_dec" -gt "0" ]; then
            echo "  $token_name: $balance_dec (raw units)"
        fi
    fi
}

echo "Checking Splitter_03fd ($SPLITTER_03FD)..."
for token_name in "${!TOKENS[@]}"; do
    check_token_balance "$SPLITTER_03FD" "Splitter_03fd" "${TOKENS[$token_name]}" "$token_name"
done
echo ""

echo "Checking Splitter_3234 ($SPLITTER_3234)..."
for token_name in "${!TOKENS[@]}"; do
    check_token_balance "$SPLITTER_3234" "Splitter_3234" "${TOKENS[$token_name]}" "$token_name"
done
echo ""

echo "=== Check Complete ==="
