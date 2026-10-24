# 免责声明 / Disclaimer

本工具（「网络检查与修复工具」，以下简称"本工具"）按**现状（AS IS）**提供，不附带任何明示或默示的担保。

## 1. 需要管理员权限

本工具需要以**管理员身份**运行，并会修改系统网络配置，包括但不限于：网卡启用/重启、IP/DHCP 重置、DNS 设置与服务、HOSTS 文件、Winsock/LSP、系统代理、环境变量。

## 2. 使用风险自担

- 使用前请自行评估风险，并确保已对重要配置做好备份。
- 本工具在修复前会自动备份到 `backup/<时间戳>/`，但**不保证**备份完整可还原所有场景（例如 `netsh winsock reset` 移除的第三方 LSP 无法完全还原）。
- 因使用本工具导致的网络中断、配置丢失、系统异常、业务停滞或其他任何直接或间接损失，作者与贡献者**不承担任何责任**。

## 3. 无担保

本工具不保证适用于任何特定用途，不保证无缺陷、不保证检查结果与修复动作对任意环境均正确。

## 4. 第三方软件

若你使用代理软件、VPN、安全软件等第三方程序，本工具的检查与修复可能与其配置相互影响，相关后果由使用者自行承担。

## 5. 责任限制

在适用法律允许的最大范围内，作者与贡献者不对任何索赔、损害或其他责任负责，无论是合同、侵权或其他原因引起。

## 6. 接受条款

下载、复制、安装或使用本工具，即视为你已阅读并接受本免责声明的全部内容。如不同意，请停止使用并删除本工具。

---

# Disclaimer (English)

This tool (the "Network Check & Repair Tool") is provided **"AS IS"**, without warranty of any kind, express or implied.

It requires **administrator privileges** and modifies system network settings (adapters, IP/DHCP, DNS, HOSTS, Winsock/LSP, proxy, environment variables). Use it at your own risk. The authors and contributors are **not liable** for any network outage, configuration loss, system failure, business interruption, or any other direct or indirect damages arising from the use of this tool.

By downloading, copying, installing, or using this tool, you acknowledge that you have read and accepted this disclaimer in full. If you do not agree, please stop using it and delete it.
