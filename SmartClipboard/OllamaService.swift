import Foundation

class OllamaService {
    static let shared = OllamaService()
    
    enum OllamaError: LocalizedError {
        case invalidURL
        case requestFailed(String)
        case decodingFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "The Ollama API URL is invalid."
            case .requestFailed(let details):
                return "Ollama request failed: \(details)"
            case .decodingFailed(let details):
                return "Failed to parse Ollama response: \(details)"
            }
        }
    }
    
    struct SearchIntent {
        let textQuery: String?
        let startDate: Date?
        let endDate: Date?
        let semanticMatchIds: [UUID]?
    }
    
    /// Parses the search query against the clipboard context using a local model in Ollama.
    func parseSearchIntent(
        query: String,
        history: [ClipboardItem],
        baseURL: String,
        modelName: String,
        searchDepth: Int = 200
    ) async throws -> SearchIntent {
        let cleanQuery = String(query.prefix(2000))
        
        // Build the OpenAI-compatible chat completion URL
        guard var url = URL(string: baseURL) else {
            throw OllamaError.invalidURL
        }
        url = url.appendingPathComponent("v1/chat/completions")
        
        let formatter = ISO8601DateFormatter()
        let currentDateString = formatter.string(from: Date())
        
        let systemPrompt = """
        You are a search query classifier for a clipboard manager.
        The current date/time is \(currentDateString).
        
        Your task is to parse the search query and return a JSON object with the following structure:
        {
          "category": "url" | "code" | "text" | "date",
          "keywords": ["word1", "word2"], // list of search terms, synonyms, or related concepts (split phrases into individual words)
          "startDateISO": "ISO8601 formatted start date, or null",
          "endDateISO": "ISO8601 formatted end date, or null"
        }

        Rules:
        1. If the query is looking for websites, links, or urls, set category to "url".
        2. If the query is looking for programming code, scripts, or terminal commands, set category to "code".
        3. If the query mentions a date or time range (e.g. "yesterday", "today", "last week"), set category to "date" and compute the correct startDateISO and endDateISO boundaries.
        4. If the query is a general text search (e.g. "music artist"), set category to "text". List synonyms and related terms in the "keywords" array to expand the search (e.g. for "music artist" output ["music", "artist", "singer", "band", "song", "jazz", "blues", "rock"]).
        5. Return ONLY the JSON object. Do not include markdown blocks or introductory text.
        """
        
        let userContent = "Search Query: \"\(cleanQuery)\""
        
        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0.0
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8.0
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OllamaError.requestFailed(error.localizedDescription)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.requestFailed("No Response from local server.")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown server error."
            throw OllamaError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }
        
        struct OpenAIResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }
        
        let openAIResponse: OpenAIResponse
        do {
            openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        } catch {
            let rawString = String(data: data, encoding: .utf8) ?? "Unable to decode response string"
            throw OllamaError.decodingFailed("Failed to parse response. Raw: \(rawString)")
        }
        
        guard let contentString = openAIResponse.choices.first?.message.content else {
            throw OllamaError.decodingFailed("Empty content returned from the model.")
        }
        
        print("[Ollama Service] Raw response from model: \(contentString)")
        
        var cleanText = contentString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanText.hasPrefix("```json") {
            cleanText.removeFirst(7)
        } else if cleanText.hasPrefix("```") {
            cleanText.removeFirst(3)
        }
        if cleanText.hasSuffix("```") {
            cleanText.removeLast(3)
        }
        cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let textData = cleanText.data(using: .utf8) else {
            throw OllamaError.decodingFailed("Response format is not UTF-8.")
        }
        
        struct SearchIntentDTO: Decodable {
            let category: String?
            let keywords: [String]?
            let startDateISO: String?
            let endDateISO: String?
        }
        
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
        
        // Swift-side Local Filtering based on LLM Classification
        var matchedIds: [UUID] = []
        let category = dto.category?.lowercased() ?? "text"
        
        if category == "url" {
            // Match URLs
            matchedIds = history.filter { item in
                let content = item.content.lowercased()
                return content.contains("http://") || 
                       content.contains("https://") || 
                       content.contains("www.") ||
                       content.range(of: #"[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}"#, options: .regularExpression) != nil
            }.map { $0.id }
        } else if category == "code" {
            // Match Code
            let codeKeywords = ["func ", "var ", "let ", "import ", "class ", "struct ", "def ", "print(", "console.log", "npm ", "pip ", "git ", "void ", "const ", "await ", "fn ", "impl ", "<html>", "</div>", "struct"]
            matchedIds = history.filter { item in
                let content = item.content
                let hasBrackets = content.contains("{") && content.contains("}")
                let hasIndentation = content.contains("    ") || content.contains("\t")
                let hasCodeKeyword = codeKeywords.contains { kw in
                    content.localizedCaseInsensitiveContains(kw)
                }
                return (hasBrackets && hasIndentation) || hasCodeKeyword
            }.map { $0.id }
        } else {
            // Text or Date matching
            let searchTerms = dto.keywords ?? []
            if !searchTerms.isEmpty {
                matchedIds = history.filter { item in
                    searchTerms.contains { term in
                        item.content.localizedCaseInsensitiveContains(term)
                    }
                }.map { $0.id }
            } else {
                matchedIds = history.filter { item in
                    item.content.localizedCaseInsensitiveContains(cleanQuery)
                }.map { $0.id }
            }
        }
        
        return SearchIntent(textQuery: nil, startDate: start, endDate: end, semanticMatchIds: matchedIds)
    }
    
    /// Fetches all active model tags running locally in the Ollama instance.
    func fetchModels(baseURL: String) async throws -> [String] {
        guard var url = URL(string: baseURL) else {
            throw OllamaError.invalidURL
        }
        url = url.appendingPathComponent("v1/models")
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OllamaError.requestFailed("Failed to connect to local Ollama server.")
        }
        
        struct OpenAIModelsResponse: Decodable {
            struct Model: Decodable {
                let id: String
            }
            let data: [Model]
        }
        
        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return decoded.data.map { $0.id }.sorted()
    }
}
