import AppKit
import CoreGraphics
import Foundation
import OSLog
import PadScreenHostCore
import ServiceManagement

@MainActor
final class PadScreenAppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "app.padscreen.host", category: "status")
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusMenuItem = NSMenuItem(title: "正在启动…", action: nil, keyEquivalent: "")
    private var virtualDisplay: CoreGraphicsVirtualDisplay?
    private var server: PadScreenServer?
    private var capture: ScreenCaptureEncoder?
    private var input: RemoteInputInjector?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem.button?.title = "▣ PadScreen"
        let menu = NSMenu()
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "请求屏幕录制权限", action: #selector(requestScreenPermission), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "请求辅助功能权限", action: #selector(requestInputPermission), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "切换登录时启动", action: #selector(toggleLoginItem), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items where item.action != nil { item.target = self }
        statusItem.menu = menu

        do {
            let synthetic = CommandLine.arguments.contains("--synthetic")
            let displayID: CGDirectDisplayID
            if synthetic {
                displayID = CGMainDisplayID()
                setStatus("合成联调模式 · 端口 \(PadScreenServer.defaultPort)")
            } else {
                let display = try CoreGraphicsVirtualDisplay()
                try display.makePrimaryMirroringPhysicalDisplays()
                virtualDisplay = display
                displayID = display.displayID
                setStatus("虚拟主屏已创建")
            }

            let injector = RemoteInputInjector(displayBounds: CGDisplayBounds(displayID))
            input = injector
            let server = PadScreenServer(
                inputHandler: { [weak injector] message in try? injector?.inject(message) },
                stateHandler: { [weak self] state in
                    DispatchQueue.main.async { self?.setStatus(state) }
                }
            )
            try server.start()
            self.server = server

            guard !synthetic else { return }
            let capture = try ScreenCaptureEncoder(displayID: displayID) { [weak server] packet in
                server?.send(packet)
            }
            self.capture = capture
            Task {
                do {
                    try await capture.start()
                    setStatus("等待平板连接 · \(PadScreenServer.defaultPort)")
                } catch {
                    setStatus("采集失败：\(error.localizedDescription)")
                }
            }
        } catch {
            setStatus("启动失败：\(error.localizedDescription)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
        if let capture { Task { await capture.stop() } }
    }

    @objc private func requestScreenPermission() {
        _ = CGRequestScreenCaptureAccess()
        setStatus(CGPreflightScreenCaptureAccess() ? "屏幕录制权限已就绪" : "请在系统设置中允许屏幕录制")
    }

    @objc private func requestInputPermission() {
        setStatus(RemoteInputInjector.requestAuthorizationPrompt() ? "辅助功能权限已就绪" : "请在系统设置中允许辅助功能")
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                setStatus("已关闭登录时启动")
            } else {
                try SMAppService.mainApp.register()
                setStatus("已启用登录时启动")
            }
        } catch {
            setStatus("登录项设置失败：请使用打包后的 .app")
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func setStatus(_ status: String) {
        logger.info("\(status, privacy: .public)")
        statusMenuItem.title = status
    }
}

@main
enum PadScreenHostMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = PadScreenAppDelegate()
        application.delegate = delegate
        application.run()
    }
}
