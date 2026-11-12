Pod::Spec.new do |s|
  s.name             = 'trevix_video'
  s.version          = '1.0.0'
  s.summary          = 'Edición de video de TREVIX en el teléfono.'
  s.description      = 'Recorte, filtro de color, superposiciones animadas, cierre y audio con AVFoundation.'
  s.homepage         = 'https://trevix.ond-s.com'
  s.license          = { :type => 'Proprietary', :text => 'TREVIX' }
  s.author           = { 'TREVIX' => 'soporte@trevix.ond-s.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '14.0'
  s.frameworks       = 'AVFoundation', 'CoreImage', 'Vision'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.0'
end
