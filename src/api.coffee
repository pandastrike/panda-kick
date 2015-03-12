{Builder} = require "pbx"
builder = new Builder "kick"

builder.define "records"
.post as: "create", creates: "record"

builder.define "record", template: "/record/:hostname"
.get()
.put()
.delete()
.schema
  required: ["hostname", "ip_address", "port", "type"]
  properties:
    hostname: type: "string"
    ip_address: type: "string"
    port: type: "integer"
    type: type: "string"

builder.reflect()

module.exports = builder.api

