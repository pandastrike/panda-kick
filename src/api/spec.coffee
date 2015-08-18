#===============================================================================
# Huxley Agent - API Specification
#===============================================================================
# We're building the Agent's API with PBX.  This document outlines the
# capabilities of the cluster's agent and how to form requests and responses.

{Builder} = require "pbx"
builder = new Builder "kick"

builder.define "records"
.post as: "create", creates: "record"

#builder.define "record", template: "/record/:hostname"


builder.reflect()

module.exports = builder.api
