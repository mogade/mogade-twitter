require_relative('settings')
require 'active_support/core_ext'
require 'twitter'

def process(set_key, message, scope_field)
  settings = Settings.new(ARGV[0] || 'development')
  redis = settings.redis
  return if redis.scard(set_key) == 0

  mongo = settings.mongo
  twitters = mongo.collection('twitters')
  scores = mongo.collection('scores')
  leaderboards = mongo.collection('leaderboards')

  Twitter.configure do |config|
    config.consumer_key = settings.twitter['key']
    config.consumer_secret = settings.twitter['secret']
  end

  begin
    skipped = []
    while (lid = redis.spop(set_key)) != nil
      limit_key =  "#{set_key}:limit:#{lid}"
      if redis.exists(limit_key)
        skipped << lid
        next
      end

      lid = BSON::ObjectId.from_string(lid)
      twitter = twitters.find_one({:lid => lid})
      next if twitter.nil?

      leaderboard = leaderboards.find_one(lid, {:fields => {:t => true, :o => true}})
      next if leaderboard.nil?

      direction = leaderboard['t'] == 1 ? :desc : :asc
      score = yield(leaderboard, direction, scores)
      next if score.nil?

      Twitter.configure do |config|
        config.oauth_token = twitter['token']
        config.oauth_token_secret = twitter['secret']
      end
      core_message = twitter[message].gsub('%score%', score[scope_field]['p'].to_s)
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
end

if ARGV[1] == 'daily'
  process 'twitter:daily', 'dm', 'd' do |leaderboard, direction, scores|
    offset = leaderboard['o']
    now = Time.now.utc
    time = now.midnight + -3600 * (offset || 0)
    stamp = time > now ? time - 86400 : time
    scores.find_one({:lid => leaderboard['_id'], 'd.s' => stamp}, {:fields => {:_id => false, 'd.p' => true, 'un' => true}, :limit => 1, :sort => ['d.p', direction]})
  end
elsif ARGV[1] == 'overall'
  process 'twitter:overall', 'om', 'o' do |leaderboard, direction, scores|
    scores.find_one({:lid => leaderboard['_id']}, {:fields => {:_id => false, 'o.p' => true, 'un' => true}, :limit => 1, :sort => ['o.p', direction]})
  end
end