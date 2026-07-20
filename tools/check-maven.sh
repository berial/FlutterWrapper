#!/bin/bash
# check-maven.sh - Test connectivity to Maven repositories.
echo "=== maven.google.com ==="
timeout 15 curl -sI -o /dev/null -w "HTTP %{http_code}, time %{time_total}s, redirect %{redirect_url}\n" https://maven.google.com/ 2>&1
echo "=== dl.google.com ==="
timeout 15 curl -sI -o /dev/null -w "HTTP %{http_code}, time %{time_total}s, redirect %{redirect_url}\n" https://dl.google.com/ 2>&1
echo "=== repo.maven.apache.org ==="
timeout 15 curl -sI -o /dev/null -w "HTTP %{http_code}, time %{time_total}s, redirect %{redirect_url}\n" https://repo.maven.apache.org/maven2/ 2>&1
echo "=== plugins.gradle.org ==="
timeout 15 curl -sI -o /dev/null -w "HTTP %{http_code}, time %{time_total}s, redirect %{redirect_url}\n" https://plugins.gradle.org/m2/ 2>&1
echo ""
echo "=== test download AGP pom ==="
timeout 30 curl -s -o /dev/null -w "HTTP %{http_code}, size %{size_download}, time %{time_total}s\n" https://maven.google.com/com/android/application/com.android.application.gradle.plugin/8.11.1/com.android.application.gradle.plugin-8.11.1.pom 2>&1
echo ""
echo "=== proxy env ==="
echo "HTTP_PROXY=$HTTP_PROXY"
echo "HTTPS_PROXY=$HTTPS_PROXY"
