# panda-kick

> **IMPORTANT** This project is no longer under active development.
> Based on what we've learned building this,
> we recommend looking at [Convox][] instead.

[Convox]:https://github.com/convox/rack

Sidekick Server For Huxley Clusters - Cluster Agent with AWS Credentials

## Summary

This repository defines the kick API server (short for sidekick). It's a primitive, meta API server that allows the cluster to alter itself independently of a remote actor.  The kick server is Dockerized and available from pandastrike/pc_kick.

## Design

The kick server is based on [PBX][pbx], Panda Strike's next generation framework for ES6-enabled REST APIs.

Thanks to AWS SecurityGroups, the kick server is not exposed to the public Internet, so it may be queried by services via unsecured HTTP requests.  

Services are self-describing and make configuraton requests.  Because the kick server possesses your AWS credentials (passed in during cluster formation), it acts as your proxy agent and makes adjustments to your account.  You'll never have to fuss over the AWS Console to get a service setup.

In the current iteration, the kick server only allows us to query and modify DNS records. As the Huxley feature-set grows, panda-kick will grow more sophisticated.


## How to use

When using [panda-cluster][pc] or [Huxley][huxley], a kick server will automatically be set up for you, with an internal address of `kick.<cluster_name>.cluster`. You can make requests to the server from anywhere within the the cluster.

## API

> **Note**: the API is still under development and subject to change

The API follows the standard REST design as closely as possible.

For POST and PUT requests, the server expects a JSON payload with a `Content-Type` of `application/vnd.kick.record+json`. A GET requests yields a JSON payload with the same mime type.


### Creating a domain name

```bash
curl -XPOST kick.<cluster_name>.cluster:2000/records -d '{
"hostname": "<hostname>",
"ip_address": "<ip_address>",
"port": "<port>",
"type": "<type>"}'
-H 'Content-Type: application/vnd.kick.record+json'
```

Where

- `<hostname>` is the hostname to be set up
- `<ip_address>` is the IP address of the host
- `<port>` is the port (only used for `SRV` records)
- `<type>` is the record type usually `A`, sometimes `SRV`

### Retrieving a domain name and status

```bash
curl -XGET kick.<cluster_name>.cluster:2000/record/<hostname>
```

Response: 

```
{
  "hostname": "test.sparkles.cluster",
  "type": "A",
  "ip_address": "10.1.2.3",
  "status": "PENDING"
}
```

The `status` field indicates whether the record has been propagated across all DNS servers or not. It can either be `PENDING` or `INSYNC`, the latter indicating that the record has been successfully set and is currently active.

### Polling for status updates

After the record is set, it takes a while until the changes are propagated through the DNS system.
In order to make sure your settings have been made permanent, you can use the following snippet, while polls the server every 5 seconds and stops when the record status indicates the changes have been set.

```bash
until curl kick.<cluster_name>.cluster:2000/record/<hostname> | grep -o 'INSYNC'; do
  sleep 5
done
```

### Updating a domain name

```bash
curl -XPUT kick.<cluster_name>.cluster:2000/record/<hostname> -d '{
"hostname": "<new_hostname>",
"ip_address": "<ip_address>",
"port": "<port>",
"type": "<type>"}' \
-H 'Content-Type: application/vnd.kick.record+json'
```

### Removing a domain name

```bash
curl -XDELETE kick.<cluster_name>.cluster:2000/record/<hostname>
```

[pbx]: https://github.com/pandastrike/pbx
[pc]: https://github.com/pandastrike/panda-cluster
[huxley]: https://github.com/pandastrike/huxley

### Posting a status update

This allows services to share their current status information.

```bash
curl -XPOST kick.<cluster_name>.cluster:2000/status-d '{
"service": "test-service", 
"application_id": "<app_id>",
"deployment_id": "<deploy_id>",
"status":"starting",
"detail": "<optional, object or string>"
}' \
-H 'Content-Type: application/vnd.kick.status+json' 
```

This information will be forwarded to the responsible Huxley API server.

**IMPORTANT**: The `status` field should be one of the following:

- `starting`
- `running`
- `failed`
- `shutting_down`
- `stopped`
