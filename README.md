# panda-kick

Sidekick Server For Huxley Clusters - Cluster Agent with AWS Credentials

> **Warning:** This is an experimental project under heavy development.  It's awesome and becoming even more so, but it is a work in progress.

## Definition

This repository defines the kick API server (short for sidekick). It's a primitive, meta API server that allows the cluster to alter itself independently of a remote actor.  The kick server is Dockerized and available from pandastrike/pc_kick.

## Design

The kick server is based on [PBX][pbx], Panda Strike's next generation framework for ES6-enabled REST APIs.

Thanks to AWS SecurityGroups, the kick server is not exposed to the public Internet, so it may be queried by services via unsecured HTTP requests.  

Services are self-describing and make configuraton requests.  Because the kick server possesses your AWS credentials (passed in during cluster formation), it acts as your proxy agent and makes adjustments to your account.  You'll never have to fuss over the AWS Console to get a service setup.

In the current iteration, the kick server only allows us to query and modify DNS records. As the Huxley feature-set grows, panda-kick will grow more sophisticated.


## How to use

When using [panda-cluster][pc] or [Huxley][huxley], a kick server will automatically be set up for you, with an internal address of `kick.<cluster_name>.cluster`. You can make requests to the server from anywhere within the the cluster as follows.

### Creating a domain name

```bash
curl -XPOST kick.<private_domain>:2000/records -d '{
"hostname": "<hostname>",       # The hostname to set up
"ip_address": "<ip_address>",   #  Usually ${COREOS_PRIVATE_IPV4} in the .service file
"port": "<port>",               # Only used for SRV records
"type": "<type>"}'              # Almost always "A", but also accepts SRV
```

### Retrieving a domain name and status

```bash
curl -XGET kick.<private_domain>:2000/record/<hostname>
```

### Updating a domain name

```bash
curl -XPUT kick.<private_domain>:2000/record/<hostname> -d '{
"hostname": "<new_hostname>",
"ip_address": "<ip_address>",
"port": "<port>",
"type": "<type>"}'
```

### Removing a domain name

```bash
curl -XDELETE kick.<private_domain>:2000/record/<hostname>
```

[pbx]: https://github.com/pandastrike/pbx
[pc]: https://github.com/pandastrike/panda-cluster
[huxley]: https://github.com/pandastrike/huxley