#!/bin/sh
# Xcode Cloud hook: runs after the clone, before xcodebuild.
# Xcode Cloud's build number (CI_BUILD_NUMBER) is the one App Store Connect and TestFlight show, so it is the
# only build number the app may display. The project file carries a stale CURRENT_PROJECT_VERSION (whatever
# Xcode last stored); here it is replaced by CI_BUILD_NUMBER for every target (the App Clip must match the app),
# and Info.plist is marked so the app can tell a Xcode Cloud build from a build run from Xcode on a Mac.
set -e
cd "$CI_PRIMARY_REPOSITORY_PATH"
[ -n "$CI_BUILD_NUMBER" ] || { echo "CI_BUILD_NUMBER not set"; exit 1; }

sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9.]+;/CURRENT_PROJECT_VERSION = $CI_BUILD_NUMBER;/g" Reczipes2.xcodeproj/project.pbxproj
plutil -replace ReczipesBuildSource -string "xcode-cloud" Reczipes2/Info.plist
plutil -replace ReczipesBuildSource -string "xcode-cloud" Reczipes2Clip/Info.plist 2>/dev/null || true

echo "Build number set to $CI_BUILD_NUMBER:"
grep -c "CURRENT_PROJECT_VERSION = $CI_BUILD_NUMBER;" Reczipes2.xcodeproj/project.pbxproj
