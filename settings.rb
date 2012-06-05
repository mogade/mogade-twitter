require 'yaml'
require 'redis'
require 'mongo'

class Settings
  def initialize(environemnt)
    @settings = YAML::load_file(File.dirname(__FILE__) + '/settings.yml')[environemnt]
  end

  def redis
    redis = Redis.new(:host => @settings['redis']['host'], :port => @settings['redis']['port'])
    redis.select(@settings['redis']['database'])
    redis
  end

  def mongo
    if @settings['mongo']['replica_set']
      connection = Mongo::ReplSetConnection.new([@settings['mongo']['host1'], @settings['mongo']['port1']], [@settings['mongo']['host2'], @settings['mongo']['port2']], {:read => :secondary, :name => @settings['mongo']['replica_set']})
    else
      connection = Mongo::Connection.new(@settings['mongo']['host'], @settings['mongo']['port'])
    end
    connection.db(@settings['mongo']['name'])
  end

  def twitter
    @settings['twitter']
  end
end