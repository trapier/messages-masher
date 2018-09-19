### summary
graylog + compose for post-loading `/var/log/messages*` files from centos 7 default logging config.

### deploy

```
docker-compose up -d
```

### configure

* http://localhost:9000
* login: `admin:admin`

```
# 1. raw global tcp input on `5555`

curl \
  -u admin:admin \
  -H 'Content-Type: application/json' \
  'http://127.0.0.1:9000/api/system/inputs'  \
  --data '{"title":"raw","type":"org.graylog2.inputs.raw.tcp.RawTCPInput","configuration":{"bind_address":"0.0.0.0","port":5555,"recv_buffer_size":1048576,"tls_cert_file":"","tls_key_file":"","tls_enable":false,"tls_key_password":"","tls_client_auth":"disabled","tls_client_auth_cert_file":"","tcp_keepalive":false,"use_null_delimiter":false,"max_message_size":2097152,"override_source":null},"global":true}'


# 2. pipeline rule

RULE='
rule "parse syslog"
when
  true
then
  set_field("received_timestamp", to_date($message.timestamp));
  let matches = grok(
    pattern: "^%{POSINT:lineno;int} %{WORD:role} %{SYSLOGBASE} ?%{GREEDYDATA:message}", 
    value: to_string($message.message),
    only_named_captures: true
  );
  let ts_string_with_year = concat(to_string(now().year), concat(" ", to_string(matches.timestamp)));
  let new_ts = parse_date(to_string(ts_string_with_year), "YYYY MMM dd HH:mm:ss");
  set_field("timestamp", new_ts);
  set_field("lineno",    matches.lineno);
  set_field("role",      matches.role);
  set_field("source",    matches.logsource);
  set_field("program",   matches.program);
  set_field("message",   matches.message);
end
'
data=$(jq --arg rule "${RULE}" -nr '{"title":"","description":"","source": $rule}')
curl \
  -u admin:admin \
  -H 'Content-Type: application/json' \
  'http://127.0.0.1:9000/api/plugins/org.graylog.plugins.pipelineprocessor/system/pipelines/rule' \
  --data "${data}"


# 3. pipeline 

pipeline_create_reply=$(\
  curl \
  -u admin:admin \
  -H 'Content-Type: application/json' \
  'http://127.0.0.1:9000/api/plugins/org.graylog.plugins.pipelineprocessor/system/pipelines/pipeline' \
  --data '{"title":"parse syslog","description":"","source":"pipeline \"parse syslog\"\nstage 0 match either\nrule \"parse syslog\"\nend"}'
)
pipeline_id=$(jq -r '.id' <<< ${pipeline_create_reply})


# 4. pipeline  connection

curl \
  -u admin:admin \
  -H 'Content-Type: application/json' \
  'http://127.0.0.1:9000/api/plugins/org.graylog.plugins.pipelineprocessor/system/pipelines/connections/to_pipeline' \
  --data '{"pipeline_id":"'${pipeline_id}'","stream_ids":["000000000000000000000001"]}'
```


notes:
- graylog 3.0 content packs support pipelines and a bunch of other stuff, so this section will become "apply this content pack".
- had to use a pipeline because extractors can't set timestamp

todo:
- multiline parsing for kernel splats and ooms.
- additional pipelines 

### load

assuming directory structure:

```
manager/$HOSTNAME/messages.gz
worker/$HOSTNAME/messages.gz
```
do: 
```
for file in */*/messages.gz; do 
  echo $file; 
  role=$(echo $file|cut -d/ -f1|sed 's:.$::');  
  zcat $file |\
    nl -s" $role " |\
    pv -brL 6M |\
    nc localhost 5555
done
```

notes:
- `lineno` inserted to enable ordering in query results, because syslog timestamps are not precise enough to uniquely identify each message. this technique becomes brittle when multiple files are loaded from the same origin host.
- `pv` rate limits to prevent drops.  beats can't introduce line numbers and raw doesn't support backpressure.  watch the journal stats in the graylog ui and tune it for your instance if you like.

