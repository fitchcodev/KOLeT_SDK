# Distribution & Hosting Guide

This guide explains how to host and consume the `flutter_contactless_sdk` in a React Native environment using Maven (JitPack) and CocoaPods.

## 1. Android Hosting (via JitPack)

### Setup
Ensure your `jitpack.yml` is present in the root. This is already created for you.

### Publishing
1. Push this repository to GitHub.
2. Create a new Release (e.g., `v1.0.0`).
3. Visit [jitpack.io](https://jitpack.io) and search for `your-username/flutter_contactless_sdk`.
4. The AAR will be available at `com.github.your-username:flutter_contactless_sdk:1.0.0`.

### Consuming in RN Wrapper
In `react-native-contactless/android/build.gradle`:
```gradle
repositories {
    maven { url 'https://jitpack.io' }
}

dependencies {
    implementation 'com.github.your-username:flutter_contactless_sdk:main-SNAPSHOT'
}
```

## 2. iOS Hosting (via CocoaPods)

### Setup
iOS requires a "Spec Repo" or a direct URL to the `.xcframework`.

### Publishing
1. Run `./build_xcframework.sh`.
2. Zip the resulting `build/ios/framework/Release/ContactlessPlugin.xcframework`.
3. Upload the zip to GitHub Releases or a CDN.
4. Update your `flutter_contactless_sdk.podspec`:
```ruby
s.source = { :http => 'https://github.com/user/repo/releases/download/v1.0.0/ContactlessPlugin.xcframework.zip' }
s.vendored_frameworks = 'ContactlessPlugin.xcframework'
```

### Consuming in RN Wrapper
In `react-native-contactless/ios/Podfile`:
```ruby
pod 'flutter_contactless_sdk', :git => 'https://github.com/your-repo/flutter_contactless_sdk.git', :tag => 'v1.0.0'
```

---

## 3. React Native Integration Flow

1. **Repo 1 (Flutter SDK)**: Build and publish artifacts.
2. **Repo 2 (RN Wrapper)**: Link to the artifacts in `build.gradle` and `Podfile`.
3. **Consumer App**: `npm install react-native-contactless`.
