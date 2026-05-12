@echo off
echo Building Android AAR...
call flutter build aar --no-debug --no-profile
echo.
echo ========================================================
echo AAR build complete.
echo Location: build\host\outputs\repo
echo ========================================================
echo.
echo To publish to JitPack:
echo 1. Ensure your project is on GitHub.
echo 2. Add jitpack.yml to your root.
echo 3. Create a release tag.
echo 4. Go to jitpack.io and enter your repo URL.
pause
