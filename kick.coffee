#===============================================================================
# Huxley - Kick Server
#===============================================================================
# This code defines a kick server, a primitive meta API that allows the cluster to
# modify itself when given AWS credentials.

#=========================
# Modules
#=========================
# Core Libraries
http = require 'http'
{resolve} = require "path"
{readFile} = require "fs"

# PandaStrike Libraries
{parse} = require 'c50n'

# Awesome functional toolkit.
{where} = require 'underscore'

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

# Given a URL of many possible formats, return the root domain.
# https://awesome.example.com/test/42#?=What+is+the+answer  =>  example.com.
get_hosted_zone = (url) ->
  try
    # Find and remove protocol (http, ftp, etc.), if present, and get domain

    if url.indexOf("://") != -1
      domain = url.split('/')[2]
    else
      domain = url.split('/')[0]

    # Find and remove port number
    domain = domain.split(':')[0]

    # Now grab the root domain, the top-level-domain, plus what's to the left of it.
    # Be careful of tld's that are followed by a period.
    foo = domain.split "."
    if foo[foo.length - 1] == ""
      domain = "#{foo[foo.length - 3]}.#{foo[foo.length - 2]}"
    else
      domain = "#{foo[foo.length - 2]}.#{foo[foo.length - 1]}"

    # And finally, make the sure the root_domain ends with a "."
    domain = domain + "."
    return domain

  catch error
    return error

# We use explicit fields from the HTTP requests for clairity, but we don't
# want to make the end user specify redundant information.  We fill in the gaps here
# to build a complete DNS record.
build_record = async (data, method) ->

  try
    # Read credential information stored in kick.cson
    config = parse( yield read_file( resolve( __dirname, "kick.cson")))
    console.log data, config
    # Figure out the host zone's ID from the query's hostname field.
    hosted_zone = get_hosted_zone data.hostname
    console.log hosted_zone

    if hosted_zone == config.public_hosted_zone
      console.log "Going Public"
      # Public Record
      return {
        zone_id: config.public_dns_id
        type: "A"
        hostname: data.hostname
        ip_address: data.ip_address
      }
    else if hosted_zone == config.private_hosted_zone
      console.log "Going Private"
      # Private Record
      return {
        zone_id: config.private_dns_id
        type: "SRV"
        hostname: data.hostname
        ip_address: "1 1 #{data.port} #{data.ip_address}"
      }
    else
      throw "Unknown hosted zone.  Cannot modify."

    return {
      zone_id: zone_id
      type: type
      hostname: data.hostname
      ip_address: data.ip_address
    }

  catch error
    return error



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
    console.log "Looking for current_record: #{hostname} #{zone_id}"
    AWS.config = yield configure_aws()
    r53 = new AWS.Route53()
    list_records = lift_object r53, r53.listResourceRecordSets

    data = yield list_records {HostedZoneId: zone_id}

    # We need to conduct a little parsing to extract the IP address of the record set.
    record = where data.ResourceRecordSets, {Name:hostname}

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
            Type: record.type,
            TTL: 60,
            ResourceRecords: [
              {
                Value: record.ip_address
              }
            ]
        }
      ]

  try
    data = yield change_record params
    return {
      result: data
      change_id: data.ChangeInfo.Id
    }

  catch error
    console.log error

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
            Type: record.type,
            TTL: 60,
            ResourceRecords: [
              {
                Value: record.ip_address
              }
            ]
        }
      ]

  try
    data = yield change_record params
    return {
      result: data
      change_id: data.ChangeInfo.Id
    }

  catch error
    console.log error

# Update an existing record in the HostedZone
update_dns_record = async (record) ->
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
            Type: record.current_type,
            TTL: 60,
            ResourceRecords: [
              {
                Value: record.current_ip_address
              }
            ]
        }
        {
          Action: "CREATE",
          ResourceRecordSet:
            Name: record.hostname,
            Type: record.type,
            TTL: 60,
            ResourceRecords: [
              {
                Value: record.ip_address
              }
            ]
        }
      ]

  try
    data = yield change_record params
    console.log "Updating Record", data
    return {
      result: data
      change_id: data.ChangeInfo.Id
    }

  catch error
    console.log error

# To give the server more flexibility, sending a POST request activates this function,
# which will detect whether the DNS record exists or not before making changes.
# It calls 'add' or "update" as approrpriate and doesn't make the user track the state
# of Amazon's DNS records.
set_dns_record = async (record) ->
  # We need to determine if the requested hostname is currently assigned in a DNS record.
  {current_ip_address, current_type} = yield get_current_record( record.hostname, record.zone_id)

  console.log "Current IP Address is : #{current_ip_address}"

  if current_ip_address?
    console.log "Updating Record"
    # There is already a record.  Change it.
    params =
      hostname: record.hostname
      zone_id: record.zone_id
      current_ip_address: current_ip_address
      current_type: current_type
      type: record.type
      ip_address: record.ip_address

    return yield update_dns_record params
  else
    console.log "Adding Record"
    # No existing record is associated with this hostname.  Create one.
    params =
      hostname: record.hostname
      zone_id: record.zone_id
      type: record.type
      ip_address: record.ip_address

    return yield add_dns_record params

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
    record = yield build_record parse yield get_data request
    console.log record

    switch request.method
      when "POST"
        console.log "Using POST method."
        {change_id} = yield set_dns_record record
        console.log "Change is Scheduled: change_id"
        response.writeHead 201
        response.write "Record Added.  Waiting for DNS update."

        yield poll_until_true get_record_status, change_id, 5000
        response.write "Done.  Record Synchronized."
        response.end()

      when "DELETE"
        {change_id} = yield delete_dns_record record
        response.writeHead 201
        response.write "Record Deleted.  Waiting for DNS update."

        yield poll_until_true get_record_status, change_id, 5000
        response.write "Done.  Record Synchronized."
        response.end()

  catch error
    response.writeHead 400
    response.write "Apologies. Unable to set DNS record."
    response.end()


#=========================
# Launch Server
#=========================
http.createServer(kick).listen(80)
console.log '===================================='
console.log '  The server is online and ready.'
console.log '===================================='
