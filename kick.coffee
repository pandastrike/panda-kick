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
  try

    while true
      status = yield func options, creds
      if status
        return status         # Complete.
      else
        yield pause duration  # Not complete. Keep going.

  catch error
    return build_error message, error


# Returns the parameters to AWS.config so the server can access the user's account.
configure_aws = ->

  config = parse( read( resolve( __dirname, kick.cson)))

  return {
    accessKeyId: config.id
    secretAccessKey: config.key
    region: config.region
    sslEnabled: true
  }

# Add a record to the HostedZone
add_dns_record = async (record) ->
  AWS.config = configure_aws()
  r53 = new AWS.Route53()
  add_record = lift_object r53, r53.changeResourceRecordSets

  params =
    HostedZoneId: record.zone_id
      ChangeBatch:
        Changes: [
          {
            Action: "CREATE",
            ResourceRecordSet:
              Name: record.hostname,
              Type: "A",
              TTL: 60,
              ResourceRecords: [
                {
                  Value: record.ip_address
                }
              ]
          }
        ]

  console.log params
  data = yield add_record params
  if err
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
  AWS.config = set_aws_creds creds
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
  console.log "Made it to the function."
  pathname = url.parse(request.url).pathname
  console.log pathname
  console.log JSON.stringify request, null, "\t"
  if pathname == "/dns"
    record = JSON.parse request.body
    console.log record
    yield add_dns_record record
    #yield poll_until_true get_record_status, change_id, 5000

    response.writeHead 201
    .write "Record Added."
    .end()



#=========================
# Launch Server
#=========================
http.createServer(kick).listen(2000)
console.log '===================================='
console.log '  The server is online and ready.'
console.log '===================================='
