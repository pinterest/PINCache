Pod::Spec.new do |s|
  s.name          = 'PINCache'
  s.version       = '2.0'
  s.source_files  = 'PINCache/*.{h,m}'
  s.homepage      = 'https://github.com/pinterest/PINCache'
  s.summary       = 'Fast, thread safe, parallel object cache for iOS and OS X.'
  s.authors       = { 'Garrett Moon' => 'garrett@pinterest.com', 'Justin Ouellette' => 'jstn@tumblr.com' }
  s.source        = { :git => 'https://github.com/pinterest/PINCache.git', :tag => "#{s.version}" }
  s.license       = { :type => 'Apache 2.0', :file => 'LICENSE.txt' }
  s.requires_arc  = true
  s.frameworks    = 'Foundation'
  s.ios.weak_frameworks   = 'UIKit'
  s.osx.weak_frameworks   = 'AppKit'
  s.ios.deployment_target = '5.0'
  s.osx.deployment_target = '10.7'
end
