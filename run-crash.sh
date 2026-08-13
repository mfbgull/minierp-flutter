#!/usr/bin/env bash
cd /media/fawad/26F2EFA7F2EF7987/D/minierp-flutter
setsid bash -c 'python3 verify-crash.py > /tmp/drp/crash.log 2>&1; echo $? > /tmp/drp/crash-exit' > /dev/null 2>&1 &
echo $! > /tmp/drp/crash-pid
echo "started pid $(cat /tmp/drp/crash-pid)"
