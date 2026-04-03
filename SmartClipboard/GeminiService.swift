import Foundation

class GeminiService {
    // Default fallback API key if not provided by user
    private let defaultApiKey = "AIzaSyBn7A0OzD8hBlEKAkizBkVPJCap5b67IQ8" 

    func search(query: String, history: [ClipboardItem], apiKey: String?, modelName: String?) async throws -> [UUID] {
        let actualApiKey = (apiKey == nil || apiKey!.isEmpty) ? defaultApiKey : apiKey!
        let actualModel = (modelName == nil || modelName!.isEmpty) ? "gemini-1.5-flash" : modelName!
        
        // Remove 'models/' prefix if present
        let cleanModel = actualModel.replacingOccurrences(of: "models/", with: "")
        
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(cleanModel):generateContent?key=\(actualApiKey)")!
        
        // Convert our history to JSON so the AI can read it
        let historyJsonData = try JSONEncoder().encode(history)
        let historyString = String(data: historyJsonData, encoding: .utf8) ?? ""
        
        let prompt = """
        You are an AI assistant helping to search a user's clipboard history.
        The user has provided a search query: "\(query)"

        Here is the clipboard history (in JSON format):
        \(historyString)

        Return a JSON array of the "id"s of the clipboard items that match the user's query.
        Return ONLY the array of IDs.
        """
        
        let requestBody: [String: Any] = [
            "contents": [ ["parts": [["text": prompt]]] ],
            "generationConfig": [ "responseMimeType": "application/json" ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        // Parse the response back into Swift UUIDs
        struct GeminiResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]
        }
        
        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
        if let text = geminiResponse.candidates.first?.content.parts.first?.text,
           let textData = text.data(using: .utf8) {
            let ids = try JSONDecoder().decode([UUID].self, from: textData)
            return ids
        }
        
        return []
    }

    func fetchModels(apiKey: String?) async throws -> [String] {
        let actualApiKey = (apiKey == nil || apiKey!.isEmpty) ? defaultApiKey : apiKey!
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(actualApiKey)")!
        
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "GeminiService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch models"])
        }
        
        struct ModelsResponse: Decodable {
            struct Model: Decodable {
                let name: String
                let supportedGenerationMethods: [String]
            }
            let models: [Model]
        }
        
        let modelsResponse = try JSONDecoder().decode(ModelsResponse.self, from: data)
        // Filter for models that support generating content
        return modelsResponse.models
            .filter { $0.supportedGenerationMethods.contains("generateContent") }
            .map { $0.name.replacingOccurrences(of: "models/", with: "") }
            .sorted()
    }
}
