#===============================================================================
# Huxley Agent - AWS API Access
#===============================================================================
# This module grants the user access to AWS via promises that wrap the aws-sdk.
AWS = require "aws-sdk"

# aws-sdk is a little odd.  We must instantiate a given library before we may
# access its methods.  This helper allows when.js to "lift" this quirky library.
lift = (object, method) -> (require "when/node").lift method.bind object

module.exports = (creds) ->
  # Generate a configuration object for AWS.
  AWS.config = creds

  # Instantiate each needed service's library so we may access their methods.
  ec2 = new AWS.EC2()
  r53 = new AWS.Route53()
  ecs = new AWS.ECS()

  # Return an object containing a library of promise wrapped functions.  This
  # will be our Swiss Army Knife for accessing the AWS API.
  return {
    ec2:
      create_tags: lift ec2, ec2.createTags
      describe_instances: lift ec2, ec2.describeInstances
      describe_key_pairs: lift ec2, ec2.describeKeyPairs
      describe_spot_instance_requests: lift ec2, ec2.describeSpotInstanceRequests
      describe_vpcs: lift ec2, ec2.describeVpcs
      run_instances: lift ec2, ec2.runInstances
      terminate_instances: lift ec2, ec2.terminateInstances
    ecs:
      create_cluster: lift ecs, ecs.createCluster
      delete_cluster: lift ecs, ecs.deleteCluster
      describe_clusters: lift ecs, ecs.describeClusters
    route53:
      change_resource_record_sets: lift r53, r53.changeResourceRecordSets
      create_hosted_zone: lift r53, r53.createHostedZone
      delete_hosted_zone: lift r53, r53.deleteHostedZone
      get_change: lift r53, r53.getChange
      list_hosted_zones: lift r53, r53.listHostedZones
      list_resource_record_sets: lift r53, r53.listResourceRecordSets
  }
