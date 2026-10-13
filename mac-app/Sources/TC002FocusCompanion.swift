import Foundation
import AppKit
import Network
import UniformTypeIdentifiers

private let keychainService = "tc002-focus-bridge"

struct StoredConfig: Codable {
    var deviceIP = ""
    var hostIP = ""
    var focusMinutes = "45"
    var restMinutes = "5"
    var repoPath = ""
    var customAudioName: String? = nil
}

enum RunnerError: LocalizedError {
    case failed(String)
    var errorDescription: String? { if case .failed(let message) = self { return message }; return nil }
}

enum EnvironmentError: LocalizedError {
    case missingTool(name: String, brewPackage: String)
    case nodeTooOld(version: String)

    var errorDescription: String? {
        switch self {
        case .missingTool(let name, _): return "未找到 \(name)"
        case .nodeTooOld(let version): return "需要 Node.js 24 或更高版本，当前为 \(version)"
        }
    }

    var brewPackages: [String] {
        switch self {
        case .missingTool(_, let package): return [package]
        case .nodeTooOld: return ["node"]
        }
    }
}

private final class ManagedADBServer {
    private let lock = NSLock()
    private var process: Process?
    private var port: UInt16?

    func ensureRunning(adb: String) throws -> UInt16 {
        lock.lock(); defer { lock.unlock() }
        guard adb != "/usr/bin/env" else { throw EnvironmentError.missingTool(name: "ADB", brewPackage: "android-platform-tools") }
        if let process, process.isRunning, let port, Self.isListening(port) { return port }
        if let process, process.isRunning { process.terminate() }
        process = nil; port = nil

        for _ in 0..<3 {
            let candidate = UInt16.random(in: 43000...53000)
            if Self.isListening(candidate) { continue }
            let server = Process()
            server.executableURL = URL(fileURLWithPath: adb)
            server.arguments = ["-L", "tcp:\(candidate)", "nodaemon", "server"]
            server.standardInput = FileHandle.nullDevice
            server.standardOutput = FileHandle.nullDevice
            server.standardError = FileHandle.nullDevice
            try server.run()
            for _ in 0..<20 {
                if !server.isRunning { break }
                if Self.isListening(candidate), server.isRunning {
                    process = server; port = candidate
                    return candidate
                }
                Thread.sleep(forTimeInterval: 0.15)
            }
            if server.isRunning { server.terminate() }
        }
        throw RunnerError.failed("无法启动 GUI 专用 ADB 服务。请退出 App 后重试，并检查 macOS“本地网络”权限。")
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        if let process, process.isRunning { process.terminate() }
        process = nil; port = nil
    }

    private static func isListening(_ port: UInt16) -> Bool {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return false }
        let connection = NWConnection(host: "127.0.0.1", port: endpointPort, using: .tcp)
        let completed = DispatchSemaphore(value: 0)
        var ready = false
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready: ready = true; completed.signal()
            case .failed: completed.signal()
            default: break
            }
        }
        connection.start(queue: DispatchQueue(label: "tc002-focus-adb-server-probe"))
        let finished = completed.wait(timeout: .now() + 0.2) == .success
        connection.cancel()
        return finished && ready
    }
}

final class AppModel {
    private static let adbServer = ManagedADBServer()
    var deviceIP = ""
    var hostIP = ""
    var focusMinutes = "45"
    var restMinutes = "5"
    var repoPath = ""
    var customAudioName = ""
    var appID = ""
    var appSecret = ""
    var status = "等待配置"
    var logText = ""
    var isBusy = false
    var isAuthorized = false
    var isLarkVerified = false
    var isEnvironmentReady = false
    var isDeviceReachable = false
    var areServicesInstalled = false
    var areServicesRunning = false
    var onChange: (() -> Void)?
    var onEnvironmentInstallOffer: (([String], String) -> Void)?
    private var oauthProcess: Process?
    private var restartOAuthWhenStopped = false

    private var customAudioURL: URL { supportDirectory().appendingPathComponent("focus_done.mp3") }
    var hasCustomAudio: Bool { FileManager.default.fileExists(atPath: customAudioURL.path) }
    var customAudioStatus: String { hasCustomAudio ? "已选择：\(customAudioName.isEmpty ? "自定义提示音" : customAudioName)" : "当前使用默认提示音" }

