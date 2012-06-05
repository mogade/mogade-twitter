require_relative('settings')

settings = Settings.new(ARGV[0] || 'development')
redis = settings.redis
runner_key = 'twitter:runner'
set_key = 'twitter:daily'

redis.watch(runner_key)
exists = redis.exists(runner_key)
redis.multi { redis.setex(runner_key, 300, true) } if exists == false

if exists == true
  p "already running"
  exit
end

require 'twitter'

mongo = settings.mongo
twitters = mongo.collection('twitters')
scores = mongo.collection('scores')
leaderboards = mongo.collection('leaderboards')

Twitter.configure do |config|
  config.consumer_key = settings.twitter['key']
  config.consumer_secret = settings.twitter['secret']
end

begin
  while (lid = redis.spop(set_key)) != nil
    lid = BSON::ObjectId.from_string(lid)
    twitter = twitters.find_one({:lid => lid})
    next if twitter.nil?

    leaderboard = leaderboards.find_one(lid, {:fields => {:_id => false, :t => true}})
    next if leaderboard.nil?
    direction = leaderboard['t'] == 1 ? :desc : :asc
    score = scores.find_one({:lid => lid}, {:fields => {:_id => false, 'd.p' => true, 'un' => true}, :limit => 1, :sort => ['d.p', direction]})

    Twitter.configure do |config|
      config.oauth_token = twitter['token']
      config.oauth_token_secret = twitter['secret']
    end
    message = twitter['message'].gsub('%user%', score['un']).gsub('%score%', score['d']['p'].to_s)
    Twitter.update(message)
  end
ensure
  redis.del(runner_key)
end