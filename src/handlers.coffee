async = (require "when/generator").lift
{validate} = (require "pbx").filters
{resolve} = require "path"
{Memory} = require "pirate"
{build_record, load_config} = require "./helpers"

config = load_config (resolve __dirname, "../config/kick.cson")

route53 = (require "./route53")(config.AWS)
adapter = Memory.Adapter.make()

module.exports = async ->

  records = yield adapter.collection "records"

  records:
    create: validate async ({respond, url, data}) ->
      record = build_record (yield data), config
      {change_id} = yield route53.set_dns_record record
      extend record, {change_id}
      yield records.put record.hostname, record
      respond 201, "Created"

  record:
    get: async ({respond, match: {path: {hostname}}}) ->
      route53.get_record_status change_id
      record = yield records.get hostname
      respond 200, record

    put: validate async ({respond, data, match: {path: {hostname}}}) ->
      yield records.put hostname, (yield data)
      respond 200, "Updated"

    delete: async ({respond, match: {path: {hostname}}}) ->
      yield records.delete hostname
      respond 200, "Deleted"

