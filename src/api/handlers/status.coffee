module.exports =
  create: validate async ({respond, data}) ->
    status = yield data
    status.cluster_id = config.cluster_id
    status.timestamp = Date.now()
    yield huxley_api?.status.post status
    respond 201, "Created"