    var isOAuthRunning: Bool { oauthProcess?.isRunning == true }
    var isReadyToStart: Bool {
        isEnvironmentReady && isLarkVerified && isDeviceReachable
            && Self.adbTarget(deviceIP) != nil
            && !hostIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func load() {
        let defaults = FileManager.default.currentDirectoryPath
        let configURL = supportDirectory().appendingPathComponent("config.json")
        if let data = try? Data(contentsOf: configURL), let config = try? JSONDecoder().decode(StoredConfig.self, from: data) {
            deviceIP = config.deviceIP; hostIP = config.hostIP; focusMinutes = config.focusMinutes; restMinutes = config.restMinutes; repoPath = config.repoPath; customAudioName = config.customAudioName ?? ""
        }
        if !hasCustomAudio { customAudioName = "" }
        if repoPath.isEmpty || !FileManager.default.fileExists(atPath: repoPath) {
            let bundled = Bundle.main.resourceURL?.appendingPathComponent("tc002-repo").path ?? ""
            repoPath = FileManager.default.fileExists(atPath: bundled + "/companion/install-macos.sh")
                ? bundled
                : (FileManager.default.fileExists(atPath: defaults + "/companion/install-macos.sh") ? defaults : "")
        }
        if hostIP.isEmpty { hostIP = detectHostIP() }
        if appID.isEmpty { appID = (try? Self.run("/usr/bin/security", args: ["find-generic-password", "-s", keychainService, "-a", "app_id", "-w"]))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        refreshAuthorizationState()
        let serviceLabels = ["com.tc002.focus-emqx", "com.tc002.focus-bridge", "com.tc002.focus-mqtt"]
        let launchAgents = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        areServicesInstalled = serviceLabels.allSatisfy {
            FileManager.default.fileExists(atPath: launchAgents.appendingPathComponent("\($0).plist").path)
        }
        areServicesRunning = serviceLabels.allSatisfy {
            (try? Self.run("/bin/launchctl", args: ["list", $0])) != nil
        }
        status = isAuthorized ? "Lark 凭据已保存；启动前会再验证权限" : "请从第 1 步开始配置"
        notify()
    }

    func autoValidateSavedConfiguration() {
        guard !isBusy else { return }
        let repo = repoPath
        let device = deviceIP.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = hostIP.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldCheckDevice = !device.isEmpty && !host.isEmpty
        let storedAppID = keychainValue(account: "app_id") ?? ""
        let shouldCheckLark = isAuthorized && !appID.isEmpty && storedAppID == appID
        isBusy = true
        status = "正在自动检查已保存的配置…"
        appendLog("启动检查：正在验证运行环境。")
        notify()

        DispatchQueue.global(qos: .userInitiated).async {
            var environmentError: Error?
            var environmentReady = false
            var deviceReachable = false
            var larkVerified = false
            var messages: [String] = []

            do {
                try Self.preflight(repo: repo)
                environmentReady = true
                messages.append("✓ 运行环境检查通过")
            } catch {
                environmentError = error
                messages.append("运行环境未通过：\(Self.friendlyError(error.localizedDescription))")
            }

            if shouldCheckDevice {
                if let target = Self.adbTarget(device) {
                    do {
                        _ = try Self.connectDevice(target)
                        deviceReachable = true
                        messages.append("✓ TC002 自动连接检查通过")
                    } catch {
                        messages.append("TC002 自动检查未通过：\(Self.friendlyError(error.localizedDescription))")
                    }
                } else {
                    messages.append(Self.invalidDeviceAddress)
                }
            }

            if shouldCheckLark {
                do {
                    let node = Self.nodePath()
                    let args = node == "/usr/bin/env" ? ["node", repo + "/bridge/setup-system-status.mjs"] : [repo + "/bridge/setup-system-status.mjs"]
                    let output = try Self.run(node, args: args, cwd: repo)
                    larkVerified = true
                    messages.append(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "✓ Lark 自动验证通过" : output.trimmingCharacters(in: .whitespacesAndNewlines))
                } catch {
                    messages.append("Lark 自动验证未通过：\(error.localizedDescription)")
                }
            }

            self.updateOnMain {
                self.isEnvironmentReady = environmentReady
                if shouldCheckDevice { self.isDeviceReachable = deviceReachable }
                if shouldCheckLark { self.isLarkVerified = larkVerified }
                self.isBusy = false
                messages.forEach { self.appendLog($0) }
                if self.isReadyToStart {
                    self.status = "自动检查通过，可以直接点击“启动专注时钟”"
                } else if environmentReady {
                    self.status = "自动检查完成；请继续填写或验证尚未就绪的项目"
                } else {
                    self.status = "运行环境检查未通过，请查看日志"
                }
                self.notify()
                if let issue = environmentError as? EnvironmentError {
                    self.onEnvironmentInstallOffer?(issue.brewPackages, Self.friendlyError(issue.localizedDescription))
                }
            }
        }
    }

    var readinessSummary: String {
        let environment = isEnvironmentReady ? "✓ 运行环境就绪" : "○ 待检查运行环境"
        let lark = isLarkVerified ? "✓ Lark 权限与系统状态正常" : (isAuthorized ? "◐ Lark 凭据已保存，待验证" : "○ 待授权 Lark")
        let device = isDeviceReachable ? "✓ TC002 可连接" : "○ 待测试 TC002 连接"
        let services = areServicesRunning ? "✓ 电脑助手正在运行" : (isReadyToStart ? "✓ 配置已验证，可以启动" : (areServicesInstalled ? "○ 电脑助手已停止" : "○ 电脑助手将在首次启动时安装"))
        return [environment, lark, device, services].joined(separator: "\n")
    }

    func detectHost() {
        hostIP = detectHostIP()
        if hostIP.isEmpty {
            status = "未自动识别到局域网 IPv4，请手动填写"
        } else {
            status = "已自动识别电脑地址：\(hostIP)"
            appendLog(status)
        }
        notify()
    }

    func checkEnvironment() {
        guard !isBusy else { return }
        isBusy = true; status = "正在检查 Node.js、ADB、EMQX 和运行包…"; notify()
        let repo = repoPath
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try Self.preflight(repo: repo)
                self.updateOnMain { self.isEnvironmentReady = true; self.isBusy = false; self.status = "运行环境检查通过"; self.appendLog("环境检查：Node.js、ADB、EMQX 和 TC002 运行包均正常。"); self.notify() }
            } catch {
                self.updateOnMain {
                    self.isEnvironmentReady = false; self.isBusy = false
                    let message = Self.friendlyError(error.localizedDescription)
                    self.status = "环境检查未通过：\(error.localizedDescription)"
                    self.appendLog(message); self.notify()
                    if let issue = error as? EnvironmentError { self.onEnvironmentInstallOffer?(issue.brewPackages, message) }
                }
            }
        }
    }

