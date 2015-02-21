# panda-kick
Sidekick Server For Huxley Clusters - Cluster Agent with AWS Credentials

## Definition
This repository defines the kick API server. (short for sidekick).  It's a primitive, meta API server that allows the cluster to alter itself independently of a remote actor.  The kick server is Dockerized and available from pandastrike/pc_kick.

## Design
The kick server is a simple Node server.  Thanks to AWS SecurityGroups, the kick server is not exposed to the public Internet, so it may be queried by services via unsecured HTTP requests.  Services are self-describing and make configuraton requests.  Because the kick server possesses your AWS credentials (passed in during cluster formation), it acts as your proxy agent and makes adjustments to your account.  You'll never have to fuss over the AWS Console to get a service setup.

In the current iteration, kick server is very simple and only makes changes to the cluster's private and public DNS records.  But even this allows us to establish arbitrary network toplogies.  As the Huxley feature-set grows, panda-kick will grow more sophisticated.


### Structure of a DNS change request:
```bash
curl -XPOST kick.<private_domain>:2000 -d ' 
"hostname": "<hostname>",
"ip_address": "<ip_address>",   #  Usually ${COREOS_PRIVATE_IPV4} in the .service file
"port": "<port>",  
"type": "<type>"'               # Almost always "A", but also accepts SRV
```
