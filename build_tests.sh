#!/usr/bin/env sh

xcodebuild ONLY_ACTIVE_ARCH=NO -project tests/PINCache.xcodeproj -scheme PINCacheTests -sdk iphonesimulator TEST_AFTER_BUILD=YES clean build
