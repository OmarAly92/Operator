Pod::Spec.new do |s|
  s.name             = 'ios_liquid_glass'
  s.version          = '0.1.0'
  s.summary          = 'iOS 27 Liquid Glass for Flutter.'
  s.description      = 'Reads the iOS accessibility settings that Flutter does not expose.'
  s.homepage         = 'https://github.com/whynotmake-it/flutter_liquid_glass'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Omar Aly' => 'omarkarim5555@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
end
