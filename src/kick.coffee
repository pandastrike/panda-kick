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
{readFileSync: read} = require "fs"

# PandaStrike Libraries
{sleep} = require 'fairmont'
{parse} = require 'c50n'

# When Library
{promise, lift} = require "when"
{liftAll} = require "when/node"
async = (require "when/generator").lift

config = parse read (resolve __dirname, "../config/kick.cson")

# Amazon Web Services
api = (require "./route53")(config.AWS)

#=========================
# Helpers
#=========================

# Enforces "fully qualified" form of hostnames.  Idompotent.
fully_qualified = (name) ->
  if name[name.length - 1] == "."
    return name
  else
    return name + "."

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

# We use explicit fields from the HTTP requests for clairity, but we don't
# want to make the end user specify redundant information.  We fill in the gaps here
# to build a complete DNS record.
build_record = (data, method) ->
  # Read credential information stored in kick.cson
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


# To give the server more flexibility, sending a POST request activates this function,
# which will detect whether the DNS record exists or not before making changes.
# It calls 'add' or "update" as approrpriate and doesn't make the user track the state
# of Amazon's DNS records.
set_dns_record = async (record) ->
  # We need to determine if the requested hostname is currently assigned in a DNS record.
  {current_ip_address, current_type} = yield api.get_current_record( record.hostname, record.zone_id)

  if current_ip_address?
    # There is already a record.  Change it.
    params =
      hostname: record.hostname
      zone_id: record.zone_id
      current_ip_address: current_ip_address
      current_type: current_type
      type: record.type
      ip_address: record.ip_address

    return yield api.update_dns_record params
  else
    # No existing record is associated with this hostname.  Create one.
    params =
      hostname: record.hostname
      zone_id: record.zone_id
      type: record.type
      ip_address: record.ip_address

    return yield api.add_dns_record params


#=========================
# Server Definition
#=========================
module.exports = async (request, response)->
  try
    record = build_record parse yield get_data request
    console.log "Request recieved.  The following is used with #{request.method} -", record

    switch request.method
      when "POST"
        {change_id} = yield set_dns_record record
        yield poll_until_true api.get_record_status, change_id, 5000
        response.writeHead 201
        response.write "Done.  Record Synchronized."
        response.end()

      when "DELETE"
        {change_id} = yield api.delete_dns_record record
        yield poll_until_true api.get_record_status, change_id, 5000
        response.writeHead 201
        response.write "Done.  Record Synchronized."
        response.end()

  catch error
    console.log error, error.stack
    response.writeHead 400
    response.write "Apologies. Unable to set DNS record."
    response.end()

