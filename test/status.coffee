assert = require "assert"
{describe} = require "amen"
{discover} = (require "pbx").client
{w} = require "fairmont"
{promise} = require "when"
{Channel, Transport} = require "mutual"
 
describe "Kick Server", (context) ->

  console.log "====================================================="
  console.log "This test requires a Redis server."
  console.log "If tests are failing, make sure you are running a"
  console.log "Redis server on localhost using the default port."
  console.log "====================================================="

  context.test "Status events", (context) ->
    api = yield discover "http://localhost:8080"

    for status in w "starting running failed shutting_down stopped"
      do (status) ->
        context.test "Status: #{status}", (context) ->
          channel = Channel.create "hello", Transport.Redis.Queue.create()

          message = promise (resolve, reject) ->
            channel.once status: (status) ->
              resolve status

          yield api.status.create
            application_id: "test"
            deployment_id: "deadbeef"
            service: "test-service"
            status: status

          assert.equal status, (yield message).status
          channel.close()

    context.test "Wrong status type results in error", (context) ->
      try
        yield api.status.create
          application_id: "test"
          deployment_id: "deadbeef"
          service: "test-service"
          status: "foobar"

        context.fail "Expected exception, but none was thrown"
      catch
        context.pass()
