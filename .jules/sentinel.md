## 2025-04-06 - Hardcoded API Key Exposure
**Vulnerability:** Found a hardcoded Google Gemini API key (`defaultApiKey`) in `SmartClipboard/GeminiService.swift`.
**Learning:** Hardcoded credentials in source code can easily be extracted by malicious actors or exposed if the repository is public. This is a critical security and billing risk.
**Prevention:** Remove hardcoded secrets from source code. Require users to provide their own API keys via settings or environment variables, or use a secure backend service to proxy API requests.

## 2025-04-06 - Sensitive Data Leak in Clipboard Manager
**Vulnerability:** ClipboardManager was blindly saving all copied data to a persistent SwiftData history database and making it available for AI searches, exposing passwords from password managers (1Password, Keychain) that mark their contents as transient/concealed.
**Learning:** Always check `NSPasteboard.types` for explicit security flags (`org.nspasteboard.TransientType`, `org.nspasteboard.ConcealedType`, `com.agilebits.onepassword`) before storing clipboard data, to respect user intent when copying sensitive credentials.
**Prevention:** Implement checks against known sensitive `PasteboardType` identifiers and short-circuit saving logic for those items.

## 2025-04-09 - Unsafe URL Construction Denial of Service
**Vulnerability:** URL creation was done using string interpolation and force-unwrapping `URLComponents(string:)!`. This could cause the application to crash (Denial of Service) if user inputs contained unencoded special characters.
**Learning:** Force-unwrapping constructed URLs is unsafe. By using `URLComponents` and its discrete properties (`scheme`, `host`, `path`, `queryItems`), the foundation framework automatically handles proper encoding and avoids crashes from malformed inputs.
**Prevention:** Always construct URLs dynamically via `URLComponents` properties and safely unwrap the resulting `.url`.
