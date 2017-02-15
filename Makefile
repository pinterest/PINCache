PLATFORM="platform=iOS Simulator,OS=10.2,name=iPhone 7"
SDK="iphonesimulator10.2"
SHELL=/bin/bash -o pipefail

.PHONY: all lint test carthage

lint:
	pod lib lint --allow-warnings

test:
	xcodebuild clean test -destination ${PLATFORM} -sdk ${SDK} -workspace PINCache.xcworkspace -scheme PINCache \
	ONLY_ACTIVE_ARCH=NO \
	CODE_SIGNING_REQUIRED=NO | xcpretty

carthage:
	carthage update

all: carthage lint test