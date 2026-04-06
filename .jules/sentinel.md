## 2025-04-06 - Hardcoded API Key Exposure
**Vulnerability:** Found a hardcoded Google Gemini API key (`defaultApiKey`) in `SmartClipboard/GeminiService.swift`.
**Learning:** Hardcoded credentials in source code can easily be extracted by malicious actors or exposed if the repository is public. This is a critical security and billing risk.
**Prevention:** Remove hardcoded secrets from source code. Require users to provide their own API keys via settings or environment variables, or use a secure backend service to proxy API requests.
