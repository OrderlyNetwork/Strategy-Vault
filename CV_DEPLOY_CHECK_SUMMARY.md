# Community Vault 部署检查总结

## 1. 发现的问题

### 🔴 严重错误

#### 问题 1: 错误的地址用于计算 spId (已修复)
**位置**: `tasks/deploy.js:183`

**原代码**:
```javascript
const spId = getStrategyProviderId(cvDeployment[cv].address, cvDeployment[cv].sp, cvDeployment[cv].broker);
```

**问题**: 使用了 `cvDeployment[cv].address`（旧地址或空地址），而不是新部署的 `CommunityVaultAddr`。

**修复后**:
```javascript
const spId = getStrategyProviderId(CommunityVaultAddr, cvDeployment[cv].sp, cvDeployment[cv].broker);
```

**影响**: 这会导致在 `community.json` 中保存错误的 `spId`，后续配置和检查都会失败。

---

### 🟡 配置缺失问题

#### 问题 2: community.json 配置不完整
**位置**: `deployment/community.json`

**缺失字段**:
- `dev` 和 `qa` 配置中缺少:
  - `broker` (必需)
  - `minDepositForLp` (必需)
  - `minDepositForSp` (必需)

**示例** (参考 `woo` 或 `kronos` 配置):
```json
{
  "dev": {
    "sp": "0x4e9FeE6661422BBD72e8133121E9387bf238C2e1",
    "nonce": 1,
    "vaultId": "",
    "address": "",
    "broker": "0x95d85ced8adb371760e4b6437896a075632fbd6cefe699f8125a8bc1d9b19e5b",
    "minDepositForLp": 0,
    "minDepositForSp": 0
  }
}
```

**影响**: 缺少这些字段会导致部署失败。

---

### 🟢 新增功能

#### 功能 1: 部署前配置验证 (已添加)
**位置**: `tasks/deploy.js:142-148`

添加了部署前的必填字段验证：
```javascript
const requiredFields = ['sp', 'nonce', 'broker', 'minDepositForLp', 'minDepositForSp'];
for (const field of requiredFields) {
    if (cvDeployment[cv][field] === undefined) {
        throw new Error(`Missing required field '${field}' in community.json for ${cv}`);
    }
}
```

**好处**: 在部署开始前就能发现配置问题，避免浪费 gas。

---

## 2. 新增的检查任务

### Task: `check-cv`

**用法**:
```bash
npx hardhat check-cv --env <env> --cv <cv_name> --network <network>
```

**示例**:
```bash
npx hardhat check-cv --env qa --cv woo --network sepolia
```

**检查项目**:
1. ✅ 合约代码存在性
2. ✅ dexVault 配置
3. ✅ isAllowedStrategy 配置
4. ✅ crossChainManager 配置
5. ✅ ledgerEid 配置
6. ✅ isAllowedStrategyProvider 配置 (使用 CV 的 SP)
7. ✅ isAllowedToken 配置 (USDC)
8. ✅ isAllowedBroker 配置 (使用 CV 的 broker)
9. ✅ minDepositForLp 配置
10. ✅ minDepositForSp 配置
11. ✅ vaultId 计算正确性
12. ✅ spId 计算正确性

---

## 3. 部署流程优化建议

### 推荐的部署流程:

1. **准备配置**
   - 确保 `community.json` 中有完整配置
   - 确保 `deployment.json` 中 `env` 的配置正确

2. **部署**
   ```bash
   npx hardhat deploy-cv --env <env> --cv <cv_name> --network <network>
   ```

3. **验证部署**
   ```bash
   npx hardhat check-cv --env <env> --cv <cv_name> --network <network>
   ```

4. **检查输出**
   - 确认所有检查项都通过 ✅
   - 检查 `community.json` 中的 `address`、`vaultId` 和 `spId` 已正确更新

---

## 4. 其他建议

### 代码优化建议:

1. **添加日志级别**
   - 考虑添加 `--verbose` 选项用于详细日志
   - 添加 `--quiet` 选项用于简化输出

2. **错误处理改进**
   - 在部署失败时提供更详细的错误信息
   - 添加重试机制（特别是验证步骤）

3. **配置验证增强**
   - 验证 broker hash 格式（应该是 bytes32）
   - 验证 sp 地址格式
   - 验证 nonce 是否已被使用（检查 salt 是否冲突）

4. **文档完善**
   - 在 `community.json` 中添加字段说明注释
   - 创建部署手册文档

---

## 5. 测试建议

在正式部署前，建议在测试网（如 sepolia）上进行完整测试：

```bash
# 1. 部署 CV
npx hardhat deploy-cv --env dev --cv test_vault --network sepolia

# 2. 检查配置
npx hardhat check-cv --env dev --cv test_vault --network sepolia

# 3. 测试核心功能
# - LP 存款
# - SP 存款
# - 提款请求
# - Claim 功能
```

---

## 6. 注意事项

⚠️ **重要提醒**:
- 部署使用 CREATE2，salt 基于 `sp` 和 `nonce` 计算
- 相同的 salt 无法重复部署
- 修改 `nonce` 可以重新部署
- `vaultId` 和 `spId` 是基于部署地址计算的，必须在部署后更新
- 部署后需要进行相应的配置（设置 broker、SP、token 等）

---

## 7. 相关文件

- 部署脚本: `tasks/deploy.js`
- 检查脚本: `tasks/check.js`
- CV 配置: `deployment/community.json`
- 部署配置: `deployment/deployment.json`
- 合约代码: `contracts/Vault/ProtocolVault.sol`

