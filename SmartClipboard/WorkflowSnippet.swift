import Foundation
import SwiftData

@Model
final class WorkflowSnippet: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var trigger: String // Stored with leading slash, e.g. "/100answers"
    var content: String
    var timestamp: Date
    var isBuiltIn: Bool
    
    init(id: UUID = UUID(), title: String, trigger: String, content: String, timestamp: Date = Date(), isBuiltIn: Bool = false) {
        self.id = id
        self.title = title
        let formattedTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        self.trigger = formattedTrigger.hasPrefix("/") ? formattedTrigger : "/\(formattedTrigger)"
        self.content = content
        self.timestamp = timestamp
        self.isBuiltIn = isBuiltIn
    }
    
    /// Default preset workflows provided out of the box
    static var defaultPresets: [WorkflowSnippet] {
        [
            WorkflowSnippet(
                title: "100 Answers & Pick Best",
                trigger: "/100answers",
                content: "Generate 100 distinct and creative answers/solutions for the following requirement or problem, then critically evaluate them and pick the top 3 best answers with detailed justification for each:",
                isBuiltIn: true
            ),
            WorkflowSnippet(
                title: "Code Review",
                trigger: "/codereview",
                content: "Please review the following code for bugs, edge cases, security vulnerabilities, performance bottlenecks, and readability improvements:",
                isBuiltIn: true
            ),
            WorkflowSnippet(
                title: "Refactor & Clean Code",
                trigger: "/refactor",
                content: "Refactor the following code to adhere to best practices, clean architecture, and modern idioms without changing its functional behavior:",
                isBuiltIn: true
            ),
            WorkflowSnippet(
                title: "Explain Code or Concept",
                trigger: "/explain",
                content: "Explain the following concept or code in clear, step-by-step detail suitable for a developer:",
                isBuiltIn: true
            ),
            WorkflowSnippet(
                title: "Summarize Text",
                trigger: "/summarize",
                content: "Summarize the following text into clear key takeaways, action items, and main points:",
                isBuiltIn: true
            ),
            WorkflowSnippet(
                title: "Fix Bugs & Errors",
                trigger: "/fixbugs",
                content: "Analyze the following code snippet and error output, identify the root cause of the issue, and provide the exact corrected code solution:",
                isBuiltIn: true
            )
        ]
    }
}
