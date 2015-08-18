#===============================================================================
# Huxley Agent - Configuration
#===============================================================================
# When the container is started, it is provided configruation data we need in
# the form of environment variables.  Grab them all and return as one lump.

module.exports =
  # Config data for the AWS SDK
  aws:
    accessKeyId: process.env.aws_id
    secretAccessKey: process.env.aws_key
    region: process.aws_region
    sslEnabled: true

  # Information about resources belonging to the cluster.
  cluster:
    id: process.env.cluster_id
    dns:
      public:
        id: process.env.dns_public_id
        name: process.env.dns_public_name
      private:
        id: process.env.dns_private_id
        name: process.env.dns_private_name

  # Information about the API and account that spawned this cluster.
  huxley:
    url: process.env.huxley_url
