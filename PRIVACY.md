## 🔒 Privacy

This fork is designed for a self-hosted Companion service:

- **Server-backed history:** Chat transcripts are stored by the configured Companion server and cached locally for responsive and offline access.
- **No iCloud chat storage:** This fork does not use CloudKit or iCloud to store conversation history.
- **No third-party analytics:** Companion Connect does not include analytics or advertising data collection.
- **Protected credentials:** The Companion API key is stored in Apple Keychain and sent only to the configured service endpoint.
- **Transport responsibility:** Use HTTPS or a trusted private network; plain HTTP does not encrypt API keys or conversation data in transit.

Your privacy and control over your data are fundamental principles behind Companion Connect.
