PLATFORM="platform=iOS Simulator,name=iPhone 8"
SDK="iphonesimulator"
SHELL=/bin/bash -o pipefail
XCODE_MAJOR_VERSION=$(shell xcodebuild -version | HEAD -n 1 | sed -E 's/Xcode ([0-9]+).*/\1/')
IOS_EXAMPLE_PROJECT="IntegrationTests/PINCache-SPM-Integration/PINCache-SPM-Integration.xcodeproj"
EXAMPLE_SCHEME="PINCache-SPM-Integration"

.PHONY: all cocoapods test carthage analyze spm example

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
	# To workaround https://github.com/Carthage/Carthage/issues/1974 on CI
	##### Apply workaround https://github.com/Carthage/Carthage/issues/3019#issuecomment-734415287
	./carthage.sh update --no-use-binaries --no-build; \
	./carthage.sh build --no-skip-current;

spm:
# For now just check whether we can assemble it
# TODO: replace it with "swift test --enable-test-discovery --sanitize=thread" when swiftPM resource-related bug would be fixed.
# https://bugs.swift.org/browse/SR-13560
	swift build


example:
	if [ ${XCODE_MAJOR_VERSION} -lt 12 ] ; then \
		echo "Xcode 12 and Swift 5.3 reqiured to build example project"; \
		exit 1; \
	fi
	xcodebuild clean build -project ${IOS_EXAMPLE_PROJECT} -scheme ${EXAMPLE_SCHEME} -destination ${PLATFORM} -sdk ${SDK} \
	ONLY_ACTIVE_ARCH=NO \
	CODE_SIGNING_REQUIRED=NO | xcpretty

all: carthage cocoapods test analyze spm example
