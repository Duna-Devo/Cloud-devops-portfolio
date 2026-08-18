#!/bin/bash
# Runs on VM2 (private — no public IP, reachable only from VM1's private IP).
# This is the actual target of the exercise: a web server running on a
# fully private machine, reachable only from inside the network.
# Required a NAT Gateway to be added first — see build-log.md — since a
# private subnet has no route to the internet for package installs by default.
# --disablerepo=kernel-livepatch skips a repo that repeatedly timed out
# during install, blocking the whole process.


sudo yum install nginx -y --disablerepo=kernel-livepatch
sudo systemctl start nginx
sudo systemctl enable nginx
curl localhost
