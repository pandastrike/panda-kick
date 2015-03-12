assert = require "assert"
{describe} = require "amen"
{discover} = (require "pbx").client
{sleep} = require "fairmont"

# ----------------------------------------------
# NOTE
# ----------------------------------------------
# This currently creates a REAL entry on Route53
# The hosted zone must already exist, or the test
# will fail.
TestRecord =
  hostname: "test.sparkles.cluster"
  ip_address: "10.1.2.3"
  port: 1234
  type: "A"

describe "Kick Server", (context) ->

  context.test "Add DNS record", ->
    api = yield discover "http://localhost:8080"

    {response: headers: {location}} =
      yield api.records.create TestRecord

    record = (api.record location)

    context.test "Get DNS record", (context) ->
      {data} = yield record.get()
      console.log yield data
      # TODO assert correctness

      context.test "Poll for changes", ->
        console.log "Polling for changes. This may take a while."
        loop
          {data} = yield record.get()
          console.log yield data
          if (yield data).ChangeInfo.Status == "PENDING"
            yield sleep 5000
          else break

        context.test "Update DNS record", ->
          yield record.put
            hostname: "test.sparkles.cluster"
            ip_address: "10.11.22.33"
            port: 1234
            type: "A"

          context.test "Remove DNS record", ->
            yield record.delete()

