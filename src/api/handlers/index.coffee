#===============================================================================
# Huxley Agent - Handlers
#===============================================================================
# We build the Agent's API with PBX.  Here we initialize the agent's access to
# various resources and pull in all the handlers we've written to carry out the
# Agent's duties.

# panda-lib
{discover} = require("pbx").client
{async} = require "fairmont"

# Third party
log = require("log4js").getLogger() # Server logging

# internal
config = require "../../config"      # Pulls config set in environment variables
AWS = require("../cluster-resources/aws/api")
Database = require "../database"


module.exports = async ->
  # Establish the server's enviornment by initializing its resources.
  try
    env =
      log: log                                 # server logging
      aws: AWS config.aws                      # library of AWS API handers
      db: yield Database.initialize()          # internal database
      huxley: yield discover config.huxley.url # connection to central Huxley API
  catch e
    log.error "Failed to initialize server resources."
    log.error "Please check configuration.  Aborting."
    log.error e
    process.exit()

  env.log.info "Server environment established."

  # Handlers
  deployments: require("./deployments")(env)
  deployment: require("./deployment")(env)

  remotes: require("./remotes")(env)
