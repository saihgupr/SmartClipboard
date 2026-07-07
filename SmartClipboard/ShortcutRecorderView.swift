import SwiftUI
import AppKit

struct ShortcutRecorderView: View {
    @AppStorage("toggleUIKeyCode") private var keyCode: Int = 0
    @AppStorage("toggleUIModifiers") private var modifiersRaw: Int = 0
    
    @State private var isRecording = false
    @State private var eventMonitor: Any?
    
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Global Hotkey")
                    .font(.system(size: 14, weight: .medium))
                Text("Toggle the clipboard window from anywhere.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button(action: {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isRecording ? Color.blue.gradient : Color.primary.opacity(0.1).gradient)
                            .frame(minWidth: 140, minHeight: 36)
                        
                        HStack(spacing: 8) {
                            if isRecording {
                                Text("Listening...")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                            } else if keyCode == 0 && modifiersRaw == 0 {
                                Text("Record Shortcut")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                            } else {
                                Text(shortcutString)
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(isRecording ? .white : .primary)
                            }
                            
                            if isRecording {
                                Image(systemName: "record.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                
                if keyCode != 0 || modifiersRaw != 0 {
                    Button(action: clearShortcut) {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.secondary)
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear Shortcut")
                    .help("Clear Shortcut")
                }
            }
        }
        .onDisappear {
            stopRecording()
        }
    }
    
    private var shortcutString: String {
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(modifiersRaw))
        var str = ""
        if modifiers.contains(.control) { str += "⌃" }
        if modifiers.contains(.option) { str += "⌥" }
        if modifiers.contains(.shift) { str += "⇧" }
        if modifiers.contains(.command) { str += "⌘" }
        
        str += " " + keyString(for: keyCode)
        return str
    }
    
    private func keyString(for keyCode: Int) -> String {
        switch keyCode {
        case 0x31: return "Space"
        case 0x24: return "Enter"
        case 0x00: return "A"
        case 0x01: return "S"
        case 0x02: return "D"
        case 0x03: return "F"
        case 0x04: return "H"
        case 0x05: return "G"
        case 0x06: return "Z"
        case 0x07: return "X"
        case 0x08: return "C"
        case 0x09: return "V"
        case 0x0B: return "B"
        case 0x0C: return "Q"
        case 0x0D: return "W"
        case 0x0E: return "E"
        case 0x0F: return "R"
        case 0x10: return "Y"
        case 0x11: return "T"
        case 0x12: return "1"
        case 0x13: return "2"
        case 0x14: return "3"
        case 0x15: return "4"
        case 0x16: return "6"
        case 0x17: return "5"
        case 0x18: return "="
        case 0x19: return "9"
        case 0x1A: return "7"
        case 0x1B: return "-"
        case 0x1C: return "8"
        case 0x1D: return "0"
        case 0x1E: return "]"
        case 0x1F: return "O"
        case 0x20: return "U"
        case 0x21: return "["
        case 0x22: return "I"
        case 0x23: return "P"
        case 0x25: return "L"
        case 0x26: return "J"
        case 0x27: return "'"
        case 0x28: return "K"
        case 0x29: return ";"
        case 0x2A: return "\\"
        case 0x2B: return ","
        case 0x2C: return "/"
        case 0x2D: return "N"
        case 0x2E: return "M"
        case 0x2F: return "."
        case 0x32: return "`"
        default: return "\(keyCode)"
        }
    }
    
    private func startRecording() {
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let forbiddenKeys = [0x35] // Escape
            if forbiddenKeys.contains(Int(event.keyCode)) {
                stopRecording()
                return nil
            }
            
            self.keyCode = Int(event.keyCode)
            self.modifiersRaw = Int(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
            
            GlobalHotkeyManager.shared.registerToggleUIHotkey(
                keyCode: self.keyCode,
                modifiers: NSEvent.ModifierFlags(rawValue: UInt(self.modifiersRaw))
            )
            
            stopRecording()
            return nil
        }
    }
    
    private func stopRecording() {
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    private func clearShortcut() {
        keyCode = 0
        modifiersRaw = 0
        GlobalHotkeyManager.shared.uninstall()
        GlobalHotkeyManager.shared.install()
    }
}
