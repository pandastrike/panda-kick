AWS = require "aws-sdk"
{extend} = require "fairmont"
{where} = require "underscore"
{lift} = require "when/node"
async = (require "when/generator").lift

# Allow "when" to lift AWS module functions, which are non-standard.
lift_object = (object, method) ->
  lift object[method].bind object

# Creates a Route53 ChangeBatch given a Zone ID and an array of changes
make_batch = ({zone_id}, changes) ->
  HostedZoneId: zone_id
  ChangeBatch:
    Changes: changes

# Creates a Route53 Change object, given an action and a record
# To be used in a ChangeBatch
make_record = (action, {hostname, type, ip_address}) ->
  {
    Action: action.toUpperCase(),
    ResourceRecordSet:
      Name: hostname,
      Type: type,
      TTL: 60,
      ResourceRecords: [
        {
          Value: ip_address
        }
      ]
  }

# Quick helper functions for creating specific Change records
create_record = (record) -> make_record("create", record)
delete_record = (record) -> make_record("delete", record)

module.exports = (config) ->

  # Update AWS config if settings where passed in
  extend AWS.config, config
  r53 = new AWS.Route53

  # create promisified versions of AWS API calls
  get_change    = lift_object r53, 'getChange'
  list_records  = lift_object r53, 'listResourceRecordSets'
  change_record = lift_object r53, 'changeResourceRecordSets'

  # This function checks the specified DNS record to see if its "INSYC", done updating.
  # It returns either true or false, and throws an exception if an AWS error is reported.
  get_record_status: async (change_id) ->
    data = yield get_change {Id: change_id}

    if data.ChangeInfo.Status == "INSYNC"
      return data
    else
      return false

  # Get the DNS record currently associated with the hostname.
  get_current_record: async (hostname, zone_id) ->
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


  # Add a record to the HostedZone
  add_dns_record: async (record) ->
    params = make_batch record, [ create_record(record) ]

    data = yield change_record params

    result: data
    change_id: data.ChangeInfo.Id

  # Update an existing record in the HostedZone
  update_dns_record: async (record) ->
    params = make_batch record, [
      delete_record
        hostname: record.hostname
        type: record.current_type
        ip_address: record.current_ip_address
      create_record(record)
    ]

    data = yield change_record params

    result: data
    change_id: data.ChangeInfo.Id

  # Delete a record from the HostedZone
  delete_dns_record: async (record) ->
    params = make_batch record, [ delete_record(record) ]

    data = yield change_record params

    result: data
    change_id: data.ChangeInfo.Id

  # To give the server more flexibility, sending a POST request activates this function,
  # which will detect whether the DNS record exists or not before making changes.
  # It calls 'add' or "update" as approrpriate and doesn't make the user track the state
  # of Amazon's DNS records.
  set_dns_record: async (record) ->
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

