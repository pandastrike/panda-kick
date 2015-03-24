assert = require "assert"
{describe} = require "amen"
{discover} = (require "pbx").client
{w} = require "fairmont"
 
describe "Kick Server", (context) ->

  context.test "Status events", (context) ->
    api = yield discover "http://localhost:8080"

    for status in w "starting running failed shutting_down stopped"
      context.test "Status: #{status}", ->
        yield api.status.create
          application_id: "test"
          deployment_id: "deadbeef"
          service: "test-service"
          status: status

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
