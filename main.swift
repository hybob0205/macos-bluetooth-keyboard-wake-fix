import AppKit
import CoreBluetooth

// Inspired by KeyBoost: https://github.com/leonardofundora/KeyBoost (MIT).
// Private API: runtime guards cannot guarantee compatibility with future macOS.
@objc private protocol CentralLatencyAPI {
    @objc(retrieveConnectedPeripheralsWithServices:allowAll:)
    func connectedPeripherals(_ services: [CBUUID], allowAll: Bool) -> [CBPeripheral]
    @objc(setDesiredConnectionLatency:forPeripheral:)
    func requestLatency(_ latency: Int, peripheral: CBPeripheral)
}

func parseNames(_ text: String) -> Set<String> {
    Set(text.components(separatedBy: ",").map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty })
}

func matchingDeviceIndices(_ deviceNames: [String?], targets: Set<String>) -> [Int] {
    deviceNames.indices.filter { targets.contains(deviceNames[$0] ?? "") }
}

final class KeyboardHelper: NSObject, NSApplicationDelegate, CBCentralManagerDelegate {
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var clientConnected = false
    private var window: NSWindow!
    private var names = Set(UserDefaults.standard.stringArray(forKey: "TargetNames") ?? [])
    private let temporary = CommandLine.arguments.contains("--trial")
    private let background = CommandLine.arguments.contains("--background")
    private let status = NSTextField(wrappingLabelWithString: "准备蓝牙连接…")
    private let nameField = NSTextField()
    private let discoverSelector = NSSelectorFromString("retrieveConnectedPeripheralsWithServices:allowAll:")
    private let latencySelector = NSSelectorFromString("setDesiredConnectionLatency:forPeripheral:")
    private let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/BluetoothKeyboardWakeFix/status.log")

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = temporary ? "蓝牙键盘唤醒助手（10 分钟测试）" : "蓝牙键盘唤醒助手"
        window.isReleasedWhenClosed = false
        let label = NSTextField(labelWithString: "目标键盘完整名称（多个名称用英文逗号分隔）")
        label.frame = NSRect(x: 24, y: 260, width: 472, height: 20)
        window.contentView?.addSubview(label)
        nameField.stringValue = names.sorted().joined(separator: ", ")
        nameField.placeholderString = "例如：OKW223-1, OKW223-2"
        nameField.frame = NSRect(x: 24, y: 225, width: 350, height: 26)
        window.contentView?.addSubview(nameField)
        let save = NSButton(title: "保存并应用", target: self, action: #selector(saveNames))
        save.frame = NSRect(x: 380, y: 223, width: 116, height: 30)
        window.contentView?.addSubview(save)
        status.frame = NSRect(x: 24, y: 112, width: 472, height: 98)
        window.contentView?.addSubview(status)
        let note = NSTextField(wrappingLabelWithString: "仅请求一台名称匹配且系统已连接的设备。\n可能增加耗电；退出后停止请求。状态不代表实测延迟。")
        note.frame = NSRect(x: 24, y: 58, width: 472, height: 44)
        window.contentView?.addSubview(note)
        let stop = NSButton(title: temporary ? "结束测试" : "停止并退出", target: self, action: #selector(finish))
        stop.frame = NSRect(x: 195, y: 16, width: 130, height: 32)
        window.contentView?.addSubview(stop)
        window.center()
        if !background || names.isEmpty { showWindow() }
        central = CBCentralManager(delegate: self, queue: .main)
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
        if temporary {
            Timer.scheduledTimer(withTimeInterval: 600, repeats: false) { [weak self] _ in self?.finish() }
        }
    }

    @objc private func saveNames() {
        names = parseNames(nameField.stringValue)
        UserDefaults.standard.set(names.sorted(), forKey: "TargetNames")
        nameField.stringValue = names.sorted().joined(separator: ", ")
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        clientConnected = false
        refresh()
    }

    private func show(_ message: String) {
        guard status.stringValue != message else { return }
        status.stringValue = message
        let line = "\(Date().ISO8601Format()) \(message.replacingOccurrences(of: "\n", with: " "))\n"
        print(line, terminator: "")
        do {
            try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: logURL.path) {
                guard FileManager.default.createFile(atPath: logURL.path, contents: nil) else { return }
            }
            let file = try FileHandle(forWritingTo: logURL)
            defer { try? file.close() }
            try file.seekToEnd()
            try file.write(contentsOf: Data(line.utf8))
        } catch { print("Unable to save diagnostic status: \(error)") }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            peripheral = nil
            clientConnected = false
            show("等待蓝牙就绪或蓝牙权限。请检查系统设置中的蓝牙权限。")
            return
        }
        refresh()
    }

    private func refresh() {
        guard central.state == .poweredOn else { return }
        guard !names.isEmpty else {
            show("请填写系统设置中显示的键盘完整名称，然后保存。")
            return
        }
        guard central.responds(to: discoverSelector), central.responds(to: latencySelector) else {
            show("当前系统不支持所需私有接口，未请求连接。请退出工具。")
            return
        }
        let api = unsafeBitCast(central!, to: CentralLatencyAPI.self)
        if let peripheral {
            if clientConnected && peripheral.state == .connected {
                api.requestLatency(0, peripheral: peripheral)
            }
            return
        }
        let connected = api.connectedPeripherals([], allowAll: true)
        let matches = matchingDeviceIndices(connected.map { $0.name }, targets: names)
        guard matches.count == 1 else {
            show(matches.isEmpty ? "等待名称匹配的键盘。请先在系统设置中连接它。"
                 : "有多台匹配设备；请缩小名称范围或断开多余设备。")
            return
        }
        let target = connected[matches[0]]
        peripheral = target
        show("正在为 \(target.name ?? "目标键盘") 建立客户端连接…")
        central.connect(target, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard self.peripheral === peripheral else { return }
        clientConnected = true
        refresh()
        show("正在为 \(peripheral.name ?? "目标键盘") 请求低延迟连接。\n仅在运行期间生效，请通过闲置后的输入测试验证。")
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral === peripheral else { return }
        self.peripheral = nil
        clientConnected = false
        show("客户端连接失败：\(error?.localizedDescription ?? "未知原因")。")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral === peripheral else { return }
        self.peripheral = nil
        clientConnected = false
        show("键盘连接已断开，等待 Mac 恢复连接。")
    }

    @objc private func finish() { NSApplication.shared.terminate(nil) }
    private func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        show("工具已退出，停止低延迟请求。")
    }
}

if CommandLine.arguments.contains("--self-test") {
    let targets = parseNames(" OKW223-1, , OKW223-2,OKW223-1 \n")
    precondition(targets == Set(["OKW223-1", "OKW223-2"]))
    precondition(parseNames(" , \n").isEmpty)
    precondition(matchingDeviceIndices([nil, "Mouse", "OKW223-1-extra", "okw223-1"], targets: targets).isEmpty)
    precondition(matchingDeviceIndices(["Mouse", "OKW223-2"], targets: targets) == [1])
    precondition(matchingDeviceIndices(["OKW223-1", "OKW223-1"], targets: targets).count == 2)
    print("Device selection checks passed; no Bluetooth connection or preferences changed.")
} else {
    let app = NSApplication.shared
    let helper = KeyboardHelper()
    app.setActivationPolicy(.regular)
    app.delegate = helper
    app.run()
}
