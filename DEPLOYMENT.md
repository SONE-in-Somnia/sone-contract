# Sone Contract Deployment Guide

## 📋 Overview

Hướng dẫn triển khai smart contract Sone game trên các mạng blockchain khác nhau.

## 🛠️ Prerequisites

1. **Node.js** (v16+ recommended)
2. **Hardhat** đã được cài đặt
3. **Private key** hoặc **mnemonic** cho việc deploy
4. **Sufficient balance** trong wallet để trả gas fees

## 📁 Available Scripts

### 1. `scripts/deploy.js` - Development/Testing

- Dành cho local testing và development
- Sử dụng tham số phù hợp cho việc test
- Hỗ trợ Hardhat network

### 2. `scripts/deploy-somnia.js` - Production

- Optimized cho Somnia mainnet
- Tham số production-ready
- Bao gồm gas estimation và safety checks

## 🚀 Deployment Instructions

### Local Development (Hardhat Network)

```bash
# Deploy trên Hardhat network để test
npx hardhat run scripts/deploy.js --network hardhat
```

### Somnia Mainnet

```bash
# Deploy trên Somnia mainnet (thực tế)
npx hardhat run scripts/deploy-somnia.js --network somnia
```

### Other Networks

Để deploy trên mạng khác, thêm network config vào `hardhat.config.js`:

```javascript
networks: {
  ethereum: {
    url: "https://eth-mainnet.alchemyapi.io/v2/YOUR-API-KEY",
    accounts: ["YOUR-PRIVATE-KEY"]
  },
  polygon: {
    url: "https://polygon-mainnet.alchemyapi.io/v2/YOUR-API-KEY",
    accounts: ["YOUR-PRIVATE-KEY"]
  }
}
```

Sau đó chạy:

```bash
npx hardhat run scripts/deploy.js --network ethereum
```

## ⚙️ Configuration Parameters

### Development Parameters

- **Round Duration**: 1 hour (3600 seconds)
- **Value Per Entry**: 0.01 ETH
- **Protocol Fee**: 5% (500 basis points)
- **Max Participants**: 100

### Production Parameters (Somnia)

- **Round Duration**: 24 hours (86400 seconds)
- **Value Per Entry**: 0.005 ETH
- **Protocol Fee**: 3% (300 basis points)
- **Max Participants**: 200

## 🔧 Post-Deployment Setup

Sau khi deploy thành công, bạn cần thực hiện:

### 1. Add Supported Tokens

```javascript
// Ví dụ: Add USDT support
await sone.addSupportedToken(
  "0xUSDT_ADDRESS", // token address
  6, // decimals
  ethers.parseUnits("1", 6), // min deposit (1 USDT)
  10000 // ratio (1:1)
);
```

### 2. Configure Native Token

```javascript
// Enable native token support
await sone.setNativeTokenConfig(
  true, // isSupported
  ethers.parseEther("0.001"), // minDeposit (0.001 ETH)
  10000 // ratio (1:1)
);
```

### 3. Security Configurations

```javascript
// Transfer ownership to multisig (recommended)
await sone.transferOwnership("MULTISIG_ADDRESS");

// Update protocol fee recipient
await sone.updateProtocolFeeRecipient("TREASURY_ADDRESS");

// Update keeper address
await sone.updateKeeper("KEEPER_BOT_ADDRESS");
```

## 🔍 Verification

### Contract Verification

- **Hardhat**: Tự động với `@nomicfoundation/hardhat-verify`
- **Manual**: Upload source code lên block explorer

### Function Testing

```javascript
// Test basic functions
const currentRound = await sone.currentRoundId();
const valuePerEntry = await sone.valuePerEntry();
const owner = await sone.owner();

console.log("Current Round:", currentRound);
console.log("Value Per Entry:", ethers.formatEther(valuePerEntry));
console.log("Owner:", owner);
```

## 💡 Tips & Best Practices

### Security

1. ✅ **Multisig Wallet**: Sử dụng multisig cho owner
2. ✅ **Audit**: Thực hiện security audit trước khi launch
3. ✅ **Test Network**: Test kỹ trên testnet trước
4. ✅ **Emergency Functions**: Hiểu rõ các emergency functions

### Gas Optimization

1. ✅ **Compiler Optimization**: Enabled trong hardhat.config.js
2. ✅ **Gas Estimation**: Luôn estimate gas trước khi deploy
3. ✅ **Batch Operations**: Group multiple calls để tiết kiệm gas

### Monitoring

1. ✅ **Events**: Monitor các events của contract
2. ✅ **Round Lifecycle**: Theo dõi quá trình round
3. ✅ **User Activity**: Monitor deposits và withdrawals

## 🆘 Troubleshooting

### Common Issues

**"Contract code size exceeds limit"**

```bash
# Solution: Enable optimization in hardhat.config.js
solidity: {
  version: "0.8.28",
  settings: {
    optimizer: {
      enabled: true,
      runs: 200
    }
  }
}
```

**"Insufficient funds for gas"**

```bash
# Solution: Đảm bảo có đủ ETH trong wallet
# Check balance và gas price trước khi deploy
```

**"Network not found"**

```bash
# Solution: Kiểm tra network config trong hardhat.config.js
# Đảm bảo RPC URL và accounts được config đúng
```

## 📞 Support

Nếu gặp vấn đề trong quá trình deployment:

1. Kiểm tra logs chi tiết
2. Verify network configuration
3. Ensure sufficient balance
4. Check contract parameters

## 📈 Monitoring After Deployment

### Essential Monitoring

- Round transitions
- User deposits
- Winner selections
- Protocol fee collections
- Emergency situations

### Recommended Tools

- Block explorer
- Custom monitoring dashboard
- Alert systems for critical events
