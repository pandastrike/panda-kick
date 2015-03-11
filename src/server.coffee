http = require "http"
kick = require "./kick"

#=========================
# Launch Server
#=========================

http.createServer(kick).listen 8080, ->
  console.log '===================================='
  console.log '  The server is online and ready.'
  console.log '===================================='
