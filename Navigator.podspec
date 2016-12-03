Pod::Spec.new do |s|

s.name                      = "Navigator"
s.version                   = "1.0.0"
s.summary                   = "Routing and navigation utilities"


s.homepage                  = "https://github.com/gcasar/ios-navigator"

s.license                   = {:type=>'MIT', :file=>'license.txt'}

s.author                    = { "gcasar" => "gregorcasar@gmail.com" }
s.platform                  = :ios, "8.0"


s.source                    = { :git => "https://github.com/gcasar/ios-navigator.git", :tag => "#{s.version}" }


s.source_files              = "Navigator/*.swift"
s.pod_target_xcconfig       =  {'SWIFT_VERSION' => '3.0'}

end
