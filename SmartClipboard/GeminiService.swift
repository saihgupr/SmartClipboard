import Foundation

class GeminiService {
    enum GeminiError: LocalizedError {
        case missingApiKey

        var errorDescription: String? {
            switch self {
            case .missingApiKey:
                return "API key is missing. Please configure it in Settings."
            }
        }
    }

    struct SearchIntent {
        let textQuery: String?
        let startDate: Date?
        let endDate: Date?
        let semanticMatchIds: [UUID]?
    }

    func parseSearchIntent(query: String, history: [ClipboardItem], apiKey: String?, modelName: String?, searchDepth: Int = 200) async throws -> SearchIntent {
        guard let actualApiKey = apiKey, !actualApiKey.isEmpty else {
            throw GeminiError.missingApiKey
        }
        // Security: Defense-in-depth truncation to prevent token exhaustion / DoS
        let safeQuery = String(query.prefix(2000))
        let actualModel = (modelName == nil || modelName!.isEmpty) ? "gemini-2.5-flash" : modelName!
        
        let cleanModel = actualModel.replacingOccurrences(of: "models/", with: "")

        var components = URLComponents()
        components.scheme = "https"
        components.host = "generativelanguage.googleapis.com"
        components.path = "/v1beta/models"

        guard var url = components.url else {
            throw NSError(domain: "GeminiService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to construct valid URL."])
        }
        
        url = url.appendingPathComponent("\(cleanModel):generateContent")

        let formatter = ISO8601DateFormatter()
        let currentDateString = formatter.string(from: Date())
        
        // Take at most the specified number of items to keep prompt within limits
        let searchContext = history.prefix(searchDepth).map { "ID: \($0.id.uuidString)\nDate: \($0.timestamp)\nContent: \($0.content.prefix(500))" }.joined(separator: "\n---\n")
        
        let prompt = """
        You are an AI assistant parsing search queries for a clipboard manager.
        The current date and time is \(currentDateString).
        
        The user has provided a search query: "\(safeQuery)"

        Extract the user's intent into a JSON object with this exact structure:
        {
          "textQuery": "A literal string to find (e.g. 'Apple'), or null if the query is conceptual/categorical",
          "startDateISO": "ISO8601 formatted start date, or null",
          "endDateISO": "ISO8601 formatted end date, or null",
          "semanticMatchIds": ["ID1", "ID2"] // Populate this with IDs of matching items for semantic, conceptual, or categorical searches
        }

        Rules:
        - CATEGORICAL SEARCHES: If the user asks for "passwords", "website urls", "links", "emails", "addresses", "code", etc., DO NOT use textQuery. Instead, scan the "Recent Clipboard Items" below and put all matching IDs in semanticMatchIds.
        - DATE SEARCHES: If the user asks for a specific date (e.g., "July 27"), calculate the correct startDateISO and endDateISO.
        - LITERAL SEARCHES: If they mention a specific literal string (e.g. "Mouse cat"), put it in textQuery.
        - SEMANTIC SEARCHES: If the query is a description (e.g. "that thing about pizza"), find the matching items in the context below and return their IDs.
        
        Return ONLY the JSON object. Do not include markdown formatting.
        
        Recent Clipboard Items for Semantic Search:
        ---
        \(searchContext)
        ---
        """
        
        let safetySettings: [[String: String]] = [
            ["category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_NONE"],
            ["category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_NONE"],
            ["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_NONE"],
            ["category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_NONE"]
        ]
        
        let requestBody: [String: Any] = [
            "contents": [ ["parts": [["text": prompt]]] ],
            "generationConfig": [ "responseMimeType": "application/json" ],
            "safetySettings": safetySettings
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(actualApiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 15.0
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
        
        let geminiResponse: GeminiResponse
        do {
            geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
        } catch {
            let rawString = String(data: data, encoding: .utf8) ?? "Unable to decode response string"
            throw NSError(domain: "GeminiService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to decode Gemini response. Raw: \(rawString)"])
        }
        
        struct SearchIntentDTO: Decodable {
            let textQuery: String?
            let startDateISO: String?
            let endDateISO: String?
            let semanticMatchIds: [String]?
        }
        
        if let text = geminiResponse.candidates.first?.content.parts.first?.text {
            
            var cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanText.hasPrefix("```json") {
                cleanText.removeFirst(7)
            } else if cleanText.hasPrefix("```") {
                cleanText.removeFirst(3)
            }
            if cleanText.hasSuffix("```") {
                cleanText.removeLast(3)
            }
            cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let textData = cleanText.data(using: .utf8) {
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
                
                let uuids = dto.semanticMatchIds?.compactMap { UUID(uuidString: $0) }
                return SearchIntent(textQuery: dto.textQuery, startDate: start, endDate: end, semanticMatchIds: uuids)
            }
        }
        
        return SearchIntent(textQuery: query, startDate: nil, endDate: nil, semanticMatchIds: nil)
    }

    func fetchModels(apiKey: String?) async throws -> [String] {
        guard let actualApiKey = apiKey, !actualApiKey.isEmpty else {
            throw GeminiError.missingApiKey
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "generativelanguage.googleapis.com"
        components.path = "/v1beta/models"

        guard let url = components.url else {
            throw NSError(domain: "GeminiService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to construct valid URL."])
        }
        
        var request = URLRequest(url: url)
        request.addValue(actualApiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 15.0

        let (data, response) = try await URLSession.shared.data(for: request)
        
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
                
                // Keep standard Gemini models
                let isGemini = name.contains("gemini")
                
                guard isGemini else { return false }
                
                // Exclude specialized or internal-only keywords
                let exclusions = [
                    "robotics", "lyria", "computer-use", "image", "tts", 
                    "customtools", "banana", "deep-research", "lite",
                    "8b", "embedding", "aqa", "vision", "learnlm"
                ]
                
                for exclusion in exclusions {
                    if name.contains(exclusion) { return false }
                }
                
                return true
            }
            .sorted()
    }
}
