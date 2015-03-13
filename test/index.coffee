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
  type: "A"

describe "Kick Server", (context) ->

  context.test "Add DNS record", ->
    api = yield discover "http://localhost:8080"

    {response: headers: {location}} =
      yield api.records.create TestRecord

    record = (api.record location)

    context.test "Get DNS record", (context) ->
      {data} = yield record.get()
      new_record = yield data
      for key of TestRecord
        assert.equal new_record[key], TestRecord[key]

      context.test "Poll for changes", ->
        loop
          console.log "Waiting for DNS changes to synchronize. This may take a while."
          {data} = yield record.get()
          {status} = yield data
          if status == "PENDING"
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

