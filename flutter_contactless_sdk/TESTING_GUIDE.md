# Local Testing Guide

---

## Android Testing

### Prerequisites
- **Physical Android Phone** with NFC hardware (no Simulator support).
- **Enable NFC**: Settings → Connected Devices → Connection Preferences → NFC.
- **Developer Options**: Enable "USB Debugging".
- Connect via USB and run `adb devices` to verify.

### Run the Example App
```bash
cd example
flutter clean
flutter pub get
flutter run
```

### What to Expect
1. The screen shows whether NFC hardware is detected.
2. Tap **"Start Payment Session"** to trigger a real card read via `nfc_manager`.
3. Hold an EMV card against the back of the phone.

### Troubleshooting
- **Gradle Errors**: Ensure `example/android/local.properties` contains the correct `flutter.sdk` path.
- **NFC Not Found**: Verify the phone has NFC hardware and it is turned ON.
- **Permission Denied**: The manifest already includes `<uses-permission android:name="android.permission.NFC" />`.

---

## iOS Testing

### Prerequisites
- **Physical iPhone 7 or newer** — CoreNFC does NOT work in the iOS Simulator.
- **Apple Developer Account** with an active paid membership (required for NFC entitlement).
- **macOS machine with Xcode 12+** to build and sign the app.

### Step 1 — Enable NFC in the Apple Developer Portal
1. Go to [developer.apple.com](https://developer.apple.com) → Certificates, Identifiers & Profiles.
2. Select your **App ID** (or create one matching your bundle ID).
3. Enable the **"NFC Tag Reading"** capability.
4. Regenerate and download your provisioning profile.

### Step 2 — Enable NFC Capability in Xcode
1. Open `example/ios/Runner.xcworkspace` in Xcode.
2. Select the **Runner** target → **Signing & Capabilities** tab.
3. Click **"+ Capability"** and add **"Near Field Communication Tag Reading"**.
4. Xcode will automatically link `Runner.entitlements` (already created at
   `ios/Runner/Runner.entitlements`) and add the entitlement key.

### Step 3 — Verify `Info.plist` Entries
The following keys are already present in `ios/Runner/Info.plist` — verify they exist:
```xml
<key>NFCReaderUsageDescription</key>
<string>This app uses NFC to read your EMV payment card for contactless payments.</string>

<key>com.apple.developer.nfc.readersession.iso7816.select-identifiers</key>
<array>
    <string>A0000000041010</string>  <!-- Mastercard -->
    <string>A0000000031010</string>  <!-- Visa -->
    <!-- ... and more -->
</array>
```

### Step 4 — Run the Example App on Device
```bash
cd example
flutter clean
flutter pub get
flutter run --release   # or open Xcode and Run (⌘R)
```

### What to Expect
1. The screen shows NFC availability (`true` on iPhone 7+).
2. Tap **"Read Card Details"** — the native iOS NFC modal sheet appears.
3. Hold an EMV card near the **top** of the iPhone (where the NFC antenna is).
4. The modal closes automatically and card data (PAN, expiry, cardholder name, cryptogram) is displayed.

### Troubleshooting
| Symptom | Cause | Fix |
|---|---|---|
| NFC sheet never appears | Missing entitlement | Add capability in Xcode (Step 2) |
| App crashes on NFC call | Missing `NFCReaderUsageDescription` | Add key to `Info.plist` |
| "Unsupported card type" error | Card AID not in `Info.plist` list | Add the AID to `com.apple.developer.nfc.readersession.iso7816.select-identifiers` |
| `NFC_UNAVAILABLE` error | Running on Simulator or iPhone 6s or older | Use a real iPhone 7 or newer |
| Session invalidated immediately | Provisioning profile mismatch | Regenerate profile after enabling NFC in Dev Portal |

