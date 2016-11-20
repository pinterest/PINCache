COMMON_PREPROCESSOR_FLAGS = ['-fobjc-arc', '-Wno-deprecated-declarations', '-Wignored-attributes']

apple_library(
  name = 'PINCache',
  exported_headers = glob([
    'PINCache/*.h',
  ]),
  srcs = glob([
    'PINCache/*.m',
  ]),
  lang_preprocessor_flags = {
    'C': ['-std=gnu99'],
    'CXX': ['-std=gnu++11'],
  },
  preprocessor_flags = COMMON_PREPROCESSOR_FLAGS,
  frameworks = [
    '$SDKROOT/System/Library/Frameworks/Foundation.framework',
    '$SDKROOT/System/Library/Frameworks/UIKit.framework',
    '$SDKROOT/System/Library/Frameworks/CoreGraphics.framework',
  ],
  visibility = [
    'PUBLIC',
  ],
)

apple_resource(
  name = 'TestAppResources',
  files = glob(['tests/PINCache/*.png']),
  dirs = [],
)

apple_bundle(
  name = 'TestApp',
  binary = ':TestAppBinary',
  extension = 'app',
  info_plist = 'tests/PINCache/PINCache-Info.plist',
  tests = [':Tests'],
)

apple_binary(
  name = 'TestAppBinary',
  prefix_header = 'tests/PINCache/PINCache-Prefix.pch',
  headers = glob([
    'tests/PINCache/*.h',
  ]),
  srcs = glob([
    'tests/PINCache/*.m',
  ]),
  deps = [
    ':TestAppResources',
    ':PINCache',
  ],
  frameworks = [
    '$SDKROOT/System/Library/Frameworks/UIKit.framework',
    '$SDKROOT/System/Library/Frameworks/Foundation.framework',
  ],
)

apple_package(
  name = 'TestAppPackage',
  bundle = ':TestApp',
)

apple_test(
  name = 'Tests',
  test_host_app = ':TestApp',
  srcs = glob([
    'tests/PINCacheTests/*.m'
  ]),
  info_plist = 'tests/PINCacheTests/PINCacheTests-Info.plist',
  preprocessor_flags = COMMON_PREPROCESSOR_FLAGS,
  frameworks = [
    '$SDKROOT/System/Library/Frameworks/Foundation.framework',
    '$SDKROOT/System/Library/Frameworks/UIKit.framework',
    '$PLATFORM_DIR/Developer/Library/Frameworks/XCTest.framework',
  ],
)
