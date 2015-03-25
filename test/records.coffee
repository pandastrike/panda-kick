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

  console.log "====================================================="
  console.log "This test requires working AWS credentials and"
  console.log "correctly configured private and public hosted zones."
  console.log "If tests fail, check your `config/kick.cson`."
  console.log "====================================================="

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

        assert status == "INSYNC"

        context.test "Update DNS record", (context) ->

          context.test "with same IP address", ->
            yield record.put TestRecord
            {data} = yield record.get()
            {status} = yield data
            assert status == "INSYNC"

          context.test "with different IP address", (context) ->
            yield record.put
              hostname: "test.sparkles.cluster"
              ip_address: "10.11.22.33"
              port: 1234
              type: "A"

            {data} = yield record.get()
            {ip_address, status} = yield data

            assert ip_address == "10.11.22.33"
            assert status == "PENDING"

            context.test "Remove DNS record", ->
              yield record.delete()

