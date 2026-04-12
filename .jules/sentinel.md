## 2025-04-06 - Hardcoded API Key Exposure
**Vulnerability:** Found a hardcoded Google Gemini API key (`defaultApiKey`) in `SmartClipboard/GeminiService.swift`.
**Learning:** Hardcoded credentials in source code can easily be extracted by malicious actors or exposed if the repository is public. This is a critical security and billing risk.
**Prevention:** Remove hardcoded secrets from source code. Require users to provide their own API keys via settings or environment variables, or use a secure backend service to proxy API requests.

## 2025-04-06 - Sensitive Data Leak in Clipboard Manager
**Vulnerability:** ClipboardManager was blindly saving all copied data to a persistent SwiftData history database and making it available for AI searches, exposing passwords from password managers (1Password, Keychain) that mark their contents as transient/concealed.
**Learning:** Always check `NSPasteboard.types` for explicit security flags (`org.nspasteboard.TransientType`, `org.nspasteboard.ConcealedType`, `com.agilebits.onepassword`) before storing clipboard data, to respect user intent when copying sensitive credentials.
**Prevention:** Implement checks against known sensitive `PasteboardType` identifiers and short-circuit saving logic for those items.

## 2025-04-10 - DoS and URL Injection via Unsafe URLComponents
**Vulnerability:** Safe `URLComponents` construction was missing. Constructing `URLComponents(string:)!` with string interpolation directly risks crashing the application (Denial of Service) via forced unwrap, and creates potential for URL injection if unencoded or unexpected characters are present in injected variables.
**Learning:** Always use safe construction of URLs with user or external data (like `cleanModel`) by assigning individual properties (`scheme`, `host`, `path`, `queryItems`) onto a default `URLComponents()` instance instead of using interpolated string formatting.
**Prevention:** Avoid string interpolation with forced unwrapped `URL(string:)!` or `URLComponents(string:)!`. Construct URL components programmatically and let foundation handle encoding.
## 2024-05-18 - Prevent API Key Exposure via URL Parameters
**Vulnerability:** The Gemini API key was transmitted as a URL query parameter (`?key=...`).
**Learning:** Placing sensitive tokens like API keys in URLs exposes them to intermediate proxy logs, server access logs, and network monitoring tools in plain text, making them susceptible to theft.
**Prevention:** Always transmit sensitive tokens using secure HTTP headers (e.g., `x-goog-api-key`, `Authorization`) instead of URL query parameters.

## 2025-04-12 - Missing Clipboard Input Length Limit (DoS Risk)
**Vulnerability:** The clipboard manager (`SmartClipboard/ClipboardManager.swift`) was blindly saving all copied string data directly into a persistent SwiftData history database and caching it in memory without imposing any length limits.
**Learning:** Saving unbounded strings from the pasteboard (e.g., if a user copies a 500MB log file or an extremely large dataset) can lead to severe memory exhaustion, blocking the main thread, crashing the application (DoS), or corrupting the local persistent store. In Swift, calling `.count` on a `String` iterates through the whole string's grapheme clusters; instead, check `newString.utf8.count` for raw size limits efficiently.
**Prevention:** Always enforce a sensible maximum length limit (e.g., 100,000 characters) on user-provided input or clipboard data before saving it to a database or transmitting it to external APIs.
