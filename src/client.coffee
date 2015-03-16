{lift: async} = require "when/generator"
{property} = require "fairmont"
{basename} = require "path"
{discover} = (require "pbx").client

class Client

  constructor: (url) ->
    @api = discover url

  create: async (record) ->
    api = yield @api
    try
      {response: {statusMessage}} = yield api.records.create record
      console.log statusMessage
    catch e
      console.error e.message

  read: async (hostname) ->
    record = (yield @api).record hostname
    {data} = yield record.get()
    console.log yield data

  delete: async (hostname) ->
    record = (yield @api).record hostname
    {data} = yield record.delete()
    console.log yield data

module.exports = Client

