#!/bin/bash
# Runs on VM1 (public — the only machine with a public IP, entry point via SSM).
# Note: this nginx install was not strictly required by the architecture —
# VM1's real role is as the SSH jump point into VM2/VM3. Kept here as a
# record of what was actually run during the build.

sudo yum install nginx -y
sudo systemctl start nginx
sudo systemctl enable nginx
curl localhost
