async = (require "when/generator").lift
{validate} = (require "pbx").filters
{resolve} = require "path"
{extend} = require "fairmont"
{Memory} = require "pirate"
{build_record, load} = require "./helpers"

adapter = Memory.Adapter.make()

module.exports = async ->

  config = yield load (resolve __dirname, "../config/kick.cson")
  route53 = (require "./route53")(config.AWS)
  records = yield adapter.collection "records"

  records:
    create: validate async ({respond, url, data}) ->
      {hostname} = record = build_record (yield data), config
      {change_id} = yield route53.set_dns_record record
      extend record, ChangeInfo: Id: change_id
      yield records.put hostname, record
      respond 201, "Created", location: url "record", {hostname}

  record:
    get: async ({respond, match: {path: {hostname}}}) ->
      record = yield records.get hostname

      if record? # if record exists, check its status
        data = yield route53.get_record_status record.ChangeInfo.Id
        extend record, data
        respond 200, record

      else
        respond 404, "Not found"

    put: validate async ({respond, data, match: {path: {hostname}}}) ->
      yield records.put hostname, (yield data)
      respond 200, "Updated"

    delete: async ({respond, match: {path: {hostname}}}) ->
      yield records.delete hostname
      respond 200, "Deleted"

