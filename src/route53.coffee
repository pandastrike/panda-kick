AWS = require 'aws-sdk'
{read} = require "fairmont"
{parse} = require 'c50n'
{resolve} = require 'path'
node_lift = (require "when/node").lift
async = (require "when/generator").lift

# Allow "when" to lift AWS module functions, which are non-standard.
lift_object = (object, method) ->
  node_lift method.bind object

# Returns the parameters to AWS.config so the server can access the user's account.
configure_aws = async ->
  config = parse yield read (resolve __dirname, "../config/kick.cson")

  return {
    accessKeyId: config.id
    secretAccessKey: config.key
    region: config.region
    sslEnabled: true
  }

module.exports =
  # This function checks the specified DNS record to see if its "INSYC", done updating.
  # It returns either true or false, and throws an exception if an AWS error is reported.
  get_record_status: async (change_id, creds) ->
    AWS.config = yield configure_aws()
    r53 = new AWS.Route53()
    get_change = lift_object r53, r53.getChange

    data = yield get_change {Id: change_id}

    if data.ChangeInfo.Status == "INSYNC"
      return data
    else
      return false

  # Get the DNS record currently associated with the hostname.
  get_current_record: async (hostname, zone_id) ->
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
  add_dns_record: async (record) ->
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

  # Update an existing record in the HostedZone
  update_dns_record: async (record) ->
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

  # Delete a record from the HostedZone
  delete_dns_record: async (record) ->
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
