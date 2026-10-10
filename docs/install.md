# Install AudioPro

[English](install.md) · [Italiano](install.it.md)

1. Download `AudioPro-<version>-macOS.zip` from [GitHub Releases](https://github.com/CometaSensitiva/AudioPro/releases/latest).
2. Unzip it and move `AudioPro.app` to Applications.
3. Open the app. If macOS blocks it, close the alert and open **System Settings → Privacy & Security**.
4. Scroll to the security section and click **Open Anyway** beside the AudioPro message. Authenticate if macOS asks, then confirm **Open**.

![Privacy & Security, where macOS offers Open Anyway after blocking an app](screenshots/privacy-security.png)

The current release is not notarized. These steps follow [Apple's first-launch instructions](https://support.apple.com/en-us/102445). The exception applies to this app; no Terminal command is needed. The button is available after an opening attempt, usually for about one hour.

The app needs macOS 26 or later. Open **Trascrizione** to download Whisper Large v3 before the first transcription; subsequent transcriptions run locally.
