assert = require "assert"
{describe} = require "amen"
{discover} = (require "pbx").client

describe "Kick Server", (context) ->

  context.test "Add DNS record", ->
    api = yield discover "http://localhost:8080"

    {response: headers: {location}} =
      yield api.records.create
        hostname: "test.sparkles.cluster"
        ip_address: "10.1.2.3"
        port: 1234
        type: "A"

    # TODO assert succesful creation
    record = (api.record location)

    context.test "Update DNS record", ->
      yield record.put
        hostname: "test.sparkles.cluster"
        ip_address: "10.11.22.33"
        port: 1234
        type: "A"

      context.test "Remove DNS record", ->
        yield record.delete()


