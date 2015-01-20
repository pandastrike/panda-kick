#===============================================================================
# Huxley - Kick Server
#===============================================================================
# This code defines a kick server, a primitive meta API that allows the cluster to
# modify itself when given AWS credentials.

#=========================
# Modules
#=========================
# Core Libraries
url = require "url"
http = require 'http'
{resolve} = require "path"

# PandaStrike Libraries
{parse} = require 'c50n'
{read} = require 'fairmont'

# When Library
{promise, lift} = require "when"
{liftAll} = require "when/node"
node_lift = (require "when/node").lift
async = (require "when/generator").lift

# Amazon Web Services
AWS = require 'aws-sdk'


#=========================
# Helpers
#=========================
# Allow "when" to lift AWS module functions, which are non-standard.
lift_object = (object, method) ->
  node_lift method.bind object

# This is a wrap of setTimeout with ES6 technology that forces a non-blocking
# pause in execution for the specified duration (in ms).
pause = (duration) ->
  promise (resolve, reject) ->
    callback = -> resolve()
    setTimeout callback, duration

# Repeatedly call "func" until it returns true.  This repeats at fixed intervals.
poll_until_true = async (func, options, creds, duration, message) ->
  while true
    status = yield func options, creds
    if status
      return status         # Complete.
    else
      yield pause duration  # Not complete. Keep going.


# Promise wrapper around request events that read "data" from the request's body.
get_data = (request) ->
  promise (resolve, reject) ->
    request.setEncoding "utf8"
    .on "data", (chunk) ->
      resolve chunk

# We want to request explicit fields from the http requests for clairity, but AWS
# needs SRV records to have a special format.
build_record = (data) ->

  config = parse( read( resolve( __dirname, "kick.cson")))

  return {
    zone_id: config.zone_id
    hostname: data.hostname
    ip_address: "#{data.priority} #{data.weight} #{data.port} #{data.ip_address}"
  }



# Returns the parameters to AWS.config so the server can access the user's account.
configure_aws = ->

  config = parse( read( resolve( __dirname, "kick.cson")))

  return {
    accessKeyId: config.id
    secretAccessKey: config.key
    region: config.region
    sslEnabled: true
  }

# Get the DNS record currently associated with the hostname.
get_current_record = async (hostname, zone_id) ->
  try
    AWS.config = configure_aws()
    r53 = new AWS.Route53()
    list_records = lift_object r53, r53.listResourceRecordSets

    data = yield list_records {HostedZoneId: zone_id}

    # We need to conduct a little parsing to extract the IP address of the record set.
    record = where data.ResourceRecordSets, {Name:hostname}
    if record.length == 0
      return null
    else
      return {
        current_ip_address: record[0].ResourceRecords[0].Value
        current_type: record[0].Type
      }

  catch error
    return build_error "Unable to access AWS Route 53.", error

# Add a record to the HostedZone
add_dns_record = async (record) ->
  AWS.config = configure_aws()
  r53 = new AWS.Route53()
  change_record = lift_object r53, r53.changeResourceRecordSets

  params =
    HostedZoneId: record.zone_id
    ChangeBatch:
      Changes: [
        {
          Action: "CREATE",
          ResourceRecordSet:
            Name: record.hostname,
            Type: "SRV",
            TTL: 60,
            ResourceRecords: [
              {
                Value: record.ip_address
              }
            ]
        }
      ]

  data = yield change_record params
  if err?
    console.log JSON.stringify err, null, "\t"
  else
    console.log JSON.stringify data, null, "\t"

  return {
    result: data
    change_id: data.ChangeInfo.Id
  }


# Delete a record from the HostedZone
delete_dns_record = async (record) ->
  AWS.config = configure_aws()
  r53 = new AWS.Route53()
  change_record = lift_object r53, r53.changeResourceRecordSets

  params =
    HostedZoneId: record.zone_id
    ChangeBatch:
      Changes: [
        {
          Action: "DELETE",
          ResourceRecordSet:
            Name: record.hostname,
            Type: "SRV",
            TTL: 60,
            ResourceRecords: [
              {
                Value: record.ip_address
              }
            ]
        }
      ]

  data = yield change_record params
  if err?
    console.log JSON.stringify err, null, "\t"
  else
    console.log JSON.stringify data, null, "\t"

  return {
    result: data
    change_id: data.ChangeInfo.Id
  }


# Update an existing record in the HostedZone
update_dns_record = async (record) ->
  AWS.config = configure_aws()
  r53 = new AWS.Route53()
  change_record = lift_object r53, r53.changeResourceRecordSets

  {current_ip_address} = yield get_current_record(record.hostname, record.zone_id)

  params =
    HostedZoneId: record.zone_id
    ChangeBatch:
      Changes: [
        {
          Action: "DELETE",
          ResourceRecordSet:
            Name: record.hostname,
            Type: "SRV",
            TTL: 60,
            ResourceRecords: [
              {
                Value: current_ip_address
              }
            ]
        }
        {
          Action: "CREATE",
          ResourceRecordSet:
            Name: record.hostname,
            Type: "SRV",
            TTL: 60,
            ResourceRecords: [
              {
                Value: record.ip_address
              }
            ]
        }
      ]

  data = yield change_record params
  if err?
    console.log JSON.stringify err, null, "\t"
  else
    console.log JSON.stringify data, null, "\t"

  return {
    result: data
    change_id: data.ChangeInfo.Id
  }


# This function checks the specified DNS record to see if its "INSYC", done updating.
# It returns either true or false, and throws an exception if an AWS error is reported.
get_record_status = async (change_id, creds) ->
  AWS.config = configure_aws()
  r53 = new AWS.Route53()
  get_change = lift_object r53, r53.getChange

  data = yield get_change {Id: change_id}

  if data.ChangeInfo.Status == "INSYNC"
    return data
  else
    return false


#=========================
# Server Definition
#=========================
kick = async (request, response)->

  record = build_record parse yield get_data request

  switch request.method
    when "POST"
      {change_id} = yield add_dns_record record
      response.writeHead 201
      response.write "Record Added.  Waiting for DNS update."

      yield poll_until_true get_record_status, change_id, 5000
      response.write "Done."
      response.end()

    when "DELETE"
      {change_id} = yield delete_dns_record record
      response.writeHead 201
      response.write "Record Deleted.  Waiting for DNS update."

      yield poll_until_true get_record_status, change_id, 5000
      response.write "Done."
      response.end()

    when "PUT"
      {change_id} = yield update_dns_record record
      response.writeHead 201
      response.write "Record Updated.  Waiting for DNS update."

      yield poll_until_true get_record_status, change_id, 5000
      response.write "Done."
      response.end()



#=========================
# Launch Server
#=========================
http.createServer(kick).listen(80)
console.log '===================================='
console.log '  The server is online and ready.'
console.log '===================================='
