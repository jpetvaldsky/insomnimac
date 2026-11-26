// Coffeine – menu bar app that controls whether the Mac can sleep.
//
// "Hard" mode uses `pmset -a disablesleep 1`. This blocks all system sleep,
// also when the lid is closed. pmset needs root, so the app installs a narrow
// sudoers rule once (admin password prompt). After that, the app calls
// `sudo -n /usr/bin/pmset -a disablesleep 0|1` without a password.

import AppKit
import IOKit.pwr_mgt
import IOKit.ps
import ServiceManagement

// MARK: - Power control

enum Power {
    static let pmset = "/usr/bin/pmset"
    static let sudoersPath = "/etc/sudoers.d/coffeine"

    /// Runs a command and returns (exit status, stdout+stderr).
    @discardableResult
    static func run(_ path: String, _ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// True when the system reports SleepDisabled = 1.
    static var isSleepDisabled: Bool {
        let (_, out) = run(pmset, ["-g"])
        for line in out.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count >= 2, parts[0] == "SleepDisabled" { return parts[1] == "1" }
        }
        return false
    }

    /// True when the sudoers rule lets us run pmset without a password.
    static var isHelperInstalled: Bool {
        guard FileManager.default.fileExists(atPath: sudoersPath) else { return false }
        let (status, _) = run("/usr/bin/sudo", ["-n", "-l", pmset, "-a", "disablesleep", "1"])
        return status == 0
    }

    /// Installs the sudoers rule. macOS shows the admin password dialog.
    static func installHelper() -> Bool {
        let user = NSUserName()
        let rule = "\(user) ALL=(root) NOPASSWD: \(pmset) -a disablesleep 0, \(pmset) -a disablesleep 1\n"
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("coffeine.sudoers")
        do { try rule.write(to: tmp, atomically: true, encoding: .utf8) } catch { return false }
        // visudo validates the file before it goes into /etc/sudoers.d.
        let shell = "/usr/sbin/visudo -cf '\(tmp.path)' && /usr/bin/install -m 0440 -o root -g wheel '\(tmp.path)' '\(sudoersPath)'"
        let script = "do shell script \"\(shell)\" with administrator privileges"
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        try? FileManager.default.removeItem(at: tmp)
        return err == nil && isHelperInstalled
    }

    static func uninstallHelper() {
        let script = "do shell script \"/bin/rm -f '\(sudoersPath)'\" with administrator privileges"
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
    }

    @discardableResult
    static func setSleepDisabled(_ disabled: Bool) -> Bool {
        let (status, _) = run("/usr/bin/sudo", ["-n", pmset, "-a", "disablesleep", disabled ? "1" : "0"])
        return status == 0
    }

    /// Battery percentage, or nil when the Mac has no battery.
    static var batteryPercent: Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for src in list {
            guard let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let cur = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return cur * 100 / max
        }
        return nil
    }

    static var isOnBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPSBatteryPowerValue
    }
}

/// Soft layer: IOPM assertion against idle sleep (system or display).
final class Assertion {
    private var id: IOPMAssertionID = 0
    private(set) var active = false

    func set(_ on: Bool, type: String, reason: String) {
        if on == active { return }
        if on {
            active = IOPMAssertionCreateWithName(type as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 reason as CFString, &id) == kIOReturnSuccess
        } else {
            IOPMAssertionRelease(id)
            active = false
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let defaults = UserDefaults.standard
    private var statusItem: NSStatusItem!
    private let systemAssertion = Assertion()
    private let displayAssertion = Assertion()
    private var batteryTimer: Timer?

    private let lowBatteryLimit = 15

    // Saved settings
    private var preventSleep: Bool {
        get { defaults.bool(forKey: "preventSleep") }
        set { defaults.set(newValue, forKey: "preventSleep") }
    }
    private var keepDisplayOn: Bool {
        get { defaults.bool(forKey: "keepDisplayOn") }
        set { defaults.set(newValue, forKey: "keepDisplayOn") }
    }
    private var batteryGuard: Bool {
        get { defaults.object(forKey: "batteryGuard") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "batteryGuard") }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // First launch: register as a login item.
        if !defaults.bool(forKey: "didRegisterLogin") {
            try? SMAppService.mainApp.register()
            defaults.set(true, forKey: "didRegisterLogin")
        }

        // Restore the saved state after login or restart.
        apply()

        batteryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkBattery()
        }
    }

    func applicationWillTerminate(_ note: Notification) {
        // Never leave the Mac in "cannot sleep" state when the app is not running.
        if Power.isSleepDisabled { Power.setSleepDisabled(false) }
        systemAssertion.set(false, type: "", reason: "")
        displayAssertion.set(false, type: "", reason: "")
    }

    // MARK: State

    private func apply() {
        if preventSleep {
            if !Power.isHelperInstalled {
                if !Power.installHelper() {
                    preventSleep = false
                    alert("Cannot prevent sleep",
                          "Coffeine needs an administrator password once to run pmset. Without it, the app cannot block sleep when the lid is closed.")
                }
            }
            if preventSleep && !Power.setSleepDisabled(true) {
                preventSleep = false
                alert("Error", "The pmset command failed.")
            }
        } else if Power.isSleepDisabled {
            Power.setSleepDisabled(false)
        }

        systemAssertion.set(preventSleep, type: kIOPMAssertPreventUserIdleSystemSleep, reason: "Coffeine: sleep prevented")
        displayAssertion.set(preventSleep && keepDisplayOn, type: kIOPMAssertPreventUserIdleDisplaySleep, reason: "Coffeine: display kept on")
        updateIcon()
    }

    private func checkBattery() {
        guard preventSleep, batteryGuard, Power.isOnBattery,
              let pct = Power.batteryPercent, pct <= lowBatteryLimit else { return }
        preventSleep = false
        apply()
        notifyLowBattery(pct)
    }

    private func updateIcon() {
        let symbol = preventSleep ? "cup.and.saucer.fill" : "cup.and.saucer"
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Coffeine")
        img?.isTemplate = true
        statusItem.button?.image = img
        statusItem.button?.toolTip = preventSleep ? "Coffeine: Mac stays awake" : "Coffeine: normal sleep"
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: preventSleep ? "Mac stays AWAKE (even with lid closed)" : "Mac sleeps normally", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(item(preventSleep ? "Allow Sleep" : "Prevent Sleep", #selector(togglePrevent), key: "s"))

        let display = item("Keep Display On", #selector(toggleDisplay))
        display.state = keepDisplayOn ? .on : .off
        menu.addItem(display)

        let battery = item("Allow Sleep When Battery ≤ \(lowBatteryLimit)%", #selector(toggleBatteryGuard))
        battery.state = batteryGuard ? .on : .off
        menu.addItem(battery)

        menu.addItem(.separator())

        let login = item("Open at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        if FileManager.default.fileExists(atPath: Power.sudoersPath) {
            menu.addItem(item("Remove pmset Permission…", #selector(removeHelper)))
        }

        menu.addItem(.separator())
        menu.addItem(item("Quit Coffeine", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func togglePrevent() { preventSleep.toggle(); apply() }
    @objc private func toggleDisplay() { keepDisplayOn.toggle(); apply() }
    @objc private func toggleBatteryGuard() { batteryGuard.toggle() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert("Open at Login", error.localizedDescription)
        }
    }

    @objc private func removeHelper() {
        preventSleep = false
        apply()
        Power.uninstallHelper()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Helpers

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    private func notifyLowBattery(_ pct: Int) {
        alert("Sleep allowed again", "Battery is at \(pct)%. Coffeine restored normal sleep.")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
