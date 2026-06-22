@preconcurrency import AppKit
import CoreAudio
@preconcurrency import Foundation
import IOKit.hid

struct AppConfig: Codable, Sendable {
    var chromeBundleID: String
    var chromePath: String
    var chatGPTURL: String
    var projectURL: String
    var openingPrompt: String
    var inputDeviceName: String
    var outputDeviceName: String
    var buttonNameHints: [String]
    var chromeProfileDir: String
    var remoteDebuggingPort: Int
    var debounceInterval: TimeInterval
    var healthCheckInterval: TimeInterval
    var webLoadTimeout: TimeInterval
    var webPollInterval: TimeInterval

    init(
        chromeBundleID: String = "com.google.Chrome",
        chromePath: String = "/Applications/Google Chrome.app",
        chatGPTURL: String = "https://chatgpt.com",
        projectURL: String = "",
        openingPrompt: String = "안녕! 무엇이 궁금해?",
        inputDeviceName: String = "",
        outputDeviceName: String = "",
        buttonNameHints: [String] = [],
        chromeProfileDir: String = "\(NSHomeDirectory())/Library/Application Support/Click2Chat/ChromeProfile",
        remoteDebuggingPort: Int = 9222,
        debounceInterval: TimeInterval = 1.0,
        healthCheckInterval: TimeInterval = 10.0,
        webLoadTimeout: TimeInterval = 20.0,
        webPollInterval: TimeInterval = 0.5
    ) {
        self.chromeBundleID = chromeBundleID
        self.chromePath = chromePath
        self.chatGPTURL = chatGPTURL
        self.projectURL = projectURL
        self.openingPrompt = openingPrompt
        self.inputDeviceName = inputDeviceName
        self.outputDeviceName = outputDeviceName
        self.buttonNameHints = buttonNameHints
        self.chromeProfileDir = chromeProfileDir
        self.remoteDebuggingPort = remoteDebuggingPort
        self.debounceInterval = debounceInterval
        self.healthCheckInterval = healthCheckInterval
        self.webLoadTimeout = webLoadTimeout
        self.webPollInterval = webPollInterval
    }

    enum CodingKeys: String, CodingKey {
        case chromeBundleID
        case chromePath
        case chatGPTURL
        case projectURL
        case openingPrompt
        case inputDeviceName
        case outputDeviceName
        case buttonNameHints
        case chromeProfileDir
        case remoteDebuggingPort
        case debounceInterval
        case healthCheckInterval
        case webLoadTimeout
        case webPollInterval
    }

