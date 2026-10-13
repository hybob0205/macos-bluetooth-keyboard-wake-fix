# macOS Bluetooth Keyboard Wake Fix

A small macOS helper for Bluetooth LE keyboards that miss keystrokes after idle.
It requests a low-latency connection while running. Configurable device names;
currently verified with Acer OKW223 on macOS 27.0.1. This is a resident workaround,
not a firmware update or a permanent macOS patch.

用于缓解 **Mac 上蓝牙键盘闲置后，前几次按键无响应，甚至连续按多次仍无法输入** 的情况。思路来自 [KeyBoost](https://github.com/leonardofundora/KeyBoost)，以 Swift、AppKit 和 CoreBluetooth 实现一个小型助手。

名称和目标设备配置不限品牌，但有效性取决于设备与系统。**目前仅有 Acer OKW223 + macOS 27.0.1 的实际验证记录；不能据此保证所有键盘或系统版本都有效。**

## 问题记录与排查结果

本项目源自一次实际排查：

| 测试 | 观察结果 |
| --- | --- |
| 使用键盘的无线接收器 | 正常 |
| 蓝牙连接手机 | 正常 |
| 蓝牙连接 Mac，分别使用 BT1 / BT2 | 都出现闲置后的按键无响应 |
| 重连、重建配对、键盘关机后再开机 | 没有解决原始问题；BT2 重建配对也曾失败 |
| 英文 ABC 输入法，空白输入框，闲置后独立按 A 五次 | 原先一个 a 也没有 |
| 启动临时低延迟助手，再做相同闲置测试 | 五次按键输入五个 a |
| 长期运行助手并启用登录启动 | 用户确认恢复正常；日志持续出现 latency=0 |

这些结果指向 **Mac 与键盘之间的 BLE 连接参数和省电机制兼容问题**。接收器和手机正常说明键盘在其他连接方式下能工作，不能完全排除键盘固件与 Mac 的兼容缺陷。尚未定位到具体芯片、固件代码或某个确定的系统缺陷。

## 日志证据意味着什么

排查中观察到的原始参数和错误片段（已去除设备地址等个人信息）：

```text
connectionInterval:15ms
peripheralLatency:22
Failed to enter Connection Subrating Mode ... Status=1330
Rejecting following parameters: min=6, max=6, lat=0, ...
```

`peripheralLatency` 是外设被允许跳过的连接事件数量，**不是毫秒值**。在 15 ms 的连接间隔和 latency=22 的组合下，允许的空闲事件跨度可达：

```text
15 ms × (22 + 1) = 345 ms
```

这不代表每次按键固定延迟 345 ms，也不能单凭这个数字解释完全无响应；正常 BLE 外设通常可以提前参与连接事件。结合 Subrating 失败、参数拒绝和实际输入测试，证据支持连接省电策略的兼容问题，但不足以证明完整的故障链。

工具运行后，实际系统日志出现：

```text
current connection params interval 10ms-30ms ... latency=0 connectionInterval:30ms
```

这说明本次测试中连接切换到 30 ms 间隔、允许跳过 0 个连接事件。它是链路参数证据，**不是端到端输入延迟的测量值**。用户的闲置后五次按键测试才是本次效果验证。

## 解决方案原理

1. 用户先在 macOS 系统设置中连接键盘，并在助手里填写它的完整名称。
2. 助手通过私有接口 `retrieveConnectedPeripheralsWithServices:allowAll:` 获取系统已连接的 BLE 外设，只选名称完全匹配且仅有一台的设备。不扫描附近设备、不负责配对。
3. 助手为该设备持有一个 CoreBluetooth 客户端连接，并调用私有接口 `setDesiredConnectionLatency:forPeripheral:`，请求低延迟等级 `0`。
4. 连接期间每 5 秒重新提出请求。真正采用的连接间隔和 peripheral latency 由系统与外设协商，并非助手直接写入一个固定的 30 ms 参数。
5. 退出助手时取消本客户端连接、停止提出请求；之后由系统正常策略管理连接，恢复时机取决于系统。

工具减少允许跳过连接事件的空间，让链路更积极地参与连接事件，从而绕过本次闲置后的输入问题。**它没有修改键盘固件，也没有修补 macOS 蓝牙栈。** 若要根治，需要厂商或 Apple 修复实际的协商/省电兼容问题；本次未找到可核对匹配的 OKW223 官方固件升级包。

## 构建与测试

需要 Mac 和 Apple Command Line Tools（包含 Swift 编译器；若未安装，可运行 `xcode-select --install`）。构建目标最低版本为 macOS 13，但仅在 macOS 27.0.1 实测过私有接口与效果。

```sh
bash build.sh
open build/BluetoothKeyboardWakeFix.app --args --trial
```

构建脚本会检查 plist、进行本地 ad-hoc 签名验证，并运行设备名称选择自检。生成的 app 没有 Developer ID 签名或公证，不提供预编译下载包。

首次运行：

1. 允许蓝牙权限；若已拒绝，在系统设置 → 隐私与安全性 → 蓝牙中检查。
2. 输入系统设置中显示的完整键盘名称。比如 `OKW223-1, OKW223-2`，多个名称用英文逗号分隔，匹配区分大小写。名称相同的多台设备同时连接时，工具会等待而不选择。
3. 点击“保存并应用”。只指定你希望测试的蓝牙键盘，不要填写鼠标或其他外设名称。当前匹配按名称进行，不能验证设备身份或自动识别它是不是键盘。
4. 使用英文输入法的空白文本框，闲置到通常出现问题的时长，再独立按 A 五次，确认是否收到五个 a。

`--trial` 在 10 分钟后退出。界面显示“请求低延迟”只表示已发送请求，不表示协商成功或延迟已经实测改善。另可通过 macOS Console 查看 `bluetoothd` 的连接参数；本地状态日志不会记录协商后的参数。

持续运行时，先退出试用实例，再打开：

```sh
open build/BluetoothKeyboardWakeFix.app
```

打开已运行的 app 不一定会传入新参数，切换试用/长期模式前应先退出。关闭窗口或点击“停止并退出”会结束程序。

## 可选：登录时启动

**先通过手动试用确认效果，再退出试用实例。** 执行：

```sh
bash login.sh enable
```

脚本把 app 复制到 `~/Applications/BluetoothKeyboardWakeFix.app`，在当前用户的 `~/Library/LaunchAgents/` 生成启动配置并启动它。首次启动仍需要蓝牙权限和目标名称配置。`--background` 隐藏初始窗口；尚未配置名称时会显示窗口。重新打开已安装的 app 可显示状态和停止按钮。

不需要管理员权限。没有 `KeepAlive`，主动退出后不会立刻重启，下次登录时才再次启动。脚本发现已有同名安装会停止并提示，不覆盖正在运行的 app。

## 停止与卸载

禁用登录启动并停止它启动的实例：

```sh
bash login.sh disable
```

若另有手动打开的实例，也应在窗口中点击“停止并退出”。随后可把 `~/Applications/BluetoothKeyboardWakeFix.app` 和项目中的 `build/` 移到废纸篓。用户配置保存在 app 自己的偏好域 `local.bluetoothkeyboard.wakefix`；状态日志位于 `~/Library/Logs/BluetoothKeyboardWakeFix/status.log`，可自行删除。

## 对其他设置的影响和限制

- 工具只保存自己的目标名称配置；不改 `KeyRepeat`、`InitialKeyRepeat`、`ApplePressAndHoldEnabled` 或系统蓝牙偏好，不主动改其他设备的参数。
- 需要蓝牙权限；不申请辅助功能或输入监控权限，不读取、模拟或上传按键，没有网络通信。状态日志仅包含连接状态、目标名称和错误信息。
- 低延迟可能增加键盘耗电。私有 API 可能在系统更新后失效；运行前会检查选择器存在，但这不能保证接口语义永远兼容。
- 仅适用于可被上述 CoreBluetooth 接口获取的 BLE 设备；无法修复所有蓝牙问题、应用卡顿、输入法问题或键盘固件问题。

原始排查还出现过长按删除不能连删、字母长按重音菜单消失。这是另行检查的输入设置问题：重复率恢复后用户确认连删正常；显式启用长按字符菜单后，新开的 TextEdit 中观察到菜单。菜单原先为何消失没有定论，且已打开的应用可能需重启。**本项目不自动设置这些选项，避免改变用户的长按习惯。**

## 验证范围与许可

原始专用助手的低延迟请求、闲置输入效果和登录启动已实际验证。此公开版本沿用同一请求机制，并增加名称配置：发布前验证了构建、签名、设备选择逻辑和启动配置生成（包括含空格的路径）；未覆盖其他型号键盘，也未重新进行通用版本的完整蓝牙闲置实测。

感谢 [Leonardo Fundora / KeyBoost](https://github.com/leonardofundora/KeyBoost) 提供连接延迟请求的思路。此项目是独立的简化助手，不是 KeyBoost 官方版本。源代码以 [MIT License](LICENSE) 发布，保留上游署名。公开仓库不包含原始设备地址、外围设备 UUID、机器专用启动路径、运行日志或已签名二进制。
