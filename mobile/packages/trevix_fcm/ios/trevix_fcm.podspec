Pod::Spec.new do |s|
  s.name             = 'trevix_fcm'
  s.version          = '1.0.0'
  s.summary          = 'Avisos push de TREVIX en iPhone.'
  s.description      = 'Firebase Cloud Messaging con APNs: token del teléfono, avisos con la app cerrada y apertura de la pantalla.'
  s.homepage         = 'https://trevix.ond-s.com'
  s.license          = { :type => 'Proprietary', :text => 'TREVIX' }
  s.author           = { 'TREVIX' => 'soporte@trevix.ond-s.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  # Firebase 12 exige iOS 15; TREVIX admite desde iOS 14.
  s.dependency 'FirebaseMessaging', '~> 11.0'
  s.platform         = :ios, '14.0'
  s.static_framework = true
  s.frameworks       = 'UserNotifications'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.0'
end
