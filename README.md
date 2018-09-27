### summary
graylog + compose for post-loading `/var/log/messages*` files from centos 7 default logging config.

### deploy

```
docker-compose up -d -p graylog/docker-compose.yml
```

### configure

```
./graylog/configure.sh
```

**notes:**
- had to use a pipeline because extractors can't set timestamp (to originally-logged time)
- graylog 3.0 content packs support pipelines and a bunch of other stuff, so this section may eventually simplify to "apply this content pack".

**todo:**
- multiline parsing for kernel splats and ooms.
- additional pipelines

### load

> **Note**: pipeline rule configured in `configure.sh` needs to match schema of input.

assuming directory structure:

```
qa/vmware/manager/$HOSTNAME/messages.gz
prod/aws/worker/$HOSTNAME/messages.gz
```

do something like:

```
#!/usr/bin/env sh

node_id=$(curl -su admin:admin http://127.0.0.1:9000/api/cluster |jq '.[]|.node_id' -r)
for file in */*.tar.gz; do
  echo $file;
  infrastructure=$(echo $file|cut -d/ -f1|sed 's:.$::');
  environment=$(echo $file|cut -d/ -f2|sed 's:.$::');
  swarm_role=$(echo $file|cut -d/ -f3|sed 's:.$::');
  tar -xOf $file var/log/messages | nl -s" ${infrastructure} ${environment} ${swarm_role} " | pv -brL 4M | nc localhost 5555;
  journal_utilization=$(curl -su admin:admin http://127.0.0.1:9000/api/cluster/${node_id}/journal |jq '.journal_size/.journal_size_limit*100'|cut -d'.' -f1)
  while [ $journal_utilization -gt 10 ]; do
    echo journal utilization ${journal_utilization}%.  waiting to be 10% or lower.
    sleep 10
    journal_utilization=$(curl -su admin:admin http://127.0.0.1:9000/api/cluster/${node_id}/journal |jq '.journal_size/.journal_size_limit*100'|cut -d'.' -f1)
  done
done
```

**notes:**
- `lineno` inserted to enable ordering of query results.  Neither syslog nor event-received timestamps are sufficiently precise to reliably distinguish "events" arriving at 10kHz. using file line number for ordering may be brittle for logs in the transition between files from the same origin host.
- `pv` rate limits to prevent drops due to journal overflow.  beats can't introduce line numbers and raw doesn't support backpressure.  wait between files until journal recovers to 10% before proceeding to next file.
    - tune the `pv` rate limit for your hardware if you like. journal depth can be monitored in the graylog web ui under `System > Nodes > Details`, or in a terminal:

        ```
        node_id=$(curl -su admin:admin http://127.0.0.1:9000/api/cluster |jq '.[]|.node_id' -r)
        watch "curl -su admin:admin http://127.0.0.1:9000/api/cluster/${node_id}/journal |jq '100*.journal_size/.journal_size_limit'"
        ```
    - `pv` rate can be changed on a running instance with `pv -R$(ps h -o pid -C pv) -L ${NEW_RATE}M`

**todo:**
* develop an input strategy that supports realtime backpressure *and* file line numbering.  
  - can beats read from a socket or named pipe?
  - or send the whole for loop through `pv`, monitor journal, and slow down `pv` if journal gets too deep
* test if pipeline `set_fields` is faster than individual `set_field` calls
* how hard is it to scale ES?

### login

* http://localhost:9000
* login: `admin:admin`
