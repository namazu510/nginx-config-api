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

DOMAIN_REQ_LOCK = Mutex.new
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
  DOMAIN_REQ_LOCK.lock
  begin
    if get_domain(sub_domain)
      status 400
      json isSuccess: false, message: 'Invalid domain.'
    else
      add_route(sub_domain)
      json isSucess: true, message: 'Successful request!'
    end
  ensure
    DOMAIN_REQ_LOCK.unlock
  end
end

delete '/route/*' do |sub_domain|
  DOMAIN_REQ_LOCK.lock
  begin
    domain = get_domain(sub_domain)
    if domain.nil?
      status 404
      json isSuccess: false, message: 'Domain is not registered'
    else
      delete_route(domain)
      json isSucess: true, message: 'Successful request!'
    end
  ensure
    DOMAIN_REQ_LOCK.unlock
  end
end

get '/log/*' do |sub_domain|
  domain = get_domain(sub_domain)
  if domain.nil?
    status 404
    json isSuccess: false, message: 'Domain is not registered'
  else
    json isSuccess: true, log: get_log("/var/log/nginx/#{domain.domain}/access.log")
  end
end

get '/error_log/*' do |sub_domain|
  domain = get_domain(sub_domain)
  if domain.nil?
    status 404
    json isSuccess: false, message: 'Domain is not registered'
  else
    json isSuccess: true, log: get_log("/var/log/nginx/#{domain.domain}/error.log")
  end
end

# ----------
# functions
# ----------
def add_route(sub_domain)
  reset_log(sub_domain)
  write_config_file(sub_domain)
  reload_nginx
end

def delete_route(domain)
  delete_config_file(domain)
  delete_ssl_certs(domain)
  domain.destroy
  reload_nginx
end

def reset_log(sub_domain)
  return unless CONFIG[ENV]['nginx']['app_log']

  domain = absolute_domain(sub_domain)
  `mkdir /var/log/nginx/#{domain}`
  `rm -rf /var/log/nginx/#{domain}/*`
end

def get_log(path)
  f = File.open(path)
  log = f.read
  f.close
  log
end

def write_config_file(sub_domain)
  path = Pathname.new(CONFIG[ENV]['nginx']['conf_dir'])
  path += sub_domain + '.conf'

  domain = absolute_domain(sub_domain)
  secure_domain = sub_domain.end_with? 'ks'

  # 最初の書き出しのときはオレオレ証明を使う
  use_lets  = false
  dummy_ssl = true

  erb = ERB.new(File.read('./config_template.erb'))
  File.open(path, mode = 'w') do |f|
    f.write(erb.result(binding))
  end

  Domain.create!(
    sub_domain: sub_domain,
    domain: domain,
    use_auth: secure_domain,
    conf_path: path,
    cert_req: true
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
  sub_domain + '.' + base
end
