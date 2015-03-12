async = (require "when/generator").lift
{compose, read, sleep} = require 'fairmont'
{parse} = require 'c50n'

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

module.exports =
  load_config: compose parse, read

  # Repeatedly call "func" until it returns true.  This repeats at fixed intervals.
  poll_until_true: async (func, options, creds, duration, message) ->
    while true
      status = yield func options, creds
      if status
        return status         # Complete.
      else
        yield sleep duration  # Not complete. Keep going.

  # We use explicit fields from the HTTP requests for clairity, but we don't
  # want to make the end user specify redundant information.  We fill in the gaps here
  # to build a complete DNS record.
  build_record: (data, config) ->
    # Enforces "fully qualified" form of hostnames.  Idompotent.
    fully_qualified = (name) ->
      if name[name.length - 1] == "."
        return name
      else
        return name + "."

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