    func installEnvironment(packages: [String]) {
        guard !isBusy else { return }
        guard let brew = Self.resolvedExecutable("brew", preferred: ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]) else {
            status = "未找到 Homebrew，无法自动安装"
            appendLog("请先从 https://brew.sh 安装 Homebrew，再重新检查运行环境。")
            notify(); return
        }
        let uniquePackages = Array(Set(packages)).sorted()
        guard !uniquePackages.isEmpty else { return }
        isBusy = true; status = "正在安装：\(uniquePackages.joined(separator: "、"))…"; notify()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                for package in uniquePackages {
                    let args = package == "android-platform-tools" ? ["install", "--cask", package] : ["install", package]
                    let output = try Self.run(brew, args: args)
                    self.updateOnMain { self.appendLog(output); self.notify() }
                }
                try Self.preflight(repo: self.repoPath)
                self.updateOnMain { self.isEnvironmentReady = true; self.isBusy = false; self.status = "安装完成，运行环境检查通过"; self.appendLog("缺少的组件已经安装并验证通过。"); self.notify() }
            } catch {
                self.updateOnMain { self.isEnvironmentReady = false; self.isBusy = false; self.status = "自动安装未完成"; self.appendLog(Self.friendlyError(error.localizedDescription)); self.notify() }
            }
        }
    }

    func checkDevice() {
        let value = deviceIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { status = "请先填写时钟 IP"; notify(); return }
        guard let target = Self.adbTarget(value) else { status = Self.invalidDeviceAddress; notify(); return }
        guard !isBusy else { return }
        isBusy = true; status = "正在测试 TC002 连接…"; notify()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try Self.connectDevice(target)
                self.updateOnMain { self.isDeviceReachable = true; self.isBusy = false; self.status = "TC002 连接正常"; self.appendLog("时钟连接检查通过：\(target)"); self.notify() }
            } catch {
                self.updateOnMain { self.isDeviceReachable = false; self.isBusy = false; self.status = "TC002 连接失败"; self.appendLog(Self.friendlyError(error.localizedDescription)); self.notify() }
            }
        }
    }

    func verifyLark() {
        guard isAuthorized else { status = "请先完成 Lark 授权"; notify(); return }
        guard keychainValue(account: "app_id") == appID else { isLarkVerified = false; status = "App ID 已修改，请先重新授权 Lark"; notify(); return }
        guard !isBusy else { return }
        isBusy = true; status = "正在验证 Lark 权限和“专注中”状态…"; notify()
        let repo = repoPath
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let node = Self.nodePath()
                let args = node == "/usr/bin/env" ? ["node", repo + "/bridge/setup-system-status.mjs"] : [repo + "/bridge/setup-system-status.mjs"]
                let output = try Self.run(node, args: args, cwd: repo)
                self.updateOnMain { self.isLarkVerified = true; self.isBusy = false; self.status = "Lark 验证通过"; self.appendLog(output); self.notify() }
            } catch {
                self.updateOnMain { self.isLarkVerified = false; self.isBusy = false; self.status = "Lark 验证失败，请检查应用权限"; self.appendLog(error.localizedDescription); self.notify() }
            }
        }
    }

    func authorizeLark() {
        guard !appID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status = "请先填写 Lark App ID"; notify(); return }
        if let existing = oauthProcess {
            if existing.isRunning {
                restartOAuthWhenStopped = true
                isBusy = true
                status = "正在结束上一次授权并重新开始…"
                appendLog("收到重新授权请求：正在关闭上一次 OAuth 流程并释放本机 8788 端口。")
                notify()
                existing.terminate()
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2) {
                    if existing.isRunning { existing.interrupt() }
                }
                return
            }
            oauthProcess = nil
        }
        let storedAppID = keychainValue(account: "app_id") ?? ""
        let effectiveSecret = appSecret.isEmpty && storedAppID == appID ? (keychainValue(account: "app_secret") ?? "") : appSecret
        guard effectiveSecret.count >= 8 else { status = "请填写与当前 App ID 匹配的 App Secret"; notify(); return }
        guard FileManager.default.fileExists(atPath: repoPath + "/bridge/oauth.mjs") else { status = "项目目录无效，找不到 bridge/oauth.mjs"; notify(); return }
        isBusy = true; status = "正在打开 Lark 授权页面…"; appendLog("App ID 和 App Secret 只写入 macOS 钥匙串，不写入项目文件。"); notify()
        let appID = self.appID; let appSecret = effectiveSecret
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try Self.run("/usr/bin/security", args: ["add-generic-password", "-U", "-s", keychainService, "-a", "app_id", "-w", appID])
                _ = try Self.run("/usr/bin/security", args: ["add-generic-password", "-U", "-s", keychainService, "-a", "app_secret", "-w", appSecret])
                self.startOAuthProcess()
            } catch { self.updateOnMain { self.isBusy = false; self.status = "写入钥匙串失败：\(error.localizedDescription)"; self.notify() } }
        }
    }

    func startFocus() {
        guard let focus = Int(focusMinutes), let rest = Int(restMinutes), (1...240).contains(focus), (1...240).contains(rest) else { status = "专注和休息时长必须是 1–240 分钟的整数"; notify(); return }
        guard !deviceIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status = "请填写时钟 IP"; notify(); return }
        guard let device = Self.adbTarget(deviceIP) else { status = Self.invalidDeviceAddress; notify(); return }
        guard !hostIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status = "请填写电脑 IP"; notify(); return }
        guard isAuthorized else { status = "请先完成 Lark 授权"; notify(); return }
        guard keychainValue(account: "app_id") == appID else { status = "App ID 已修改，请先重新授权 Lark"; notify(); return }
        guard FileManager.default.fileExists(atPath: repoPath + "/companion/install-macos.sh") else { status = "项目目录无效，找不到 companion/install-macos.sh"; notify(); return }
        save(); isBusy = true; status = "正在检查时钟连接…"; appendLog("准备启动：专注 \(focus) 分钟，休息 \(rest) 分钟，设备 \(deviceIP)"); notify()
        let focusSeconds = focus * 60; let restSeconds = rest * 60; let repo = repoPath; let host = hostIP; let audio = hasCustomAudio ? customAudioURL.path : nil
        DispatchQueue.global(qos: .userInitiated).async {
            var deviceCheckStarted = false
            var deviceConnected = false
            do {
                self.updateOnMain { self.status = "1/5 检查运行环境…"; self.notify() }
                try Self.preflight(repo: repo)
                self.updateOnMain { self.isEnvironmentReady = true; self.status = "2/5 连接 TC002…"; self.notify() }
                deviceCheckStarted = true
                let adbPort = try Self.connectDevice(device)
                deviceConnected = true
                self.updateOnMain { self.isDeviceReachable = true; self.status = "3/5 验证 Lark 系统状态…"; self.notify() }
                let node = Self.nodePath()
                let statusArgs = node == "/usr/bin/env" ? ["node", repo + "/bridge/setup-system-status.mjs"] : [repo + "/bridge/setup-system-status.mjs"]
                let lark = try Self.run(node, args: statusArgs, cwd: repo)
                self.updateOnMain { self.isLarkVerified = true; self.appendLog(lark); self.status = "4/5 安装并启动电脑助手…"; self.notify() }
                let install = try Self.run("/bin/bash", args: [repo + "/companion/install-macos.sh", "--lan-host", host, "--mode", "real", "--focus-seconds", String(focusSeconds), "--rest-seconds", String(restSeconds), "--apply"], cwd: repo)
                self.updateOnMain { self.appendLog(install); self.areServicesInstalled = true; self.areServicesRunning = true; self.status = "5/5 配置并启动 TC002…"; self.notify() }
                let configure = try Self.run("/bin/bash", args: [repo + "/companion/configure-device.sh", "--adb-target", device, "--lan-host", host, "--focus-seconds", String(focusSeconds), "--rest-seconds", String(restSeconds)], cwd: repo, adbServerPort: adbPort)
                self.updateOnMain { self.appendLog(configure); self.isDeviceReachable = true; self.notify() }
                var launchArgs = [repo + "/companion/start-focus.sh", "--adb-target", device]
                if let audio { launchArgs += ["--audio", audio] }
                let launch = try Self.run("/bin/bash", args: launchArgs, cwd: repo, adbServerPort: adbPort)
                self.updateOnMain { self.appendLog(launch); self.isBusy = false; self.status = "专注时钟已启动；设备重启后恢复原生界面"; self.notify() }
            } catch {
                self.updateOnMain {
                    if (deviceCheckStarted && !deviceConnected) || error.localizedDescription.localizedCaseInsensitiveContains("adb") {
                        self.isDeviceReachable = false
                    }
                    self.isBusy = false; self.status = "启动未完成，请查看下方处理建议"
                    let message = Self.friendlyError(error.localizedDescription)
                    self.appendLog(message); self.notify()
                    if let issue = error as? EnvironmentError { self.onEnvironmentInstallOffer?(issue.brewPackages, message) }
                }
            }
        }
    }

    func stopComputerServices() {
        let labels = ["com.tc002.focus-emqx", "com.tc002.focus-bridge", "com.tc002.focus-mqtt"]; let home = FileManager.default.homeDirectoryForCurrentUser.path
        isBusy = true; notify()
        DispatchQueue.global(qos: .userInitiated).async {
            for label in labels { _ = try? Self.run("/bin/launchctl", args: ["unload", home + "/Library/LaunchAgents/\(label).plist"]) }
            self.updateOnMain { self.isBusy = false; self.areServicesRunning = false; self.status = "电脑端助手已停止；时钟仍保持当前临时界面，重启时钟即可回原生"; self.notify() }
        }
    }

    func rebootDevice() {
        let value = deviceIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { status = "请先填写时钟 IP"; notify(); return }
        guard let target = Self.adbTarget(value) else { status = Self.invalidDeviceAddress; notify(); return }
        isBusy = true; status = "正在重启时钟，重启后会回到原生界面…"; notify()
        DispatchQueue.global(qos: .userInitiated).async {
            do { let adb = Self.adbPath(); let port = try Self.connectDevice(target); let args = adb == "/usr/bin/env" ? ["adb", "-s", target, "reboot"] : ["-s", target, "reboot"]; _ = try Self.run(adb, args: args, adbServerPort: port); self.updateOnMain { self.isBusy = false; self.status = "已发出重启命令；设备启动后应恢复原生界面"; self.notify() } }
            catch { self.updateOnMain { self.isBusy = false; self.status = "重启失败：\(error.localizedDescription)"; self.notify() } }
        }
    }

    func stopADBServer() { Self.adbServer.stop() }

    func save() {
        let config = StoredConfig(deviceIP: deviceIP, hostIP: hostIP, focusMinutes: focusMinutes, restMinutes: restMinutes, repoPath: repoPath, customAudioName: hasCustomAudio ? customAudioName : nil)
        do { let directory = supportDirectory(); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); try JSONEncoder().encode(config).write(to: directory.appendingPathComponent("config.json"), options: .atomic) }
        catch { appendLog("保存配置失败：\(error.localizedDescription)") }
    }

    func chooseCustomAudio(_ source: URL) {
        guard !isBusy else { return }
        guard source.pathExtension.lowercased() == "mp3" else { status = "请选择 MP3 文件"; notify(); return }
        guard let values = try? source.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize, size > 0, size <= 20 * 1024 * 1024 else {
            status = "MP3 文件必须大于 0 且不超过 20 MB"; notify(); return
        }
        do {
            let directory = supportDirectory()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let temporary = directory.appendingPathComponent("focus_done.mp3.\(UUID().uuidString).tmp")
            try FileManager.default.copyItem(at: source, to: temporary)
            if FileManager.default.fileExists(atPath: customAudioURL.path) { try FileManager.default.removeItem(at: customAudioURL) }
            try FileManager.default.moveItem(at: temporary, to: customAudioURL)
            customAudioName = source.lastPathComponent
            save()
            status = "提示音已更换；下次启动时同步到 TC002"
            appendLog("已选择自定义提示音：\(customAudioName)（不写入项目或固件）")
            notify()
        } catch {
            status = "保存提示音失败：\(error.localizedDescription)"
            notify()
        }
    }

    func resetCustomAudio() {
        guard !isBusy else { return }
        do {
            if FileManager.default.fileExists(atPath: customAudioURL.path) { try FileManager.default.removeItem(at: customAudioURL) }
            customAudioName = ""
            save()
            status = "已恢复默认提示音；下次启动时同步到 TC002"
            appendLog("已恢复默认提示音")
            notify()
        } catch {
            status = "恢复默认提示音失败：\(error.localizedDescription)"
            notify()
        }
    }

    private func startOAuthProcess() {
        let process = Process(); let node = Self.nodePath(); process.executableURL = URL(fileURLWithPath: node); process.arguments = node == "/usr/bin/env" ? ["node", repoPath + "/bridge/oauth.mjs"] : [repoPath + "/bridge/oauth.mjs"]
        var environment = ProcessInfo.processInfo.environment; environment["TC002_OPEN_BROWSER"] = "1"; environment["PATH"] = Self.toolPath(); process.environment = environment; process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.updateOnMain { self?.appendLog(text.trimmingCharacters(in: .newlines)); self?.notify() }
        }
        process.terminationHandler = { [weak self] process in
            pipe.fileHandleForReading.readabilityHandler = nil
            let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
            let remainingText = String(data: remaining, encoding: .utf8)?.trimmingCharacters(in: .newlines) ?? ""
            self?.updateOnMain {
                self?.appendLog(remainingText)
                self?.oauthProcess = nil
                let shouldRestart = self?.restartOAuthWhenStopped == true
                self?.restartOAuthWhenStopped = false
                self?.refreshAuthorizationState()
                if shouldRestart {
                    self?.isBusy = true
                    self?.isLarkVerified = false
                    self?.status = "正在重新打开 Lark 授权页面…"
                    self?.appendLog("上一次 OAuth 流程已结束，正在启动新的授权。")
                    self?.notify()
                    self?.startOAuthProcess()
                } else if process.terminationStatus == 0 {
                    self?.isBusy = false
                    self?.isLarkVerified = true; self?.appSecret = ""; self?.status = "Lark 授权和系统状态验证成功"
                    self?.notify()
                } else {
                    self?.isBusy = false
                    self?.isLarkVerified = false; self?.status = "Lark 授权未完成，请查看下方日志"
                    self?.appendLog("授权流程已退出（状态码 \(process.terminationStatus)）。可以直接点击“重新授权 Lark”再次尝试。")
                    self?.notify()
                }
            }
        }
        oauthProcess = process
        do { try process.run() } catch { pipe.fileHandleForReading.readabilityHandler = nil; oauthProcess = nil; updateOnMain { self.isBusy = false; self.status = "无法启动授权流程：\(error.localizedDescription)"; self.notify() } }
    }

    private func supportDirectory() -> URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TC002FocusCompanion", isDirectory: true) }
    private func hasKeychainValue(account: String) -> Bool { (try? Self.run("/usr/bin/security", args: ["find-generic-password", "-s", keychainService, "-a", account, "-w"])) != nil }
    private func keychainValue(account: String) -> String? { try? Self.run("/usr/bin/security", args: ["find-generic-password", "-s", keychainService, "-a", account, "-w"]).trimmingCharacters(in: .whitespacesAndNewlines) }
    private func refreshAuthorizationState() { isAuthorized = ["app_id", "app_secret", "user_open_id", "system_status_id"].allSatisfy { hasKeychainValue(account: $0) } }
    private func detectHostIP() -> String {
        var interfaces = ["en0", "en1", "en2"]
        if let listed = try? Self.run("/sbin/ifconfig", args: ["-l"]) {
            interfaces.append(contentsOf: listed.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { !$0.hasPrefix("lo") && !$0.hasPrefix("utun") && !$0.hasPrefix("awdl") && !$0.hasPrefix("llw") })
        }
        var seen = Set<String>()
        for interface in interfaces where seen.insert(interface).inserted {
            if let value = try? Self.run("/usr/sbin/ipconfig", args: ["getifaddr", interface]), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return ""
    }
    private func appendLog(_ text: String) { guard !text.isEmpty else { return }; logText += (logText.isEmpty ? "" : "\n") + text }
    private func notify() { DispatchQueue.main.async { self.onChange?() } }
    private func updateOnMain(_ work: @escaping () -> Void) { DispatchQueue.main.async(execute: work) }

    private static func run(_ executable: String, args: [String] = [], cwd: String? = nil, adbServerPort: UInt16? = nil) throws -> String {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = args; if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        var environment = ProcessInfo.processInfo.environment; environment["PATH"] = toolPath(); if let adbServerPort { environment["ADB_SERVER_PORT"] = String(adbServerPort) }; process.environment = environment
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe; try process.run(); let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""; process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw RunnerError.failed(output.isEmpty ? "命令退出码：\(process.terminationStatus)" : output) }; return output
    }
    private static func preflight(repo: String) throws {
        let required = [
            "companion/install-macos.sh",
            "companion/configure-device.sh",
            "companion/start-focus.sh",
            "companion/verify-runtime-bundle.sh",
            "device/TC002_Focus_Probe/TemporaryFocusRelease/EasyUI.cfg",
            "device/TC002_Focus_Probe/TemporaryFocusRelease/lib/libzkgui.so",
            "device/TC002_Focus_Probe/TemporaryFocusRelease/ui/audio/focus_done.mp3"
        ]
        for relative in required where !FileManager.default.fileExists(atPath: repo + "/" + relative) {
            throw RunnerError.failed("发布包不完整，缺少 \(relative)")
        }
        guard let node = resolvedNodePath() else { throw EnvironmentError.missingTool(name: "Node.js 24+", brewPackage: "node") }
        let nodeVersion = try run(node, args: ["--version"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let nodeMajor = Int(nodeVersion.drop(while: { !$0.isNumber }).prefix(while: { $0.isNumber })) ?? 0
        guard nodeMajor >= 24 else { throw EnvironmentError.nodeTooOld(version: nodeVersion) }
        guard let adb = resolvedExecutable("adb", preferred: ["/opt/homebrew/bin/adb", "/usr/local/bin/adb", "/usr/bin/adb"]) else { throw EnvironmentError.missingTool(name: "ADB", brewPackage: "android-platform-tools") }
        _ = try run(adb, args: ["version"])
        guard let brew = resolvedExecutable("brew", preferred: ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]) else { throw RunnerError.failed("未找到 Homebrew；无法定位或自动安装 EMQX") }
        do { _ = try run(brew, args: ["--prefix", "emqx"]) }
        catch { throw EnvironmentError.missingTool(name: "EMQX", brewPackage: "emqx") }
        _ = try run("/bin/bash", args: [repo + "/companion/verify-runtime-bundle.sh"], cwd: repo)
    }
    private static let invalidDeviceAddress = "时钟地址只填 IPv4 或 IPv4:端口，例如 192.168.1.132:5555；不要粘贴 http:// 链接"
    private static func adbTarget(_ input: String) -> String? {
        let parts = input.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return nil }
        let octets = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4, octets.allSatisfy({ UInt8($0) != nil }) else { return nil }
        let port = parts.count == 2 ? UInt16(parts[1]) : 5555
        guard let port, port > 0 else { return nil }
        return "\(parts[0]):\(port)"
    }
    private static func connectDevice(_ target: String) throws -> UInt16 {
        try probeDevicePort(target)
        let adb = adbPath()
        let serverPort = try adbServer.ensureRunning(adb: adb)
        var lastError = "未知错误"
        for attempt in 1...2 {
            do {
                let output = try run(adb, args: adb == "/usr/bin/env" ? ["adb", "connect", target] : ["connect", target], adbServerPort: serverPort)
                let connected = output.lowercased().split(separator: "\n").contains {
                    $0.hasPrefix("connected to ") || $0.hasPrefix("already connected to ")
                }
                guard connected else { throw RunnerError.failed(output.trimmingCharacters(in: .whitespacesAndNewlines)) }
                let state = try run(adb, args: adb == "/usr/bin/env" ? ["adb", "-s", target, "get-state"] : ["-s", target, "get-state"], adbServerPort: serverPort)
                guard state.trimmingCharacters(in: .whitespacesAndNewlines) == "device" else { throw RunnerError.failed("ADB 未返回 device 状态：\(state)") }
                return serverPort
            } catch {
                lastError = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                if attempt == 1 { Thread.sleep(forTimeInterval: 1) }
            }
        }
        throw RunnerError.failed("\(target) 的 TCP 端口可达，但 GUI 专用 ADB 服务无法连接。请检查 macOS“本地网络”权限及拦截 adb 的网络工具，退出并重新打开 GUI 后重试。原始错误：\(lastError)")
    }
    private static func probeDevicePort(_ target: String) throws {
        let parts = target.split(separator: ":")
        guard parts.count == 2, let portNumber = UInt16(parts[1]), let port = NWEndpoint.Port(rawValue: portNumber) else {
            throw RunnerError.failed(invalidDeviceAddress)
        }
        let connection = NWConnection(host: NWEndpoint.Host(String(parts[0])), port: port, using: .tcp)
        let completed = DispatchSemaphore(value: 0)
        var failure: Error?
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready: completed.signal()
            case .failed(let error): failure = error; completed.signal()
            default: break
            }
        }
        connection.start(queue: DispatchQueue(label: "tc002-focus-device-probe"))
        let timedOut = completed.wait(timeout: .now() + 12) == .timedOut
        connection.cancel()
        if timedOut {
            throw RunnerError.failed("Mac 连接 \(target) 超时。请确认时钟当前 IP、Wi-Fi ADB，以及 macOS“本地网络”权限。")
        }
        if let failure {
            throw RunnerError.failed("Mac 无法连接 \(target) 的 TCP 端口。请核对时钟当前 IP、Wi-Fi 和 macOS“本地网络”权限。底层错误：\(failure.localizedDescription)")
        }
    }
    private static func adbPath() -> String { resolvedExecutable("adb", preferred: ["/opt/homebrew/bin/adb", "/usr/local/bin/adb", "/usr/bin/adb"]) ?? "/usr/bin/env" }
    private static func nodePath() -> String { resolvedNodePath() ?? "/usr/bin/env" }
    private static func resolvedNodePath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = [
            "/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node",
            home + "/.local/bin/node", home + "/.volta/bin/node", home + "/.local/share/mise/shims/node"
        ]
        let roots = [home + "/.local/node", home + "/.nvm/versions/node"]
        for root in roots {
            if let entries = try? FileManager.default.contentsOfDirectory(atPath: root) {
                candidates.append(contentsOf: entries.sorted().reversed().map { root + "/" + $0 + "/bin/node" })
            }
        }
        let fnmRoot = home + "/Library/Application Support/fnm/node-versions"
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: fnmRoot) {
            candidates.append(contentsOf: entries.sorted().reversed().map { fnmRoot + "/" + $0 + "/installation/bin/node" })
        }
        return resolvedExecutable("node", preferred: candidates)
    }
    private static func resolvedExecutable(_ name: String, preferred: [String]) -> String? {
        var candidates = preferred
        let environmentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        candidates.append(contentsOf: environmentPath.split(separator: ":").map { String($0) + "/" + name })
        var seen = Set<String>()
        return candidates.first { seen.insert($0).inserted && FileManager.default.isExecutableFile(atPath: $0) }
    }
    private static func toolPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [resolvedNodePath().map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }, home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"].compactMap { $0 }
        let uniquePaths = NSOrderedSet(array: paths).array.compactMap { $0 as? String }
        return uniquePaths.joined(separator: ":")
    }
    private static func friendlyError(_ message: String) -> String {
        if message.contains("找不到 EMQX") || message.contains("brew --prefix emqx") { return "EMQX 未安装。请先运行一键准备，或执行 brew install emqx。\n\(message)" }
        if message.contains("TCP 端口") || message.contains("Mac 连接") { return message }
        if message.contains("ADB") || message.contains("adb") { return "无法连接 TC002。请确认时钟已开启 Wi-Fi ADB，且与 Mac 在同一局域网。\n\(message)" }
        if message.contains("system status") || message.contains("Lark") || message.contains("钥匙串") { return "Lark 配置不完整。请确认自建应用已开通系统状态权限，然后重新授权。\n\(message)" }
        return message
    }
}
