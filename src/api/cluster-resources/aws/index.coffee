#===============================================================================
# Huxley Agent - Cloud Platform AWS
#===============================================================================
# This is an interface for methods use the raw API functions in api.coffee and
# get us from a deployment's resource request to the proper (and hopefully
# efficient) allocation of resources.

# panda-lib
{async} = require "fairmont"

# internal
ebs = require "./ebs"
ec2 = require "./ec2"
elb = require "./elb"

module.exports = 
