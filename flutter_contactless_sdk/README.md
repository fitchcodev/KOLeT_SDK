# Flutter Contactless SDK

A high-performance SDK for contactless payments (NFC/EMV) built with Flutter and designed for polyglot deployment (Flutter, React Native, Native).

## Features

- **NFC Session Management**: Hardware-optimized NFC reader for iOS (CoreNFC) and Android.
- **EMV State Machine**: Built-in logic for processing EMV cards and generating cryptograms.
- **Hardware Security**: Integrated with Android KeyStore and iOS Secure Enclave for key management.
- **RN Ready**: Built-in support for generating AAR and XCFramework for React Native integration.

## Folder Structure

```
flutter_contactless_sdk/
├── lib/
│   ├── contactless_sdk.dart            # Public API entry point
│   └── src/
│       ├── nfc/                        # NFC manager and handlers
│       ├── payment/                    # EMV processing logic
│       ├── security/                   # Key store and signing
│       └── models/                     # Data models
├── android/                            # Native Android bridge (Kotlin)
├── ios/                                # Native iOS bridge (Swift)
├── build_aar.bat                      # Build script for Android (AAR)
├── build_xcframework.sh                # Build script for iOS (XCFramework)
└── DISTRIBUTION.md                     # Hosting & Publishing guide
```

## Getting Started

1. **Initialize the SDK**:
   ```dart
   import 'package:flutter_contactless_sdk/contactless_sdk.dart';

   await ContactlessSDK.initialize(apiKey: 'YOUR_API_KEY');
   ```

2. **Start a Payment**:
   ```dart
   final result = await ContactlessSDK.startPayment(PaymentRequest(
     amount: 100.0,
     currency: 'USD',
     merchantId: 'M123',
     terminalId: 'T456',
   ));
   ```

## React Native Integration

To integrate this into a React Native app, refer to the [DISTRIBUTION.md](./DISTRIBUTION.md) for hosting on JitPack and CocoaPods.
