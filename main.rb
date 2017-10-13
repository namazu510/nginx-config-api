require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/json'
require 'yaml'
require 'pathname'
require 'erb'
require 'logger'
require 'open3'

CONFIG = YAML.load_file('./config.yml')
ENV = development? ? 'develop' : 'production'

begin
  File.open('domain-store.dump', 'r') do |f|
    DOMAIN_STORE = Marshal.load(f)
  end
rescue
  DOMAIN_STORE = []
end


configure do
  mime_type :text, 'text/plain'
end

get '/' do
  'This is Nginx config generate api.'
end

post '/route/*' do |sub_domain|
  if domain_exist?(sub_domain)
    status 400
    json isSuccess: false, message: 'Invalid domain.'
  else
    add_route(sub_domain)
    json isSucess: true, message: 'Successful request!'
  end
end

delete '/route/*' do |sub_domain|
  if !domain_exist?(sub_domain)
    status 404
    json isSuccess: false, message: 'Domain is not registered'
  else
    delete_route(sub_domain)
    json isSucess: true, message: 'Successful request!'
  end
end

# ----------
# functions
# ----------
def add_route(sub_domain)
  ssl_cert_request(sub_domain)
  write_config_file(sub_domain)
  DOMAIN_STORE << sub_domain
  save_domain_store
  reload_nginx
end

def delete_route(sub_domain)
  delete_config_file(sub_domain)
  delete_ssl_certs(sub_dmain)
  DOMAIN_STORE.delete(sub_domain)
  save_domain_store
  reload_nginx
end

def save_domain_store
  File.open('domain-store.dump', 'w') do |f|
    Marshal.dump(DOMAIN_STORE)
  end
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


  erb = ERB.new(File.read('./config_template.erb'))
  File.open(path, mode = 'w') do |f|
    f.write(erb.result(binding))
  end
end

def delete_config_file(sub_domain)
  path = Pathname.new(CONFIG[ENV]['nginx']['conf_dir'])
  path += sub_domain + '.conf'

  fail 'config file dose not exist' unless path.exist?
  path.delete
end

def ssl_cert_request(sub_domain)
  lets_conf = CONFIG[ENV]['lets']
  return unless lets_conf['enable']

  cmd = lets_conf['cmd']
  email = lets_conf['email']
  domain = absolute_domain(sub_domain)
  webroot_path = lets_conf['webroot_dir'] + domain

  `mkdir -p #{webroot_path}`
  command = "#{cmd}  --agree-tos --webroot -w #{webroot_path} -d #{domain} --email #{email}"
  puts command
  o, e, s = Open3.capture3(command)
  fail "ssl_cert request faild! \n #{e}" unless s.success?
  o
end

def delete_ssl_certs(sub_domain)
  lets_conf = CONFIG[ENV]['lets']
  return unless lets_conf['enable']

  domain = absolute_domain(sub_domain)
  `rm -rf /etc/letsencrypt/live/#{domain}`
  `rm -rf /etc/letsencrypt/renewal/#{domain}.conf`
end

def reload_nginx
  cmd = CONFIG[ENV]['nginx']['reload_cmd']
  `#{cmd}`
end

def domain_exist?(sub_domain)
  DOMAIN_STORE.include? sub_domain
end

def absolute_domain(sub_domain)
  base = CONFIG[ENV]['domain']['base']
  sub_domain  + '.' + base
end
