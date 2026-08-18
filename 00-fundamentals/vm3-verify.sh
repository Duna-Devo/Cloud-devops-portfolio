#!/bin/bash
# Runs on VM3 (private — no public IP, reachable only from VM1's private IP).
# This is the actual proof of the exercise: VM3 fetches VM2's page across
# the private network, with neither machine exposed to the internet.
# Required a security group rule allowing VM3 -> VM2 on port 80 — see
# build-log.md.

curl <VM2-private-ip>   # replace with your VM2's actual private IP
