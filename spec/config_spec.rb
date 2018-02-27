require './spec/spec_helper'
require './config'

Config::CONFIG_FILE_NAME = './spec/config-test.yml'

describe Config do
  let(:config_env1) { Config.new('env1') }
  let(:config_env2) { Config.new('env2') }

  it 'initializeできる' do
    config = Config.new('env1')
    expect(config).not_to be_nil
  end

  it '一階層目の値取れる' do
    expect(config_env1.obj1).to eq 'hello'
  end

  it '二階層目の値取れる' do
    expect(config_env1.obj2.obj2_1).to eq 'hello'
  end

  it 'env違うのも取れる' do
    expect(config_env2.obj1).to eq 'hello'
  end
end

