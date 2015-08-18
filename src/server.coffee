#===============================================================================
# Huxley Agent
#===============================================================================
# stdlib
{parse} = require "url"

# panda-lib
{call} = require "fairmont"
{processor} = require "pbx"

# internal
handlers = require "./api/handlers"
spec = require "./api/spec"
port = 8080

#=========================
# Launch Server
#=========================

call ->
  (require "http")
  .createServer yield (processor spec, handlers)
  .listen port, ->
    console.log "Server listening on #{port}"
