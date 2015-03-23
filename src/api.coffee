{Builder} = require "pbx"
builder = new Builder "kick"

builder.define "records"
.post as: "create", creates: "record"

builder.define "record", template: "/record/:hostname"
.get()
.put()
.delete()
.schema
  required: ["hostname", "ip_address", "type"]
  properties:
    hostname: type: "string"
    ip_address: type: "string"
    port: type: "integer"
    type: type: "string"

builder.define "status"
.post as: "create", creates: "status"
.schema
  required: ["service", "status", "application_id", "deployment_id"]
  properties:
    service: type: "string"
    application_id: type: "string"
    deployment_id: type: "string"
    status: type: "string"
    details: type: "object"

builder.reflect()

module.exports = builder.api

