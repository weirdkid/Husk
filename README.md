# About This Fork
> This fork will be more specialized for talking to local (same device or LAN) AI chat services. It will be intentionally fairly bare-bones, since it is intended to be a simple front-end chat client for my local AI service that provides tools, personality, memory, etc on the server. This fork will likely diverge from the orginal Husk app significantly, and I'll probably change the name of the project and app at some point.

The upstream project README follows below. A huge thank you to Nathan1258 for the leg up.


# Husk

> Husk is an open-source, OpenAI and Ollama-compatible app designed for iOS. It provides an elegant, native interface for interacting with privately hosted models. Husk aims to deliver a seamless, unfiltered, and secure multimodal experience across your Apple devices.

![License](https://img.shields.io/github/license/nathan1258/husk)

## App Store

[<img src="https://github.com/Nathan1258/Husk/blob/main/assets/app-store.png">](https://apps.apple.com/gb/app/husk/id6746637464)

## 🚀 Features

- ✨ Native client for the self-hosted Companion service, with server-backed chat history and an offline local cache
- 📎 Support for text-based attachments (image support for multimodal models coming soon)
- ⚙️ Highly customizable with names, system prompts, and personalization options

## 🖼️ Demo

![Screenshot 1](https://github.com/Nathan1258/Husk/blob/main/assets/Husk%20-%20Generic%20Screenshot%20-%201.png)
![Screenshot 2](https://github.com/Nathan1258/Husk/blob/main/assets/Husk%20-%20Generic%20Screenshot%20-%202.png)

## 💸 Pricing & DIY Install

The parent Husk project is a **paid app** on the [App Store](#app-store). The original author asks that you buy to help pay for his work on it. 

That said, Husk is also **fully open-source**, so if you prefer, you're welcome to compile and install it yourself for free.

### 🛠️ Build It Yourself (Free Option)

If you'd rather not purchase Husk from the App Store, here's how you can install it manually:

1. **Clone the Repository**  
   ```bash
   git clone https://github.com/Nathan1258/Husk.git
   cd Husk
   ```

2. **Open in Xcode**  
   Open the `Husk.xcodeproj` file in Xcode.

3. **Set Your Team**  
   - Go to the **project settings** in Xcode.
   - Under **Signing & Capabilities**, set your **Apple Developer account** (a free account works for personal builds).

4. **Build & Run**  
   - Select your **iOS device** as the target.
   - Hit **Run (⌘R)** to build and install the app on your device.

> ⚠️ You may need to trust your developer certificate on the device under **Settings → General → Device Management** before launching the app.

This option gives you full access to Husk at no cost, and allows you to explore or contribute to the project freely.

## 🔒 Privacy

This fork is designed for a self-hosted Companion service:

- **Server-backed history:** Chat transcripts are stored by the configured Companion server and cached locally for responsive and offline access.
- **No iCloud chat storage:** This fork does not use CloudKit or iCloud to store conversation history.
- **No third-party analytics:** Husk does not include analytics or advertising data collection.
- **Protected credentials:** The Companion API key is stored in Apple Keychain and sent only to the configured service endpoint.
- **Transport responsibility:** Use HTTPS or a trusted private network; plain HTTP does not encrypt API keys or conversation data in transit.

Your privacy and control over your data are fundamental principles behind Husk.

## 🙏 Support

If you enjoy using Husk or find it helpful, here are a few ways you can support the project:

- ⭐️ **Star this repository** on GitHub to help others discover Husk.
- 🐞 **Report issues** or suggest features by opening an issue [here](https://github.com/Nathan1258/Husk/issues).
- 💬 **Join the discussion** or ask questions in the GitHub Discussions or community forums.
- 📢 **Share Husk** with friends or on social media to spread the word.

If you're needing any support then please [contact me](mailto:husk-app@pm.com).

## 🙏 Acknowledgements

Special thanks to the maintainers of the following open-source projects that make Husk possible:

- [SwiftUI Markdown](https://github.com/gonzalezreal/swift-markdown-ui) – for rendering Markdown beautifully in SwiftUI.
