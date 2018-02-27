# 今あるNginxのコンフィグを全部書き直す
# templateの変更でアップデートが掛かったときとかのために対応する

require './config'
require './models/domain'
CONFIG = Config.new('production')

Domain.all.each do |domain|
  puts "#{domain.domain}"
  # update
  if domain.auth_url == 'http://gallery-portal.gallery.local/hornet-auth'
    domain.auth_url = 'http://gallery-portal.gallery.local/auth/csc-auth'
  end

  # write
  use_lets = !domain.cert_req
  dummy_ssl = !use_lets
  auth_uri = URI.parse(domain.auth_url) if domain.use_auth
  erb = ERB.new(File.read('./config_template.erb'))
  File.open(domain.conf_path, mode = 'w') do |f|
    f.write(erb.result(binding))
  end

  domain.save!
end
