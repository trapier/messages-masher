#!/usr/bin/env sh

cat > .glogcli.cfg <<-EOCONFIG
	[environment:default]
	host=localhost
	port=9000
	username=admin
	default_stream=000000000000000000000001
	
	[format:default]
	format={source} {role} {message}
	color=false
EOCONFIG

glogcli --no-tls -c .glogcli.cfg -p admin -@0 -n0  "program:kernel AND Killed" |\
\
sed -E 's|([^ ]*) ([^ ]*).*\(([^ ]*)\).*anon-rss:([^k]*).*|\1,\2,\3,\4|'  |\
\
r -e '
library(tidyverse)
options(tibble.width = Inf)
options(width = 1000)
library(pander)
oom_data <- read_csv(file("stdin"), col_names=c("host", "role", "victim", "rss"))
summary <- oom_data %>% group_by(victim) %>% 
  summarise(count = n(),
    "rss min" = min(rss),
    "rss median"  = median(rss),
    "rss max" = max(rss),
    workers   = str_c(unique(host[role == "worker"]), "\n", collapse = ""),
    managers  = str_c(unique(host[role == "manager"]), "\n", collapse = "")
  ) %>% 
  arrange(desc(count))
pandoc.table(summary, 
  style = "multiline",
  keep.line.breaks = TRUE,
  split.table = Inf,
  justify = "right"
)
' 2>/dev/null
