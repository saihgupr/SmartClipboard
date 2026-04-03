import Foundation

class GeminiService {
    // Default fallback API key if not provided by user
    private let defaultApiKey = "AIzaSyBn7A0OzD8hBlEKAkizBkVPJCap5b67IQ8" 

    struct SearchIntent {
        let textQuery: String?
        let startDate: Date?
        let endDate: Date?
    }

    func parseSearchIntent(query: String, apiKey: String?, modelName: String?) async throws -> SearchIntent {
        let actualApiKey = (apiKey == nil || apiKey!.isEmpty) ? defaultApiKey : apiKey!
        let actualModel = (modelName == nil || modelName!.isEmpty) ? "gemini-1.5-flash" : modelName!
        
        let cleanModel = actualModel.replacingOccurrences(of: "models/", with: "")
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(cleanModel):generateContent?key=\(actualApiKey)")!
        
        let formatter = ISO8601DateFormatter()
        let currentDateString = formatter.string(from: Date())
        
        let prompt = """
        You are an AI assistant parsing search queries for a clipboard manager.
        The current date and time is \(currentDateString).
        
        The user has provided a search query: "\(query)"

        Extract the user's intent into a JSON object with this exact structure:
        {
          "textQuery": "Extracted search string, or null if none",
          "startDateISO": "ISO8601 formatted start date, or null",
          "endDateISO": "ISO8601 formatted end date, or null"
        }

        Rules:
        - If the user asks for a specific date (e.g., "July 27"), calculate the correct startDateISO and endDateISO for that entire day.
        - If they specify time, narrow the range.
        - If they mention text (e.g. "Mouse cat"), put it in textQuery.
        - If they just search a word and no date, startDateISO and endDateISO should be null.
        - Return ONLY the JSON object. Do not include markdown formatting like ```json.
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
        
        struct SearchIntentDTO: Decodable {
            let textQuery: String?
            let startDateISO: String?
            let endDateISO: String?
        }
        
        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
        if let text = geminiResponse.candidates.first?.content.parts.first?.text,
           let textData = text.data(using: .utf8) {
            
            let dto = try JSONDecoder().decode(SearchIntentDTO.self, from: textData)
            
            var start: Date? = nil
            var end: Date? = nil
            let autoFormatter = ISO8601DateFormatter()
            autoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let looseFormatter = ISO8601DateFormatter()
            
            if let s = dto.startDateISO {
                start = autoFormatter.date(from: s) ?? looseFormatter.date(from: s)
            }
            if let e = dto.endDateISO {
                end = autoFormatter.date(from: e) ?? looseFormatter.date(from: e)
            }
            
            return SearchIntent(textQuery: dto.textQuery, startDate: start, endDate: end)
        }
        
        return SearchIntent(textQuery: query, startDate: nil, endDate: nil)
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
        
        // Filter for models that support generating content and are relevant for general app use
        return modelsResponse.models
            .filter { $0.supportedGenerationMethods.contains("generateContent") }
            .map { $0.name.replacingOccurrences(of: "models/", with: "") }
            .filter { modelName in
                let name = modelName.lowercased()
                
                // Keep standard Gemini and Gemma (Instruction Tuned) models
                let isGemini = name.contains("gemini")
                let isGemma = name.contains("gemma") && name.contains("-it")
                
                guard isGemini || isGemma else { return false }
                
                // Exclude specialized or internal-only keywords
                // We exclude things like robotics, lyria (music), and internal experiments (banana)
                let exclusions = [
                    "robotics", "lyria", "computer-use", "image", "tts", 
                    "customtools", "banana", "deep-research"
                ]
                
                for exclusion in exclusions {
                    if name.contains(exclusion) { return false }
                }
                
                return true
            }
            .sorted()
    }
}
