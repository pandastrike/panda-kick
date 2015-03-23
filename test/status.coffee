assert = require "assert"
{describe} = require "amen"
{discover} = (require "pbx").client
 
describe "Kick Server", (context) ->

  context.test "Create a status event", ->
    api = yield discover "http://localhost:8080"

    {response: headers: {location}} =
      yield api.status.create
        application_id: "test"
        deployment_id: "deadbeef"
        service: "test-service"
        status: "starting"