    init(from decoder: Decoder) throws {
        let defaults = AppConfig()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chromeBundleID = try container.decodeIfPresent(String.self, forKey: .chromeBundleID) ?? defaults.chromeBundleID
        chromePath = try container.decodeIfPresent(String.self, forKey: .chromePath) ?? defaults.chromePath
        chatGPTURL = try container.decodeIfPresent(String.self, forKey: .chatGPTURL) ?? defaults.chatGPTURL
        projectURL = try container.decodeIfPresent(String.self, forKey: .projectURL) ?? defaults.projectURL
        openingPrompt = try container.decodeIfPresent(String.self, forKey: .openingPrompt) ?? defaults.openingPrompt
        inputDeviceName = try container.decodeIfPresent(String.self, forKey: .inputDeviceName) ?? defaults.inputDeviceName
        outputDeviceName = try container.decodeIfPresent(String.self, forKey: .outputDeviceName) ?? defaults.outputDeviceName
        buttonNameHints = try container.decodeIfPresent([String].self, forKey: .buttonNameHints) ?? defaults.buttonNameHints
        chromeProfileDir = try container.decodeIfPresent(String.self, forKey: .chromeProfileDir) ?? defaults.chromeProfileDir
        remoteDebuggingPort = try container.decodeIfPresent(Int.self, forKey: .remoteDebuggingPort) ?? defaults.remoteDebuggingPort
        debounceInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .debounceInterval) ?? defaults.debounceInterval
        healthCheckInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .healthCheckInterval) ?? defaults.healthCheckInterval
        webLoadTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .webLoadTimeout) ?? defaults.webLoadTimeout
        webPollInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .webPollInterval) ?? defaults.webPollInterval
    }

    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Click2Chat", isDirectory: true)
    }

    static var configURL: URL {
        supportDirectory.appendingPathComponent("config.json")
    }

    static var environmentURL: URL {
        supportDirectory.appendingPathComponent(".env")
    }

    static func loadOrCreate() -> AppConfig {
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: configURL),
           let config = try? JSONDecoder().decode(AppConfig.self, from: data) {
            return config
        }

        var config = AppConfig()
        let legacyEnvironment = DotEnv.load(from: environmentURL)
        if !legacyEnvironment.isEmpty {
            config.apply(environment: legacyEnvironment)
        }
        try? config.save()
        return config
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Self.supportDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder.pretty.encode(self)
        try data.write(to: Self.configURL, options: .atomic)
    }

    var hasProjectURL: Bool {
        !projectURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var validationProblems: [String] {
        var problems: [String] = []
        if !hasProjectURL {
            problems.append("ChatGPT 프로젝트 URL이 없습니다")
        } else if let url = URL(string: projectURL), url.scheme == "https", url.host == "chatgpt.com" {
            // Valid ChatGPT URL.
        } else {
            problems.append("프로젝트 URL은 https://chatgpt.com 주소여야 합니다")
        }
        if inputDeviceName.isEmpty { problems.append("마이크를 선택하지 않았습니다") }
        if outputDeviceName.isEmpty { problems.append("스피커를 선택하지 않았습니다") }
        if buttonNameHints.isEmpty { problems.append("버튼 이름을 입력하지 않았습니다") }
        if !(1...65535).contains(remoteDebuggingPort) {
            problems.append("Chrome 디버깅 포트는 1~65535여야 합니다")
        }
        return problems
    }

    mutating func apply(environment: [String: String]) {
        func value(_ key: String) -> String? {
            guard let raw = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                return nil
            }
            return raw
        }

        if let raw = value("CLICK2CHAT_CHROME_PATH") { chromePath = raw }
        if let raw = value("CLICK2CHAT_CHATGPT_URL") { chatGPTURL = raw }
        if let raw = value("CLICK2CHAT_PROJECT_URL") { projectURL = raw }
        if let raw = environment["CLICK2CHAT_OPENING_PROMPT"] { openingPrompt = raw }
        if let raw = value("CLICK2CHAT_INPUT_DEVICE_NAME") { inputDeviceName = raw }
        if let raw = value("CLICK2CHAT_OUTPUT_DEVICE_NAME") { outputDeviceName = raw }
        if let raw = value("CLICK2CHAT_BUTTON_NAME_HINTS") {
            buttonNameHints = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if let raw = value("CLICK2CHAT_CHROME_PROFILE_DIR") { chromeProfileDir = NSString(string: raw).expandingTildeInPath }
        if let raw = value("CLICK2CHAT_REMOTE_DEBUGGING_PORT"), let parsed = Int(raw) { remoteDebuggingPort = parsed }
        if let raw = value("CLICK2CHAT_DEBOUNCE_INTERVAL"), let parsed = TimeInterval(raw) { debounceInterval = parsed }
        if let raw = value("CLICK2CHAT_HEALTH_CHECK_INTERVAL"), let parsed = TimeInterval(raw) { healthCheckInterval = parsed }
        if let raw = value("CLICK2CHAT_WEB_LOAD_TIMEOUT"), let parsed = TimeInterval(raw) { webLoadTimeout = parsed }
        if let raw = value("CLICK2CHAT_WEB_POLL_INTERVAL"), let parsed = TimeInterval(raw) { webPollInterval = parsed }
    }
}

enum DotEnv {
    static func load(from url: URL) -> [String: String] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, let last = value.last,
               (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                value.removeFirst()
                value.removeLast()
            }
            values[key] = value
        }
        return values
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

enum VoiceState: Equatable {
    case idle
    case starting
    case active
    case recovering
    case error(String)

