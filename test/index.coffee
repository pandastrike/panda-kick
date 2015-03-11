assert = require "assert"
{describe} = require "amen"
{promise} = require "when"
request = require "supertest"
app = require "../src/kick"

attempt = (fn) ->
  promise (resolve, reject) ->
    done = (err, result) ->
      reject err if err?
      resolve result
    fn done

describe "Kick Server", (context) ->

  context.test "Add DNS record", ->
    yield attempt (done) ->
      request(app)
        .post "/"
        .send
          hostname: "test.sparkles.cluster"
          ip_address: "10.1.2.3"
          port: 1234
          type: "A"
        .expect 201
        .expect /Done/
        .end done

    context.test "Update DNS record", ->
      yield attempt (done) ->
        request(app)
          .post "/"
          .send
            hostname: "test.sparkles.cluster"
            ip_address: "10.11.22.33"
            port: 1234
            type: "A"
          .expect 201
          .expect /Done/
          .end done

      context.test "Remove DNS record", ->
        yield attempt (done) ->
          request(app)
            .delete "/"
            .send
              hostname: "test.sparkles.cluster"
              ip_address: "10.11.22.33"
              port: 1234
              type: "A"
            .expect 201
            .expect /Done/
            .end done


