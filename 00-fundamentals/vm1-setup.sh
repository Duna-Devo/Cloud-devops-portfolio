#!/bin/bash
# VM1 — public entry point. Accessed via SSM Session Manager (no SSH port open).
sudo yum install nginx -y
sudo systemctl start nginx
sudo systemctl enable nginx
curl localhost