    var title: String {
        switch self {
        case .idle:
            return "Click2Chat: 대기"
        case .starting:
            return "Click2Chat: 시작 중"
        case .active:
            return "Click2Chat: 대화 중"
        case .recovering:
            return "Click2Chat: 새 대화 준비 중"
        case .error(let message):
            return "Click2Chat: 오류 - \(message)"
        }
    }

    var statusSymbolName: String {
        switch self {
        case .idle:
            return "message.fill"
        case .starting, .recovering:
            return "ellipsis.message.fill"
        case .active:
            return "waveform.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
}

final class Logger: @unchecked Sendable {
    private let logURL: URL

    init() {
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        logURL = logs.appendingPathComponent("Click2Chat.log")
    }

    func write(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL)
        }
    }
}

final class AudioDeviceManager {
    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    func ensure(inputName: String, outputName: String) -> [String] {
        var problems: [String] = []

        if !setDefaultDevice(named: inputName, selector: kAudioHardwarePropertyDefaultInputDevice) {
            problems.append("마이크 없음: \(inputName)")
        }

        if !setDefaultDevice(named: outputName, selector: kAudioHardwarePropertyDefaultOutputDevice) {
            problems.append("스피커 없음: \(outputName)")
        }

        return problems
    }

    func hasDevice(named name: String) -> Bool {
        devices().contains { deviceName($0) == name }
    }

    func allDeviceNames() -> [String] {
        devices().compactMap { deviceName($0) }.sorted()
    }

    private func setDefaultDevice(named name: String, selector: AudioObjectPropertySelector) -> Bool {
        guard let device = devices().first(where: { deviceName($0) == name }) else {
            logger.write("Audio device not found: \(name)")
            return false
        }

        var deviceID = device
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )

        if status != noErr {
            logger.write("Failed to set default audio device \(name): \(status)")
            return false
        }

        return true
    }

    private func devices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(0), count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            return []
        }

        return deviceIDs
    }

    private func deviceName(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return name as String
    }
}

final class WebChatGPTController: @unchecked Sendable {
    private let config: AppConfig
    private let logger: Logger

    init(config: AppConfig, logger: Logger) {
        self.config = config
        self.logger = logger
    }

