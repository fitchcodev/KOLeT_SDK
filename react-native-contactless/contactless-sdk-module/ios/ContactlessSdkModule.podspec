require 'json'

package = JSON.parse(File.read(File.join(__dir__, '..', 'package.json')))

Pod::Spec.new do |s|
  s.name           = 'ContactlessSdkModule'
  s.version        = package['version']
  s.summary        = package['name']
  s.description    = package['name']
  s.license        = package['license'] || 'MIT'
  s.author         = package['author'] || ''
  s.homepage       = package['homepage'] || 'https://example.com'
  s.platform       = :ios, '13.0'
  s.source         = { :git => 'https://example.com/contactless-sdk-module.git', :tag => s.version.to_s }
  s.swift_version  = '5.4'
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  s.source_files = '**/*.{h,m,mm,swift}'
end
