#===============================================================================
# Huxley Agent - Database
#===============================================================================
# This module sets up a database for the Huxley Agent.  Among other things, the
# Agent uses this to gather logs from cluster containers.

{async} = require "fairmont"
{Memory} = require "pirate"  # database adapter (In-Memory simulation of database)


module.exports =

  initialize: async () ->
    #adapter = Redis.Adapter.make(host: "192.168.59.103")  # Local Machine
    #adapter = Redis.Adapter.make(host: "172.17.42.1")    # Docker Container
    adapter = Memory.Adapter.make()
    adapter.connect()

    # Database Collection Declarations
    return {
      # Raw Adapters
      logs: yield adapter.collection "logs"
    }
