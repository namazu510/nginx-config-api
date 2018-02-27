require 'yaml'

class Config
  CONFIG_FILE_NAME = './config.yml'

  def initialize(env)
    config = YAML.load_file(CONFIG_FILE_NAME)
    hash_method_define = Proc.new do |res, obj|
      obj.each do |k, v|
        if(v.kind_of?(Hash))
          res_child = Object.new
          hash_method_define.call(res_child, v)
          res.define_singleton_method(k) { res_child }
          next
        end
        res.define_singleton_method(k) { v }
      end
    end
    hash_method_define.call(self, config[env])
  end
end
