{call} = require "when/generator"
{processor} = require "pbx"
{parse} = require "url"
initialize = require "./handlers"
api = require "./api"
api.base_url = "http://localhost:8080"

#=========================
# Launch Server
#=========================

call ->
  (require "http")
  .createServer yield (processor api, initialize)
  .listen (parse api.base_url).port, ->
    console.log "Server listening on #{api.base_url}"
