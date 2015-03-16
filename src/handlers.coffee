async = (require "when/generator").lift
{validate} = (require "pbx").filters
{resolve} = require "path"
{extend} = require "fairmont"
{Memory} = require "pirate"
{build_record, load} = require "./helpers"

# Temporary storage for records and their change IDs
adapter = Memory.Adapter.make()

module.exports = async ->

  config = yield load (resolve __dirname, "../config/kick.cson")
  route53 = (require "./route53")(config.AWS)
  records = yield adapter.collection "records"

  records:
    create: validate async ({respond, url, data}) ->
      {hostname} = record = build_record (yield data), config
      {change_id} = yield route53.set_dns_record record
      extend record, {change_id}
      yield records.put hostname, record
      respond 201, "Created", location: url "record", {hostname}

  record:
    get: async ({respond, match: {path: {hostname}}}) ->
      record = yield records.get hostname

      if record? # if record exists, check its status
        {status} = yield route53.get_record_status record.change_id
        extend record, {status}
        # TODO: is there a nicer way to filter out only fields we want?
        respond 200,
          hostname: record.hostname
          ip_address: record.ip_address
          port: record.port
          type: record.type
          status: record.status

      else
        respond.not_found()

    put: validate async ({respond, data, match: {path: {hostname}}}) ->
      record = yield records.get hostname

      if record?
        {hostname} = record = build_record (yield data), config
        {change_id} = yield route53.set_dns_record record
        extend record, {change_id}
        yield records.put hostname, record
        respond 200, "Updated"

      else
        respond.not_found()

    delete: async ({respond, match: {path: {hostname}}}) ->
      record = yield records.get hostname

      if record?
        yield route53.delete_dns_record record
        yield records.delete hostname
        respond 200, "Deleted"

      else
        respond.not_found()
