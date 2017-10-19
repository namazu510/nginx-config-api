ActiveRecord::Base.configurations = YAML.load_file('db/database.yml')
ActiveRecord::Base.establish_connection(:development)

class Domain < ActiveRecord::Base
  # sub_domain: text
  # domain: text
  # use_auth: boolean
  # conf_path: text
end