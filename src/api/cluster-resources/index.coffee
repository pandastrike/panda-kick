#===============================================================================
# Huxley Agent - Cluster Resource Interface
#===============================================================================
# Huxley clusters may contain any combination of cloud provider resources.  This
# provides an interface to allocate them as desired.

module.exports =

  allocate: async () ->

  check: async () ->


  # Cloud Platforms
  aws: require "./aws"
