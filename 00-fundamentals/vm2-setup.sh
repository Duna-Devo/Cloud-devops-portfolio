#!/bin/bash
# VM2 — private (no public IP). Reachable only via SSH from VM1's private IP.
# Outbound internet access provided by a NAT Gateway.
sudo yum install nginx -y --disablerepo=kernel-livepatch
sudo systemctl start nginx
sudo systemctl enable nginx
curl localhost
