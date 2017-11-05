require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/json'
require 'yaml'
require 'pathname'
require 'erb'
require 'logger'
require 'open3'
require 'thread'
require 'active_record'

require './models/domain'

CONFIG = YAML.load_file('./config.yml')
ENV = development? ? 'develop' : 'production'

CERT_LOCK = Mutex.new
NGINX_LOCK = Mutex.new

configure do
  mime_type :text, 'text/plain'
end

# ----------
# routes
# ----------
get '/' do
  'This is Nginx config generate api.'
end

post '/route/*' do |sub_domain|
  if get_domain(sub_domain)
    status 400
    json isSuccess: false, message: 'Invalid domain.'
  else
    add_route(sub_domain)
    json isSucess: true, message: 'Successful request!'
  end
end

delete '/route/*' do |sub_domain|
  domain = get_domain(sub_domain)
  if domain.nil?
    status 404
    json isSuccess: false, message: 'Domain is not registered'
  else
    delete_route(domain)
    json isSucess: true, message: 'Successful request!'
  end
end

get '/log/*' do |sub_domain|
  domain = get_domain(sub_domain)
  if domain.nil?
    status 404
    json isSuccess: false, message: 'Domain is not registered'
  else
    json isSuccess: true, log: get_log("/var/log/nginx/#{sub_domain}/access.log")
  end
end

get '/error_log/*' do |sub_domain|
  domain = get_domain(sub_domain)
  if domain.nil?
    status 404
    json isSuccess: false, message: 'Domain is not registered'
  else
    json isSuccess: true, log: get_log("/var/log/nginx/#{sub_domain}/error.log")
  end
end

# ----------
# functions
# ----------
def add_route(sub_domain)
  cert_files = ssl_cert_update(sub_domain)
  write_config_file(sub_domain, cert_files)
  reload_nginx
end

def delete_route(domain)
  delete_config_file(domain)
  delete_ssl_certs(domain)
  domain.destroy
  reload_nginx
end

def get_log(path)
  f = File.open(path)
  log = f.read
  f.close
  log
end

def write_config_file(sub_domain, cert_files)
  path = Pathname.new(CONFIG[ENV]['nginx']['conf_dir'])
  path += sub_domain + '.conf'

  domain = absolute_domain(sub_domain)
  internal_domain = CONFIG[ENV]['domain']['internal_base']
  secure_domain = sub_domain.end_with? 'ks'

  show_log  = CONFIG[ENV]['nginx']['app_log']
  use_ssl   = CONFIG[ENV]['nginx']['ssl']
  use_lets  = CONFIG[ENV]['lets']['enable']
  dummy_ssl = CONFIG[ENV]['nginx']['dummy_ssl']

  if show_log
    `mkdir /var/log/nginx/#{domain}`
  end

  erb = ERB.new(File.read('./config_template.erb'))
  File.open(path, mode = 'w') do |f|
    f.write(erb.result(binding))
  end

  Domain.create!(
      sub_domain: sub_domain,
      domain: domain,
      use_auth: secure_domain,
      conf_path: path,
      lets_live_path: cert_files[:live][:path].to_s,
      lets_renew_path: cert_files[:renew][:path].to_s,
  )
end

def delete_config_file(domain)
  `rm -rf #{domain.conf_path}`
end

def delete_ssl_certs(domain)
  lets_conf = CONFIG[ENV]['lets']
  return unless lets_conf['enable']

  # 複数同じ証明書Dirを使ってる場合は最後の１つになるまで消さない
  `rm -rf #{domain.lets_live_path}` unless Domain.where(lets_live_path: domain.lets_live_path).size > 1
  `rm -rf #{domain.lets_renew_path}` unless Domain.where(lets_renew_path: domain.lets_renew_path).size > 1
end

def ssl_cert_update(new_sub_domain)
  lets_conf = CONFIG[ENV]['lets']
  return unless lets_conf['enable']

  # 登録domain + 新しく追加するドメインの一覧を生成する
  domains = Domain.all
  domain_list = " -d #{absolute_domain(new_sub_domain)}"
  domains.each do |domain|
    domain_list << " -d #{domain.domain}"
  end

  # 発行する
  options = %w(--agree-tos -q --expand --allow-subset-of-names)
  command = "#{lets_conf['cmd']}  #{options.join(' ')} --email #{lets_conf['email']} " +
     "--webroot -w #{lets_conf['webroot_dir']} #{domain_list}"
  puts command

  files = {}
  CERT_LOCK.synchronize do
    o, e, s = Open3.capture3(command)
    fail "ssl_cert request faild! \n #{e}" unless s.success?

    # 発行されたパスを取得する　=> 最終更新の物が今できた奴
    files = {
      live: get_latest_file('/etc/letsencrypt/live'),
      renew: get_latest_file('/etc/letsencrypt/renewal')
    }
  end
  files
end

def get_latest_file(path)
  Pathname.new(path).children.map do |child_path|
    {
      path: child_path,
      last_modify: File.stat(child_path).mtime
    }
  end.sort_by! { |file| file['last_modify'] }.last
end

def reload_nginx
  cmd = CONFIG[ENV]['nginx']['reload_cmd']
  NGINX_LOCK.synchronize do
    o, e, s = Open3.capture3(cmd)
    fail "nginx reload faild!" unless s.success?
  end
end

def get_domain(sub_domain)
  Domain.find_by(sub_domain: sub_domain)
end

def absolute_domain(sub_domain)
  base = CONFIG[ENV]['domain']['base']
  sub_domain  + '.' + base
end
