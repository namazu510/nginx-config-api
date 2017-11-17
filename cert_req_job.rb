require 'timers'
require 'open3'
require 'active_record'
require './models/domain'

CONFIG = YAML.load_file('./config.yml')
ENV = 'production'
cert_interval = 60 * 60 * 12 # 証明書発行リクエスト実行間隔

timers = Timers::Group.new
timers.every(cert_interval) do
  puts "#{Time.now} cert request job start"
  cert_req_domains = Domain.where(cert_req: true)
  if cert_req_domains.blank?
    puts "#{Time.now} no cert required domain"
    next
  end

  # 登録domainの一覧を生成する
  domains = Domain.all
  domain_list = ''
  domains.each do |domain|
    domain_list << " -d #{domain.domain}"
  end

  # 発行する
  options = %w(--agree-tos -q --expand --allow-subset-of-names)
  lets_conf = CONFIG[ENV]['lets']
  command = "#{lets_conf['cmd']}  #{options.join(' ')} --email #{lets_conf['email']} " +
    "--webroot -w #{lets_conf['webroot_dir']} #{domain_list}"
  puts command
  o, e, s = Open3.capture3(command)
  fail "ssl_cert request faild! \n #{e}" unless s.success?

  # 発行されたパスを取得する　=> 最終更新の物が今できた奴
  files = {
    live: get_latest_file('/etc/letsencrypt/live'),
    renew: get_latest_file('/etc/letsencrypt/renewal')
  }

  # DBを更新する
  domains.each do |domain|
    domain.cert_req = false
    domain.lets_live_path = files[:live][:path].to_s
    domain.lets_renew_path = files[:renew][:path].to_s
    domain.update!
  end

  # Nginxのコンフィグをオレオレから置き換える
  domains.each do |domain|
    use_lets = true
    dummy_ssl = false

    erb = ERB.new(File.read('./config_template.erb'))
    File.open(domain.conf_path, mode = 'w') do |f|
      domain = domain.domain
      f.write(erb.result(binding))
    end
  end

  # Nginxをリロードする
  cmd = CONFIG[ENV]['nginx']['reload_cmd']
  o, e, s = Open3.capture3(cmd)
  fail "nginx reload faild!" unless s.success?

  puts "#{Time.now} finish cert update requests"
end

# -----
# functions
# -----
def get_latest_file(path)
  Pathname.new(path).children.map do |child_path|
    {
        path: child_path,
        last_modify: File.stat(child_path).mtime
    }
  end.sort_by! { |file| file['last_modify'] }.last
end

# timer起動する
puts "scheduled cert_req_job"
loop { timers.wait }
