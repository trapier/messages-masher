## summary
graylog + compose for post-loading `/var/log/messages*` files from centos 7 default logging config.

### deploy

```
docker-compose up -d
```

### configure

* http://localhost:9000
* login: `admin:admin`

1. raw global tcp input on `5555`

2. pipeline rule

    ```
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
- `pv` rate limits to prevent drops.  beats can't introduce line numbers and raw doesn't support backpressure.  watch the journal stats in the graylog ui and tune it for your instance if you like.
- `lineno` inserted enable ordering in query results, because syslog timestamps are not precise enough to uniquely identify each message. this technique becomes brittle when multiple files are loaded from the same host.
