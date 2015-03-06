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
parse_url = (require "url").parse

# PandaStrike Libraries
{read, sleep} = require 'fairmont'
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
# Enforces "fully qualified" form of hostnames.  Idompotent.
fully_qualified = (name) ->
  if name[name.length - 1] == "."
    return name
  else
    return name + "."

# Allow "when" to lift AWS module functions, which are non-standard.
lift_object = (object, method) ->
  node_lift method.bind object

# Repeatedly call "func" until it returns true.  This repeats at fixed intervals.
poll_until_true = async (func, options, creds, duration, message) ->
  while true
    status = yield func options, creds
    if status
      return status         # Complete.
    else
      yield sleep duration  # Not complete. Keep going.


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
    {hostname} = parse_url url

    # Now grab the root domain, the top-level-domain, plus what's to the left of it.
    # Be careful of tld's that are followed by a period.
    parts = hostname.split "."
    if parts[parts.length - 1] == ""
      domain = "#{parts[parts.length - 3]}.#{parts[parts.length - 2]}"
    else
      domain = "#{parts[parts.length - 2]}.#{parts[parts.length - 1]}"

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
    config = parse yield read (resolve __dirname, "../config/kick.cson")
    console.log data, config
    # Figure out the host zone's ID from the query's hostname field.
    hosted_zone = get_hosted_zone data.hostname

    if hosted_zone == config.public_hosted_zone
      # Public Record
      record =
        zone_id: config.public_dns_id
        hostname: fully_qualified data.hostname

      if data.type? && data.type != ""
        record.type = data.type
      else
        record.type = "A"

      if record.type == "A"
        record.ip_address = data.ip_address
      else
        record.ip_address = "1 1 #{data.port} #{data.ip_address}"

      return record


    else if hosted_zone == config.private_hosted_zone
      # Private Record
      record =
        zone_id: config.private_dns_id
        hostname: fully_qualified data.hostname

      if data.type? && data.type != ""
        record.type = data.type
      else
        record.type = "SRV"

      if record.type == "A"
        record.ip_address = data.ip_address
      else
        record.ip_address = "1 1 #{data.port} #{data.ip_address}"

      return record


    else
      throw "Unknown hosted zone.  Cannot modify."

  catch error
    console.log error
    return error



# Returns the parameters to AWS.config so the server can access the user's account.
configure_aws = async ->

  config = parse yield read (resolve __dirname, "../config/kick.cson")

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
      return {
        current_ip_address: null
        current_type: null
      }
    else
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

  if current_ip_address?
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
module.exports = async (request, response)->
  try
    record = yield build_record parse yield get_data request
    console.log "Request recieved.  The following is used with #{request.method} -", record

    switch request.method
      when "POST"
        {change_id} = yield set_dns_record record
        yield poll_until_true get_record_status, change_id, 5000
        response.writeHead 201
        response.write "Done.  Record Synchronized."
        response.end()

      when "DELETE"
        {change_id} = yield delete_dns_record record
        yield poll_until_true get_record_status, change_id, 5000
        response.writeHead 201
        response.write "Done.  Record Synchronized."
        response.end()

  catch error
    console.log error
    response.writeHead 400
    response.write "Apologies. Unable to set DNS record."
    response.end()