    func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: config.chromePath)
    }

    func startFreshVoiceConversation(completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        guard isInstalled() else {
            completion(.failure(RuntimeError("Google Chrome이 /Applications에 없습니다.")))
            return
        }
        guard config.hasProjectURL else {
            completion(.failure(RuntimeError("Settings에서 ChatGPT 프로젝트 URL을 설정해야 합니다.")))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.runChromeVoice("start-fresh-voice")
            DispatchQueue.main.async {
                switch result {
                case .success(let status):
                    self.logger.write("Chrome fresh voice status: \(status)")
                    if status == "started" {
                        completion(.success(()))
                    } else if status == "login-required" {
                        completion(.failure(RuntimeError("Click2Chat Chrome 프로필에서 ChatGPT 로그인이 필요합니다.")))
                    } else if status == "project-unavailable" {
                        completion(.failure(RuntimeError("ChatGPT 프로젝트 URL을 열 수 없습니다. Settings를 확인하세요.")))
                    } else if status == "missing-project-url" {
                        completion(.failure(RuntimeError("Settings에서 ChatGPT 프로젝트 URL을 설정해야 합니다.")))
                    } else if status == "voice-button-missing" {
                        completion(.failure(RuntimeError("ChatGPT 웹 Voice 버튼을 찾지 못했습니다.")))
                    } else if status == "chrome-unreachable" {
                        completion(.failure(RuntimeError("Chrome DevTools에 연결하지 못했습니다.")))
                    } else {
                        completion(.failure(RuntimeError("ChatGPT Voice 시작 실패: \(status)")))
                    }
                case .failure(let error):
                    self.logger.write("Chrome fresh voice failed: \(error.localizedDescription)")
                    completion(.failure(error))
                }
            }
        }
    }

    func toggleVoiceConversation(completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        guard isInstalled() else {
            completion(.failure(RuntimeError("Google Chrome이 /Applications에 없습니다.")))
            return
        }
        guard config.hasProjectURL else {
            completion(.failure(RuntimeError("Settings에서 ChatGPT 프로젝트 URL을 설정해야 합니다.")))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.runChromeVoice("toggle-voice")
            DispatchQueue.main.async {
                switch result {
                case .success(let status):
                    self.logger.write("Chrome voice toggle status: \(status)")
                    if status == "started" || status == "stopped" || status == "not-active" {
                        completion(.success(status))
                    } else if status == "login-required" {
                        completion(.failure(RuntimeError("Click2Chat Chrome 프로필에서 ChatGPT 로그인이 필요합니다.")))
                    } else if status == "project-unavailable" {
                        completion(.failure(RuntimeError("ChatGPT 프로젝트 URL을 열 수 없습니다. Settings를 확인하세요.")))
                    } else if status == "voice-button-missing" {
                        completion(.failure(RuntimeError("ChatGPT 웹 Voice 버튼을 찾지 못했습니다.")))
                    } else {
                        completion(.failure(RuntimeError("ChatGPT Voice 토글 실패: \(status)")))
                    }
                case .failure(let error):
                    self.logger.write("Chrome voice toggle failed: \(error.localizedDescription)")
                    completion(.failure(error))
                }
            }
        }
    }

    func stopVoiceConversation(completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.runChromeVoice("stop-voice")
            DispatchQueue.main.async {
                switch result {
                case .success(let output):
                    let status = output
                    if status == "stopped" || status == "not-active" {
                        completion(.success(status))
                    } else {
                        completion(.failure(RuntimeError("ChatGPT 웹 Voice 종료 버튼을 찾지 못했습니다: \(status)")))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    static func requestAutomationPermissions() -> Result<String, Error> {
        let config = AppConfig.loadOrCreate()
        let logger = Logger()
        let controller = WebChatGPTController(config: config, logger: logger)
        return controller.runChromeVoice("open-project")
    }

    func openProject() -> Result<String, Error> {
        guard config.hasProjectURL else {
            return .failure(RuntimeError("Settings에서 ChatGPT 프로젝트 URL을 설정해야 합니다."))
        }
        return runChromeVoice("open-project")
    }

    func status() -> Result<String, Error> {
        runChromeVoice("status")
    }

    private func runChromeVoice(_ action: String) -> Result<String, Error> {
        guard let scriptPath = chromeVoiceScriptPath() else {
            return .failure(RuntimeError("chrome_voice.mjs를 찾을 수 없습니다."))
        }

        let process = Process()
        let nodePath = nodeExecutablePath()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = nodePath == "/usr/bin/env" ? ["node", scriptPath, action] : [scriptPath, action]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "CLICK2CHAT_CONFIG": AppConfig.configURL.path
        ]) { current, _ in current }
        let output = Pipe()
        let errorOutput = Pipe()
        process.standardOutput = output
        process.standardError = errorOutput

        do {
            try process.run()
            process.waitUntilExit()
            let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: errorOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if process.terminationStatus == 0 {
                return .success(stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return .failure(RuntimeError(stderr.trimmingCharacters(in: .whitespacesAndNewlines)))
        } catch {
            return .failure(error)
        }
    }

    private func chromeVoiceScriptPath() -> String? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("chrome_voice.mjs").path
        if let bundled, FileManager.default.fileExists(atPath: bundled) {
            return bundled
        }

        let source = FileManager.default.currentDirectoryPath + "/scripts/chrome_voice.mjs"
        if FileManager.default.fileExists(atPath: source) {
            return source
        }
        return nil
    }

    private func nodeExecutablePath() -> String {
        for path in ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"] {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return "/usr/bin/env"
    }

}

struct RuntimeError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

final class HIDButtonMonitor {
    private let config: AppConfig
    private let logger: Logger
    private let onButtonPress: () -> Void
    private let onDeviceListChanged: () -> Void
    private var manager: IOHIDManager
    private var connectedProducts = Set<String>()
    private var lastPress = Date.distantPast

    init(
        config: AppConfig,
        logger: Logger,
        onButtonPress: @escaping () -> Void,
        onDeviceListChanged: @escaping () -> Void
    ) {
        self.config = config
        self.logger = logger
        self.onButtonPress = onButtonPress
        self.onDeviceListChanged = onDeviceListChanged
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func start() {
        let keyboardMatch: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard
        ]
        let consumerMatch: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_Consumer,
            kIOHIDDeviceUsageKey: kHIDUsage_Csmr_ConsumerControl
        ]

        IOHIDManagerSetDeviceMatchingMultiple(manager, [keyboardMatch, consumerMatch] as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, HIDButtonMonitor.deviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, HIDButtonMonitor.deviceRemoved, context)
        IOHIDManagerRegisterInputValueCallback(manager, HIDButtonMonitor.inputValue, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            logger.write("IOHIDManagerOpen failed: \(result)")
        }
        refreshConnectedDevices()
    }

    func hasTargetDevice() -> Bool {
        connectedProducts.contains { isTargetProduct($0) }
    }

    private func refreshConnectedDevices() {
        connectedProducts.removeAll()
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            onDeviceListChanged()
            return
        }

        for device in devices {
            if let product = productName(for: device) {
                connectedProducts.insert(product)
            }
        }
        onDeviceListChanged()
    }

    private func handleDeviceMatched(_ device: IOHIDDevice) {
        if let product = productName(for: device) {
            connectedProducts.insert(product)
            logger.write("HID connected: \(product)")
        }
        onDeviceListChanged()
    }

    private func handleDeviceRemoved(_ device: IOHIDDevice) {
        if let product = productName(for: device) {
            connectedProducts.remove(product)
            logger.write("HID removed: \(product)")
        }
        refreshConnectedDevices()
    }

    private func handleInput(product: String?, usagePage: UInt32, usage: UInt32, value: Int) {
        guard value != 0 else { return }
        guard let product, isTargetProduct(product) else { return }

        let now = Date()
        guard now.timeIntervalSince(lastPress) >= config.debounceInterval else {
            logger.write("Ignored debounced button press from \(product)")
            return
        }

        lastPress = now
        logger.write("Button press from \(product), usagePage=\(usagePage), usage=\(usage)")
        onButtonPress()
    }

    private func isTargetProduct(_ product: String) -> Bool {
        config.buttonNameHints.contains { hint in
            product.localizedCaseInsensitiveContains(hint)
        }
    }

    private func productName(for device: IOHIDDevice) -> String? {
        IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
    }

    private static let deviceMatched: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        let monitor = Unmanaged<HIDButtonMonitor>.fromOpaque(context).takeUnretainedValue()
        monitor.handleDeviceMatched(device)
    }

    private static let deviceRemoved: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        let monitor = Unmanaged<HIDButtonMonitor>.fromOpaque(context).takeUnretainedValue()
        monitor.handleDeviceRemoved(device)
    }

    private static let inputValue: IOHIDValueCallback = { context, _, _, value in
        guard let context else { return }
        let monitor = Unmanaged<HIDButtonMonitor>.fromOpaque(context).takeUnretainedValue()
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        let product = monitor.productName(for: device)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)
        monitor.handleInput(product: product, usagePage: usagePage, usage: usage, value: intValue)
    }
}

