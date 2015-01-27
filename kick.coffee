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
{readFile} = require "fs"

# PandaStrike Libraries
{parse} = require 'c50n'

# Awesome functional toolkit.
{where, without} = require 'underscore'

# When Library
{promise, lift} = require "when"
{liftAll} = require "when/node"
node_lift = (require "when/node").lift
async = (require "when/generator").lift

# Amazon Web Services
AWS = require 'aws-sdk'

#------------------------
# This array holds all ports that are reserved by services.
# This is a temporary measure until a formal database with atomicity is implemented.
occupied_ports = []
#------------------------


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


# This wraps Node's irregular, asynchronous readFile in a promise.
read_file = (path) ->
  promise (resolve, reject) ->
    readFile path, "utf-8", (error, data) ->
      if data?
        resolve data
      else
        resolve error

# Promise wrapper around request events that read "data" from the request's body.
get_data = (request) ->
  promise (resolve, reject) ->
    request.setEncoding "utf8"
    .on "data", (chunk) ->
      resolve chunk

# This function will select an unoccupied port.
select_free_port = (min, max) ->
  for port in [min..max]
    unless port in occupied_ports
      return port


# We want to use explicit fields from the HTTP requests for clairity, but AWS
# needs SRV records to have a special format.
build_record = async (data, method) ->

  # Choose a free port if the user has requested one.
  if data.port == "auto_private"
    data.port = select_free_port 2001, 2999
  if data.port == "auto_public"
    data.port = select_free_port 3001, 3999

  # Read credential information stored in kick.cson
  config = parse( yield read_file( resolve( __dirname, "kick.cson")))

  return {
    port: data.port
    record:
      zone_id: "/hostedzone/#{config.zone_id}"
      hostname: data.hostname
      ip_address: "#{data.priority} #{data.weight} #{data.port} #{data.ip_address}"
  }



# Returns the parameters to AWS.config so the server can access the user's account.
configure_aws = async ->

  config = parse( yield read_file( resolve( __dirname, "kick.cson")))

  return {
    accessKeyId: config.id
    secretAccessKey: config.key
    region: config.region
    sslEnabled: true
  }

# Get the DNS record currently associated with the hostname.
get_current_record = async (hostname, zone_id) ->
  try
    AWS.config = yield configure_aws()
    r53 = new AWS.Route53()
    list_records = lift_object r53, r53.listResourceRecordSets

    data = yield list_records {HostedZoneId: zone_id}

    # We need to conduct a little parsing to extract the IP address of the record set.
    record = where data.ResourceRecordSets, {Name:hostname}

    if record.length == 0
      record = where data.ResourceRecordSets, {Name: "#{hostname}."}
      if record.length == 0
        return null

    return {
      current_ip_address: record[0].ResourceRecords[0].Value
      current_type: record[0].Type
    }

  catch error
    console.log error

# Add a record to the HostedZone
add_dns_record = async (record) ->
  AWS.config = yield configure_aws()
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
  return {
    result: data
    change_id: data.ChangeInfo.Id
  }


# Delete a record from the HostedZone
delete_dns_record = async (record) ->
  AWS.config = yield configure_aws()
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
  return {
    result: data
    change_id: data.ChangeInfo.Id
  }


# Update an existing record in the HostedZone
update_dns_record = async (record) ->
  AWS.config = yield configure_aws()
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
  return {
    result: data
    change_id: data.ChangeInfo.Id
  }


# This function checks the specified DNS record to see if its "INSYC", done updating.
# It returns either true or false, and throws an exception if an AWS error is reported.
get_record_status = async (change_id, creds) ->
  AWS.config = yield configure_aws()
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
  try
    {record, port} = yield build_record parse yield get_data request

    switch request.method
      when "POST"
        {change_id} = yield add_dns_record record
        response.writeHead 201
        response.write "Record Added.  Waiting for DNS update."

        yield poll_until_true get_record_status, change_id, 5000
        occupied_ports.push port
        response.write "Done.   Port #{port} in use."
        response.end()

      when "DELETE"
        {change_id} = yield delete_dns_record record
        response.writeHead 201
        response.write "Record Deleted.  Waiting for DNS update."

        yield poll_until_true get_record_status, change_id, 5000
        occupied_ports = without occupied_ports, port
        response.write "Done.   Port #{port} in use."
        response.end()

      when "PUT"
        {change_id} = yield update_dns_record record
        response.writeHead 201
        response.write "Record Updated.  Waiting for DNS update."

        yield poll_until_true get_record_status, change_id, 5000
        response.write "Done.   Port #{port} in use."
        response.end()

  catch error
    response.writeHead 400
    response.write "Apologies. Unable to set private DNS record."
    response.end()


#=========================
# Launch Server
#=========================
http.createServer(kick).listen(80)
console.log '===================================='
console.log '  The server is online and ready.'
console.log '===================================='
