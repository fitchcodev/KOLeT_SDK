#!/bin/bash
echo "Building iOS XCFramework..."

# Clean build directory
rm -rf build/ios/framework

# Build for Simulator and Device
flutter build ios-framework --no-debug --no-profile --output=build/ios/framework

echo "========================================================"
echo "XCFramework build complete."
echo "Location: build/ios/framework/Release"
echo "========================================================"
echo ""
echo "To publish to CocoaPods:"
echo "1. Upload the ContactlessSDK.xcframework (zipped) to a CDN (e.g. GitHub Releases)."
echo "2. Update your .podspec to point to the remote source URL."
echo "3. Push the podspec to your private/public spec repo."
