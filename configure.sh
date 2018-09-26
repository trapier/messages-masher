#!/usr/bin/env sh

echo '# 0. wait for graylog api to be available'

until curl -m1 -s http://127.0.0.1:9000/api/system/lbstatus; do
    sleep 5
done

echo
echo '# 1. raw global tcp input on `5555`'

curl -s \
  -u admin:admin \
  -H 'Content-Type: application/json' \
  'http://127.0.0.1:9000/api/system/inputs'  \
  --data '{"title":"raw","type":"org.graylog2.inputs.raw.tcp.RawTCPInput","configuration":{"bind_address":"0.0.0.0","port":5555,"recv_buffer_size":1048576,"tls_cert_file":"","tls_key_file":"","tls_enable":false,"tls_key_password":"","tls_client_auth":"disabled","tls_client_auth_cert_file":"","tcp_keepalive":false,"use_null_delimiter":false,"max_message_size":2097152,"override_source":null},"global":true}'


echo
echo '# 2. pipeline rule'

RULE='
rule "parse syslog"
when
  true
then
  set_field("received_timestamp", to_date($message.timestamp));
  let matches = grok(
    pattern: "^%{POSINT:lineno;int} %{WORD:infrastructure} %{WORD:phase} %{WORD:swarm_role} %{SYSLOGBASE} ?%{GREEDYDATA:message}", 
    value: to_string($message.message),
    only_named_captures: true
  );
  let ts_string_with_year = concat(to_string(now().year), concat(" ", to_string(matches.timestamp)));
  let new_ts = parse_date(to_string(ts_string_with_year), "YYYY MMM dd HH:mm:ss");
  set_field("timestamp",      new_ts);
  set_field("lineno",         matches.lineno);
  set_field("infrastructure", matches.infrastructure);
  set_field("phase",          matches.phase);
  set_field("swarm_role",     matches.swarm_role);
  set_field("source",         matches.logsource);
  set_field("program",        matches.program);
  set_field("message",        matches.message);
end
'
data=$(jq --arg rule "${RULE}" -nr '{"title":"","description":"","source": $rule}')
curl -s \
  -u admin:admin \
  -H 'Content-Type: application/json' \
  'http://127.0.0.1:9000/api/plugins/org.graylog.plugins.pipelineprocessor/system/pipelines/rule' \
  --data "${data}"


echo
echo '# 3. pipeline '

pipeline_create_reply=$(\
  curl -s \
  -u admin:admin \
  -H 'Content-Type: application/json' \
  'http://127.0.0.1:9000/api/plugins/org.graylog.plugins.pipelineprocessor/system/pipelines/pipeline' \
  --data '{"title":"parse syslog","description":"","source":"pipeline \"parse syslog\"\nstage 0 match either\nrule \"parse syslog\"\nend"}'
)
pipeline_id=$(jq -r '.id' <<< ${pipeline_create_reply})


echo
echo '# 4. pipeline  connection'

curl -s \
  -u admin:admin \
  -H 'Content-Type: application/json' \
  'http://127.0.0.1:9000/api/plugins/org.graylog.plugins.pipelineprocessor/system/pipelines/connections/to_pipeline' \
  --data '{"pipeline_id":"'${pipeline_id}'","stream_ids":["000000000000000000000001"]}'

echo
