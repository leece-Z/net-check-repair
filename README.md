# 网络检查与修复工具

一款 Windows 本机「网络检查 + 一键修复」小工具：双击 `.bat` 即用，图形界面极简，能检查并修复常见断网问题（网卡、IP/DHCP、DNS、HOSTS、LSP、代理、环境变量等），修复前自动备份，可一键回滚。

> 纯 PowerShell + WinForms 实现，零第三方依赖，仅需 Windows 自带组件。

## 功能特性

- **一键检查**：打开界面即自动执行一次全面检查，结果表格展示「检查项 / 状态 / 说明」，状态按颜色区分。
- **一键修复**：只对「异常」项执行修复，修复前仅确认一次；结束后输出「异常项 → 已修复 / 需重启」汇总。
- **自动备份**：每次修复前自动备份当前配置，可一键回滚。
- **准确判定**：区分「正常 / 异常 / 需重启 / 需人工处理 / 受断网影响」，避免把物理断网或正常代理误判为故障。
- **虚拟网卡排除**：判定只基于真实物理网卡，VirtualBox / VMware / Hyper-V 等虚拟网卡不参与。

## 检查项与修复动作

| 检查项 | 检查内容 | 修复动作 | 修复结果标注 |
| --- | --- | --- | --- |
| 网络硬件配置 | 物理网卡是否被禁用 / 未连接 | 启用被禁用网卡、重启未连接网卡 | 已修复 / 需人工处理 |
| 网络连接配置 | 物理网卡 IPv4 地址与默认网关 | `netsh int ip reset` | 需重启；物理断网时为「受断网影响」 |
| DHCP 服务 | Dhcp 服务状态与启动类型 | 设为自动并启动 | 已修复 |
| DNS 服务 | Dnscache 服务 + 域名解析测试 | 启动服务、清 DNS 缓存、重置为自动 DNS | 已修复；物理断网时为「受断网影响」 |
| HOSTS 文件 | 是否存在可疑映射 | 重置为标准内容 | 已修复 |
| LSP 协议 | 是否存在非系统 LSP 条目 | `netsh winsock reset` | 需重启 |
| IE 代理 | 代理后网络连通性 | 不自动改写代理配置 | 需人工处理 |
| 环境变量 | SystemRoot / TEMP / PATH 是否正常 | 仅报告，不自动修改 | 需人工处理 |

### IE 代理的判定规则

- 未使用代理：测试 `http://www.baidu.com`。
- 使用代理：测试 `http://www.baidu.com` + `https://www.google.com`（补充地址）。
- **任一项异常即判定为异常，并在说明中展示异常地址**；两项全部正常才判定正常。
- 使用代理本身不会被当作故障，也不会被自动关闭。

## 系统要求

- Windows 10 / Windows 11
- Windows PowerShell 5.1（系统自带）
- 管理员权限（`.bat` 会自动请求提权）

## 快速开始

1. 克隆或下载本仓库。
2. 双击 `网络修复工具.bat`。
3. 在 UAC 提示中选择「是」，授予管理员权限。
4. 程序打开后自动执行一次全面检查。
5. 点击「一键修复」，确认一次后开始修复。
6. 查看修复汇总；如需还原，点击「回滚」。

```powershell
git clone https://github.com/<your-account>/net_check_repair.git
```

## 备份与回滚

每次点击「一键修复」时，会先在本工具目录下生成备份：

```text
backup/<yyyyMMdd_HHmmss>/
├── hosts.bak        当前 HOSTS 文件副本
├── proxy.reg        当前 IE 代理注册表导出
├── netsh_dump.txt   当前网络配置全量导出（netsh dump）
└── env.json         当前关键环境变量快照
```

点击「回滚」会还原到**最近一次**备份。注意：`netsh winsock reset` 移除的第三方 LSP 无法完全还原，部分配置需重启后生效。

## 目录结构

```text
net_check_repair/
├── .gitignore
├── LICENSE
├── README.md
├── DISCLAIMER.md
├── net_check.ps1          主程序（WinForms GUI + 检查/修复/备份回滚）
└── 网络修复工具.bat        双击入口（自提权后启动 main 脚本）
```

> `backup/` 为运行时生成，已被 `.gitignore` 排除。

## 注意事项

- 本工具会修改系统网络配置，请先阅读 [DISCLAIMER.md](DISCLAIMER.md)。
- 物理断网（网线未插、路由器掉线）无法由软件修复，工具会标注「需人工处理」。
- `netsh int ip reset`、`netsh winsock reset` 需要重启计算机后才完全生效。
- 环境变量异常只提示不自动修改，避免误伤系统配置。

## 免责声明

本工具按「现状」提供，需管理员权限并会修改网络配置。使用风险自担，作者不承担任何责任。详见 [DISCLAIMER.md](DISCLAIMER.md)。

## License

[MIT](LICENSE)