enum Diagnostics {
    static func run() {
        let config = AppConfig.loadOrCreate()
        print(report(config: config))
    }

    static func report(config: AppConfig) -> String {
        let logger = Logger()
        let audio = AudioDeviceManager(logger: logger)
        var lines: [String] = []

        lines.append("Click2Chat diagnostics")
        lines.append("")
        lines.append("Config: \(AppConfig.configURL.path)")
        lines.append("Project URL: \(config.hasProjectURL ? config.projectURL : "missing")")
        lines.append("Chrome: \(FileManager.default.fileExists(atPath: config.chromePath) ? "installed" : "missing")")
        lines.append("ChatGPT web: \(config.chatGPTURL)")
        lines.append("Chrome profile: \(config.chromeProfileDir)")
        lines.append("Remote debugging port: \(config.remoteDebuggingPort)")
        if !config.validationProblems.isEmpty {
            lines.append("")
            lines.append("Configuration problems:")
            lines.append(contentsOf: config.validationProblems.map { "- \($0)" })
        }
        lines.append("")
        lines.append("Audio devices:")
        for name in audio.allDeviceNames() {
            let marker: String
            if name == config.inputDeviceName {
                marker = " [target input]"
            } else if name == config.outputDeviceName {
                marker = " [target output]"
            } else {
                marker = ""
            }
            lines.append("- \(name)\(marker)")
        }
        lines.append("")
        lines.append("HID products:")
        for product in hidProducts() {
            let marker = config.buttonNameHints.contains { product.localizedCaseInsensitiveContains($0) } ? " [target button]" : ""
            lines.append("- \(product)\(marker)")
        }
        return lines.joined(separator: "\n")
    }

