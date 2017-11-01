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

# ----------
# functions
# ----------
def add_route(sub_domain)
  ssl_cert_update()
  write_config_file(sub_domain)
  reload_nginx
end

def delete_route(domain)
  delete_config_file(domain)
  delete_ssl_certs(domain)
  domain.destroy
  reload_nginx
end


def write_config_file(sub_domain)
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
      conf_path: path
  )
end

def delete_config_file(domain)
  `rm -rf #{domain.conf_path}`
end

def delete_ssl_certs(domain)
  lets_conf = CONFIG[ENV]['lets']
  return unless lets_conf['enable']

  conf_dirs = %W(archive/#{domain.domain} live/#{domain.domain} renewal/#{domain.domain}.conf)
  conf_dirs.each do |dir|
    `rm -rf /etc/letsencrypt/#{dir}`
  end
end

def ssl_cert_update
  lets_conf = CONFIG[ENV]['lets']
  return unless lets_conf['enable']

  # 登録domainの全一覧を生成する
  domains = Domain.all
  domain_list = ''
  domains.each do |domain|
    domain_list << " -d #{domain.domain}"
  end

  # 発行する
  options = %w(--agree-tos -q --expand --allow-subset-of-names)
  command = "#{lets_conf['cmd']}  #{options.join(' ')} --email #{lets_conf['email']} " +
     "--webroot -w #{lets_conf['webroot_dir']} #{domain_list}"
  puts command
  CERT_LOCK.synchronize do
    o, e, s = Open3.capture3(command)
    puts o
    fail "ssl_cert request faild! \n #{e}" unless s.success?
  end
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
