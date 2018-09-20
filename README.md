### summary
graylog + compose for post-loading `/var/log/messages*` files from centos 7 default logging config.

### deploy

```
docker-compose up -d
```

### configure

```
./configure.sh
```

notes:
- graylog 3.0 content packs support pipelines and a bunch of other stuff, so this section will become "apply this content pack".
- had to use a pipeline because extractors can't set timestamp

todo:
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

notes:
- `lineno` inserted to enable ordering in query results, because syslog timestamps are not precise enough to uniquely identify each message. this technique becomes brittle when multiple files are loaded from the same origin host.
- `pv` rate limits to prevent drops.  beats can't introduce line numbers and raw doesn't support backpressure.  wait between files until journal recovers to 10% before proceeding to next file as a saftey.
- watch the journal stats in the graylog ui and tune it for your instance if you like. how to watch journal stats:

    ```
    node_id=$(curl -su admin:admin http://127.0.0.1:9000/api/cluster |jq '.[]|.node_id' -r)
    watch "curl -su admin:admin http://127.0.0.1:9000/api/cluster/${node_id}/journal |jq '100*.journal_size/.journal_size_limit'"
    ```

### login

* http://localhost:9000
* login: `admin:admin`
