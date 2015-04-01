{Channel, Transport} = require "mutual"
{parse} = require "url"

module.exports = (config) ->
  {hostname} = parse config.api_server
  # We assume the Redis server runs on the same host as the
  # API server, and on the default port (6379)
  # TODO: make port configurable
  transport = Transport.Redis.Queue.create(host: hostname)
  channel = Channel.create "huxley", transport

