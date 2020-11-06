PLATFORM="platform=iOS Simulator,name=iPhone 8"
SDK="iphonesimulator"
SHELL=/bin/bash -o pipefail
XCODE_MAJOR_VERSION=$(shell xcodebuild -version | HEAD -n 1 | sed -E 's/Xcode ([0-9]+).*/\1/')

.PHONY: all cocoapods test carthage analyze spm

cocoapods:
	pod lib lint

analyze:
	xcodebuild clean analyze -destination ${PLATFORM} -sdk ${SDK} -workspace PINCache.xcworkspace -scheme PINCache \
	ONLY_ACTIVE_ARCH=NO \
	CODE_SIGNING_REQUIRED=NO \
	CLANG_ANALYZER_OUTPUT=plist-html \
	CLANG_ANALYZER_OUTPUT_DIR="$(shell pwd)/clang" | xcpretty
	if [[ -n `find $(shell pwd)/clang -name "*.html"` ]] ; then rm -rf `pwd`/clang; exit 1; fi
	rm -rf $(shell pwd)/clang

test:
	xcodebuild clean test -destination ${PLATFORM} -sdk ${SDK} -workspace PINCache.xcworkspace -scheme PINCache \
	ONLY_ACTIVE_ARCH=NO \
	CODE_SIGNING_REQUIRED=NO | xcpretty

carthage:
	if [ ${XCODE_MAJOR_VERSION} -gt 11 ] ; then \
		echo "Carthage no longer works in Xcode 12 https://github.com/Carthage/Carthage/blob/master/Documentation/Xcode12Workaround.md"; \
		exit 1; \
	fi
	carthage update --no-use-binaries --no-build
	carthage build --no-skip-current

spm:
# For now just check whether we can assemble it
# TODO: replace it with "swift test --enable-test-discovery --sanitize=thread" when swiftPM resource-related bug would be fixed.
# https://bugs.swift.org/browse/SR-13560
	swift build

all: carthage cocoapods test analyze spm
