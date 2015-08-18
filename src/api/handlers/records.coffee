module.exports =
  create: validate async ({respond, url, data}) ->
    {hostname} = record = build_record (yield data), config
    {change_id, status} = yield route53.set_dns_record record
    extend record, {change_id, status}
    yield records.put hostname, record
    respond 201, "Created", location: url "record", {hostname}
