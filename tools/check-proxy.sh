#!/bin/bash
# check-proxy.sh - Diagnose proxy and gradle cache state.
echo "=== proxy env vars ==="
echo "HTTP_PROXY=$HTTP_PROXY"
echo "HTTPS_PROXY=$HTTPS_PROXY"
echo "http_proxy=$http_proxy"
echo "https_proxy=$https_proxy"
echo "ALL_PROXY=$ALL_PROXY"
echo "no_proxy=$no_proxy"
echo ""
echo "=== /etc/resolv.conf ==="
cat /etc/resolv.conf 2>&1
echo ""
echo "=== gradle wrapper dists cache ==="
ls -la ~/.gradle/wrapper/dists/ 2>&1
echo ""
echo "=== test direct gradle download speed ==="
time timeout 30 curl -sI -o /dev/null -w "HTTP %{http_code}, size %{size_download}, time %{time_total}s\n" https://services.gradle.org/distributions/gradle-9.3.1-all.zip 2>&1
