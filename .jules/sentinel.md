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