    private static func hidProducts() -> [String] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let keyboardMatch: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard
        ]
        let consumerMatch: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_Consumer,
            kIOHIDDeviceUsageKey: kHIDUsage_Csmr_ConsumerControl
        ]

        IOHIDManagerSetDeviceMatchingMultiple(manager, [keyboardMatch, consumerMatch] as CFArray)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return []
        }

        return devices
            .compactMap { IOHIDDeviceGetProperty($0, kIOHIDProductKey as CFString) as? String }
            .sorted()
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private let projectURLField = NSTextField()
    private let openingPromptField = NSTextField()
    private let inputDeviceField = NSComboBox()
    private let outputDeviceField = NSComboBox()
    private let buttonHintsField = NSTextField()
    private let chromePathField = NSTextField()
    private let chromeProfileField = NSTextField()
    private let portField = NSTextField()
    private let debounceField = NSTextField()
    private let healthCheckField = NSTextField()
    private let loadTimeoutField = NSTextField()
    private let pollIntervalField = NSTextField()

    init(config: AppConfig, audioDeviceNames: [String]) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Click2Chat 설정"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        projectURLField.stringValue = config.projectURL
        openingPromptField.stringValue = config.openingPrompt
        inputDeviceField.addItems(withObjectValues: audioDeviceNames)
        inputDeviceField.stringValue = config.inputDeviceName
        outputDeviceField.addItems(withObjectValues: audioDeviceNames)
        outputDeviceField.stringValue = config.outputDeviceName
        buttonHintsField.stringValue = config.buttonNameHints.joined(separator: ", ")
        chromePathField.stringValue = config.chromePath
        chromeProfileField.stringValue = config.chromeProfileDir
        portField.stringValue = String(config.remoteDebuggingPort)
        debounceField.stringValue = String(config.debounceInterval)
        healthCheckField.stringValue = String(config.healthCheckInterval)
        loadTimeoutField.stringValue = String(config.webLoadTimeout)
        pollIntervalField.stringValue = String(config.webPollInterval)

        let rows: [(String, NSView)] = [
            ("ChatGPT 프로젝트 URL", projectURLField),
            ("첫 인사", openingPromptField),
            ("마이크", inputDeviceField),
            ("스피커", outputDeviceField),
            ("버튼 이름 (쉼표 구분)", buttonHintsField),
            ("Chrome 경로", chromePathField),
            ("Chrome 프로필 경로", chromeProfileField),
            ("디버깅 포트", portField),
            ("버튼 입력 간격 (초)", debounceField),
            ("상태 확인 주기 (초)", healthCheckField),
            ("웹 로딩 제한 (초)", loadTimeoutField),
            ("웹 확인 주기 (초)", pollIntervalField)
        ]

        let grid = NSGridView(views: rows.map { row in
            let label = NSTextField(labelWithString: row.0)
            label.alignment = .right
            return [label, row.1]
        })
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill

        for field in [projectURLField, openingPromptField, buttonHintsField, chromePathField, chromeProfileField] {
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }

        let help = NSTextField(labelWithString: "저장한 설정은 Click2Chat을 다시 시작하면 적용됩니다.")
        help.textColor = .secondaryLabelColor
        let saveButton = NSButton(title: "저장", target: self, action: #selector(saveSettings))
        saveButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: "취소", target: self, action: #selector(closeWindow))
        let buttons = NSStackView(views: [cancelButton, saveButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8

        let footer = NSStackView(views: [help, buttons])
        footer.orientation = .horizontal
        footer.distribution = .fill
        footer.alignment = .centerY

        let content = NSStackView(views: [grid, footer])
        content.orientation = .vertical
        content.spacing = 18
        content.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = NSView()
        window.contentView?.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            content.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -20)
        ])
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func saveSettings() {
        guard let port = Int(portField.stringValue),
              let debounce = TimeInterval(debounceField.stringValue),
              let healthCheck = TimeInterval(healthCheckField.stringValue),
              let loadTimeout = TimeInterval(loadTimeoutField.stringValue),
              let pollInterval = TimeInterval(pollIntervalField.stringValue) else {
            showAlert(message: "숫자 설정을 확인해 주세요.", informativeText: "포트와 시간 값에는 숫자만 입력할 수 있습니다.")
            return
        }

        var config = AppConfig.loadOrCreate()
        config.projectURL = projectURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        config.openingPrompt = openingPromptField.stringValue
        config.inputDeviceName = inputDeviceField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        config.outputDeviceName = outputDeviceField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        config.buttonNameHints = buttonHintsField.stringValue.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        config.chromePath = chromePathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        config.chromeProfileDir = NSString(string: chromeProfileField.stringValue).expandingTildeInPath
        config.remoteDebuggingPort = port
        config.debounceInterval = debounce
        config.healthCheckInterval = healthCheck
        config.webLoadTimeout = loadTimeout
        config.webPollInterval = pollInterval

        do {
            try config.save()
            let warnings = config.validationProblems
            let detail = warnings.isEmpty
                ? "앱을 종료한 뒤 다시 실행하면 새 설정이 적용됩니다."
                : "저장되었습니다. 다음 항목을 확인해 주세요:\n\n" + warnings.map { "• \($0)" }.joined(separator: "\n")
            showAlert(message: "설정을 저장했습니다", informativeText: detail)
            close()
        } catch {
            showAlert(message: "설정을 저장하지 못했습니다", informativeText: error.localizedDescription)
        }
    }

    @objc private func closeWindow() {
        close()
    }

    private func showAlert(message: String, informativeText: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informativeText
        alert.runModal()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private let config = AppConfig.loadOrCreate()
    private let logger = Logger()
    private lazy var audio = AudioDeviceManager(logger: logger)
    private lazy var chatGPT = WebChatGPTController(config: config, logger: logger)
    private var hidMonitor: HIDButtonMonitor?
    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?
    private var state: VoiceState = .idle {
        didSet {
            logger.write("State changed: \(state.title)")
            updateMenu()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.write("Click2Chat launched")
        setupStatusItem()
        startHIDMonitor()
        runHealthCheck()
        if CommandLine.arguments.contains("--settings") {
            menuSettings()
        }
        Timer.scheduledTimer(withTimeInterval: config.healthCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.runHealthCheck()
            }
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        updateStatusIcon(for: .idle)
        updateMenu()
    }

    private func updateStatusIcon(for state: VoiceState) {
        guard let button = statusItem?.button else { return }
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(
            systemSymbolName: state.statusSymbolName,
            accessibilityDescription: state.title
        ) ?? NSImage(systemSymbolName: "message.fill", accessibilityDescription: "Click2Chat")
        image?.isTemplate = true
        button.title = ""
        button.image = image?.withSymbolConfiguration(configuration)
        button.imagePosition = .imageOnly
    }

    private func startHIDMonitor() {
        hidMonitor = HIDButtonMonitor(
            config: config,
            logger: logger,
            onButtonPress: { [weak self] in
                self?.toggleVoiceFromButton()
            },
            onDeviceListChanged: { [weak self] in
                self?.updateMenu()
            }
        )
        hidMonitor?.start()
    }

    private func toggleVoiceFromButton() {
        switch state {
        case .active:
            stopVoice()
        case .idle, .error:
            toggleVoice()
        case .starting, .recovering:
            logger.write("Ignored button press while transition is in progress")
        }
    }

    private func toggleVoice() {
        state = state == .active ? .recovering : .starting
        let audioProblems = audio.ensure(inputName: config.inputDeviceName, outputName: config.outputDeviceName)
        guard audioProblems.isEmpty else {
            state = .error(audioProblems.joined(separator: ", "))
            return
        }

        chatGPT.toggleVoiceConversation { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let status):
                    if status == "started" {
                        self.state = .active
                    } else {
                        self.logger.write("Toggle completed with status: \(status)")
                        self.state = .idle
                    }
                case .failure(let error):
                    self.state = .error(error.localizedDescription)
                }
            }
        }
    }

    private func startFreshVoice(recovering: Bool) {
        state = recovering ? .recovering : .starting
        let audioProblems = audio.ensure(inputName: config.inputDeviceName, outputName: config.outputDeviceName)
        guard audioProblems.isEmpty else {
            state = .error(audioProblems.joined(separator: ", "))
            return
        }

        chatGPT.startFreshVoiceConversation { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success:
                    self.state = .active
                case .failure(let error):
                    self.state = .error(error.localizedDescription)
                }
            }
        }
    }

    private func stopVoice() {
        state = .recovering
        chatGPT.stopVoiceConversation { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let method):
                    self.logger.write("Stop completed with method: \(method)")
                    self.state = .idle
                case .failure(let error):
                    self.state = .error("종료 실패: \(error.localizedDescription)")
                }
            }
        }
    }

    private func runHealthCheck() {
        var errors: [String] = []
        if !chatGPT.isInstalled() {
            errors.append("Chrome 없음")
        }
        if !audio.hasDevice(named: config.inputDeviceName) {
            errors.append("마이크 미연결")
        }
        if !audio.hasDevice(named: config.outputDeviceName) {
            errors.append("스피커 미연결")
        }
        if !errors.isEmpty {
            logger.write("Health check warnings: \(errors.joined(separator: ", "))")
        }

        updateMenu()
    }

    private func updateMenu() {
        guard let statusItem else { return }
        updateStatusIcon(for: state)
        statusItem.button?.toolTip = state.title

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: state.title, action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let buttonConnected = hidMonitor?.hasTargetDevice() == true
        menu.addItem(NSMenuItem(title: "버튼: \(buttonConnected ? "연결됨" : "절전/미감지")", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "마이크: \(audio.hasDevice(named: config.inputDeviceName) ? config.inputDeviceName : "미연결")", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "스피커: \(audio.hasDevice(named: config.outputDeviceName) ? config.outputDeviceName : "미연결")", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "프로젝트 URL: \(config.hasProjectURL ? "설정됨" : "필요")", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Start New Voice Chat", action: #selector(menuStartNewVoiceChat), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Stop Voice", action: #selector(menuStopVoice), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Project", action: #selector(menuOpenProject), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Run Diagnostics", action: #selector(menuRunDiagnostics), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(menuSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(menuQuit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
    }

    @objc private func menuStartNewVoiceChat() {
        startFreshVoice(recovering: state == .active)
    }

    @objc private func menuStopVoice() {
        stopVoice()
    }

    @objc private func menuOpenProject() {
        switch chatGPT.openProject() {
        case .success(let status):
            logger.write("Open project status: \(status)")
        case .failure(let error):
            state = .error(error.localizedDescription)
        }
    }

    @objc private func menuSettings() {
        let controller = SettingsWindowController(
            config: AppConfig.loadOrCreate(),
            audioDeviceNames: audio.allDeviceNames()
        )
        settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func menuRunDiagnostics() {
        let report = Diagnostics.report(config: config)
        logger.write("\n\(report)")
        let alert = NSAlert()
        alert.messageText = "Click2Chat Diagnostics"
        alert.informativeText = report
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func menuQuit() {
        NSApplication.shared.terminate(nil)
    }
}

if CommandLine.arguments.contains("--diagnose") {
    Diagnostics.run()
} else if CommandLine.arguments.contains("--request-permissions") {
    switch WebChatGPTController.requestAutomationPermissions() {
    case .success(let message):
        print(message)
    case .failure(let error):
        print(error.localizedDescription)
        exit(1)
    }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
