Pod::Spec.new do |s|
  s.name             = 'trevix_app_icon'
  s.version          = '1.0.0'
  s.summary          = 'Iconos alternativos de TREVIX'
  s.homepage         = 'https://treviix.app'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'TREVIX' => 'soporte@treviix.app' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '14.0'
  s.swift_version    = '5.0'
end
