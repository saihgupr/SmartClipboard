import Foundation
import SwiftData
import AppKit

@MainActor
class ImportManager: ObservableObject {
    private let modelContext: ModelContext
    
    @Published var isImporting = false
    @Published var importMessage: String?
    @Published var lastImportCount: Int = 0
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func importFromAlfred() {
        isImporting = true
        importMessage = "Locating Alfred database..."
        
        let home = FileManager.default.homeDirectoryForCurrentUser
        let alfredDbPath = home.appendingPathComponent("Library/Application Support/Alfred/Databases/clipboard.alfdb").path
        
        guard FileManager.default.fileExists(atPath: alfredDbPath) else {
            importMessage = "Alfred clipboard database not found."
            isImporting = false
            return
        }
        
        importMessage = "Reading Alfred history..."
        
        let task = Process()
        task.launchPath = "/usr/bin/sqlite3"
        task.arguments = [alfredDbPath, "-json", "SELECT item, ts FROM clipboard WHERE dataType = 0 ORDER BY ts DESC;"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            
            struct AlfredItem: Codable {
                let item: String
                let ts: Double
            }
            
            let decoder = JSONDecoder()
            let items = try decoder.decode([AlfredItem].self, from: data)
            
            importMessage = "Importing \(items.count) items..."
            var count = 0
            
            // Pre-fetch all existing contents for O(1) checks
            let descriptor = FetchDescriptor<ClipboardItem>()
            let existingItems = try modelContext.fetch(descriptor)
            var existingContent = Set(existingItems.map { $0.content })
            
            for alfredItem in items {
                let content = alfredItem.item
                if content.isEmpty { continue }
                
                if !existingContent.contains(content) {
                    // Alfred timestamp is in seconds since Mac reference date (Jan 1, 2001)
                    let date = Date(timeIntervalSinceReferenceDate: alfredItem.ts)
                    let newItem = ClipboardItem(content: content, timestamp: date)
                    modelContext.insert(newItem)
                    existingContent.insert(content)
                    count += 1
                }
            }
            
            try modelContext.save()
            lastImportCount = count
            importMessage = "Successfully imported \(count) items from Alfred."
            
        } catch {
            importMessage = "Error importing from Alfred: \(error.localizedDescription)"
        }
        
        isImporting = false
    }
    
    func importFromKeyboardMaestro() {
        isImporting = true
        importMessage = "Locating Keyboard Maestro history..."
        
        let home = FileManager.default.homeDirectoryForCurrentUser
        let kmPlistPath = home.appendingPathComponent("Library/Application Support/Keyboard Maestro/Keyboard Maestro Clipboard History.plist")
        
        guard FileManager.default.fileExists(atPath: kmPlistPath.path) else {
            importMessage = "Keyboard Maestro clipboard history not found."
            isImporting = false
            return
        }
        
        do {
            let data = try Data(contentsOf: kmPlistPath)
            guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [[String: Any]] else {
                importMessage = "Failed to parse Keyboard Maestro data."
                isImporting = false
                return
            }
            
            importMessage = "Importing \(plist.count) items..."
            var count = 0
            
            // Pre-fetch existing for speed
            let descriptor = FetchDescriptor<ClipboardItem>()
            let existingItems = try modelContext.fetch(descriptor)
            var existingContent = Set(existingItems.map { $0.content })
            
            for dict in plist {
                guard let dataArray = dict["Clipboard"] as? [[String: Any]] else { continue }
                
                // Find plain text content
                var textContent: String?
                for dataDict in dataArray {
                    if let key = dataDict["Key"] as? String,
                       (key == "public.utf8-plain-text" || key == "com.apple.traditional-mac-plain-text" || key == "public.utf16-plain-text"),
                       let data = dataDict["Data"] as? Data {
                        
                        if key == "public.utf16-plain-text" {
                            textContent = String(data: data, encoding: .utf16)
                        } else {
                            textContent = String(data: data, encoding: .utf8)
                        }
                        
                        if textContent != nil && !textContent!.isEmpty {
                            break
                        }
                    }
                }
                
                guard let content = textContent, !content.isEmpty else { continue }
                
                if !existingContent.contains(content) {
                    let date = dict["Date"] as? Date ?? Date()
                    let newItem = ClipboardItem(content: content, timestamp: date)
                    modelContext.insert(newItem)
                    existingContent.insert(content)
                    count += 1
                }
            }
            
            try modelContext.save()
            lastImportCount = count
            importMessage = "Successfully imported \(count) items from Keyboard Maestro."
            
        } catch {
            importMessage = "Error importing from Keyboard Maestro: \(error.localizedDescription)"
        }
        
        isImporting = false
    }
    
    func importFromBetterTouchTool() {
        isImporting = true
        importMessage = "Locating BetterTouchTool database..."
        
        let home = FileManager.default.homeDirectoryForCurrentUser
        let bttDir = home.appendingPathComponent("Library/Application Support/BetterTouchTool")
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: bttDir, includingPropertiesForKeys: [.fileSizeKey], options: [])
            let bttDbFiles = files.filter { 
                let name = $0.lastPathComponent
                return name.hasPrefix("BTTClipboardManager") && 
                       name.contains("sqlite") && 
                       !name.contains("-shm") && 
                       !name.contains("-wal")
            }
            
            // Find the largest file, which is likely the active history
            var largestFile: URL?
            var largestSize: Int = -1
            
            for file in bttDbFiles {
                if let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                    if size > largestSize {
                        largestSize = size
                        largestFile = file
                    }
                }
            }
            
            guard let bttDbPath = largestFile?.path else {
                importMessage = "BetterTouchTool clipboard database not found."
                isImporting = false
                return
            }
            
            importMessage = "Reading BetterTouchTool history..."
            
            let task = Process()
            task.launchPath = "/usr/bin/sqlite3"
            task.arguments = [bttDbPath, "-json", "SELECT ZPREVIEWTEXT as item, ZDATE as ts FROM ZBTTCLIP WHERE ZPREVIEWTEXT IS NOT NULL AND ZPREVIEWTEXT != '' ORDER BY ZDATE DESC;"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            
            struct BTTItem: Codable {
                let item: String
                let ts: Double
            }
            
            if data.isEmpty {
                lastImportCount = 0
                importMessage = "No clipboard items found in BetterTouchTool."
                isImporting = false
                return
            }
            
            let decoder = JSONDecoder()
            let items: [BTTItem]
            do {
                items = try decoder.decode([BTTItem].self, from: data)
            } catch {
                // If decoding fails, it might be because it's not an array
                importMessage = "Failed to parse BetterTouchTool data."
                isImporting = false
                return
            }
            
            importMessage = "Importing \(items.count) items from BTT..."
            var count = 0
            
            let descriptor = FetchDescriptor<ClipboardItem>()
            let existingItems = try modelContext.fetch(descriptor)
            var existingContent = Set(existingItems.map { $0.content })
            
            for bttItem in items {
                let content = bttItem.item
                if content.isEmpty { continue }
                
                if !existingContent.contains(content) {
                    let date = Date(timeIntervalSinceReferenceDate: bttItem.ts)
                    let newItem = ClipboardItem(content: content, timestamp: date)
                    modelContext.insert(newItem)
                    existingContent.insert(content)
                    count += 1
                }
            }
            
            try modelContext.save()
            lastImportCount = count
            importMessage = "Successfully imported \(count) items from BetterTouchTool."
            
        } catch {
            importMessage = "Error importing from BetterTouchTool: \(error.localizedDescription)"
        }
        
        isImporting = false
    }
}
