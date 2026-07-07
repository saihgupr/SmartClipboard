import Foundation
import Combine

@MainActor
class UpdateManager: ObservableObject {
    static let shared = UpdateManager()
    
    @Published var isUpdateAvailable = false
    @Published var latestVersionString = ""
    @Published var latestReleaseURL: URL?
    @Published var isChecking = false
    @Published var checkStatus: UpdateStatus = .idle
    
    enum UpdateStatus: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable(version: String, url: URL)
        case failed(error: String)
    }
    
    private init() {}
    
    func checkForUpdates(manually: Bool = false) {
        guard !isChecking else { return }
        
        isChecking = true
        checkStatus = .checking
        
        guard let url = URL(string: "https://api.github.com/repos/saihgupr/SmartClipboard/releases/latest") else {
            isChecking = false
            checkStatus = .failed(error: "Invalid URL configuration")
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("SmartClipboard-App", forHTTPHeaderField: "User-Agent")
        
        // Disable caching to get fresh releases
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor in
                guard let self = self else { return }
                self.isChecking = false
                
                if let error = error {
                    self.checkStatus = .failed(error: error.localizedDescription)
                    return
                }
                
                guard let data = data else {
                    self.checkStatus = .failed(error: "No response data received")
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let tagName = json["tag_name"] as? String,
                       let htmlURLString = json["html_url"] as? String,
                       let htmlURL = URL(string: htmlURLString) {
                        
                        let remoteVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                        
                        if remoteVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                            self.isUpdateAvailable = true
                            self.latestVersionString = tagName
                            self.latestReleaseURL = htmlURL
                            self.checkStatus = .updateAvailable(version: tagName, url: htmlURL)
                        } else {
                            self.isUpdateAvailable = false
                            self.checkStatus = .upToDate
                        }
                    } else {
                        // Check if it's a rate limit or API error
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let message = json["message"] as? String {
                            self.checkStatus = .failed(error: message)
                        } else {
                            self.checkStatus = .failed(error: "Could not parse release information")
                        }
                    }
                } catch {
                    self.checkStatus = .failed(error: "Failed to read release data: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
}
