{Channel, Transport} = require "mutual"

# Set up a message channel to transmit status events
# TODO: how to configure the Redis server's address?
transport = Transport.Redis.Queue.create()
# TODO: what do we name the channel?
channel = Channel.create "hello", transport

module.exports = channel
