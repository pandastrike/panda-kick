{call} = require "when/generator"
{processor} = require "pbx"
initialize = require "./handlers"
api = require "./api"
api.base_url = "http://localhost:8080"

#=========================
# Launch Server
#=========================

call ->
  (require "http")
  .createServer yield (processor api, initialize)
  .listen 8080, ->
    console.log "Server listening on #{api.base_url}"
