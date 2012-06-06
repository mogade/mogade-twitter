
require_relative('settings')

settings = Settings.new(ARGV[0] || 'development')
redis = settings.redis
set_key = 'twitter:daily'

exit if redis.scard(set_key) == 0

require 'twitter'
Twitter.configure do |config|
  config.consumer_key = settings.twitter['key']
  config.consumer_secret = settings.twitter['secret']
end

mongo = settings.mongo
twitters = mongo.collection('twitters')
scores = mongo.collection('scores')
leaderboards = mongo.collection('leaderboards')

skipped = []
begin
  while (lid = redis.spop(set_key)) != nil
    limit_key =  "twitter:limit:#{lid}"
    if redis.exists(limit_key)
      skipped << lid
      next
    end

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
    core_message = twitter['message'].gsub('%score%', score['d']['p'].to_s)
    message = core_message.gsub('%user%', score['un'])
    if message.length > 140
      message = core_message.gsub('%user%', 'some1')
    end
    Twitter.update(message) if message.length <= 140
    redis.setex(limit_key, 300, true)
  end
ensure
  redis.sadd(set_key, *skipped) if skipped.length > 0
end