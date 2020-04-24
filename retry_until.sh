#!/bin/bash
# Author:	@vipink1203
# Web: www.vipinkumar.me
# UseCase: Script to run a command in loop with different values but if it fails then it should retry the same again in 10 secs
# LastEdited:	1 Apr 2020


months=(5 6 7 8 9 10 11 12)
for month in "${months[@]}";
do
  total_days=`cal "${month}" 2020 | awk 'NF {DAYS = $NF}; END {print DAYS}'`

  for (( i = 1; i <= ${total_days}; i++));
  do
    until php artisan cron:create_email --asof="2020-${month}-${i}"; do
        echo Server not reachable, retrying in 10 seconds...
        sleep 10
    done
  done
done
