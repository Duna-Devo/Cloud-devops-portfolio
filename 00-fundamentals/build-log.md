# Gate Check — Build Log

A step-by-step record of how the gate check was actually built, including the real issues hit and how each was diagnosed and fixed.

## 1. Connecting VM1 to VM2 and VM3

VM1 was reached via SSM Session Manager (browser-based, no SSH). From inside VM1's session, SSH was used to reach VM2 and VM3 over their private IPs, using a shared key (`hop-key.pem`).

**Bug 1 — corrupted key:** the key's contents were copy-pasted from the local machine into a file on VM1 (`nano ~/hop-key.pem`). The first paste was incomplete/corrupted, missing proper `BEGIN`/`END` markers, causing SSH to reject it outright. Fixed by deleting the file and re-pasting the key content cleanly.

**Bug 2 — wrong file permissions:** even with a valid key, SSH refused to use it, reporting "bad permissions." SSH requires a private key to be readable only by its owner. Fixed with `chmod 400 ~/hop-key.pem`.

Once both were resolved, `ssh -i ~/hop-key.pem ec2-user@<private-ip>` succeeded from VM1 into both VM2 and VM3.

## 2. Installing nginx on VM2 — NAT Gateway required

`sudo yum install nginx -y` initially failed on VM2 with repository timeout errors. Root cause: VM2 sits in a fully private subnet with no route to the internet, so it could not reach package repositories at all.

**Fix:** provisioned a NAT Gateway in the public subnet, with an Elastic IP, and updated the private subnet's route table to send outbound traffic (`0.0.0.0/0`) through it. This gives private instances outbound-only internet access — they can request and receive responses, but nothing can initiate a connection inbound. After this, the nginx install succeeded.

## 3. VM3 → VM2 connectivity — security group fix

`curl <VM2-private-ip>` from VM3 initially timed out. VM2's security group only allowed inbound traffic from VM1's private IP — VM3 was not authorized.

**Fix:** added an inbound rule to VM2's security group allowing HTTP (port 80) from VM3's private IP specifically. After this, `curl` from VM3 successfully returned VM2's nginx welcome page.

## 4. Deliberate break/fix cycle

On VM2, `nginx` was stopped intentionally:
```bash
sudo systemctl stop nginx
```

Diagnosed as if walking in cold, using only logs and system state — no prior knowledge assumed:
```bash
sudo systemctl status nginx
sudo journalctl -u nginx -n 30 --no-pager
sudo ss -tlnp | grep :80
```

Restarted:
```bash
sudo systemctl start nginx
sudo systemctl status nginx
```

Verified the fix from VM3 (the actual dependent machine), not from VM2 itself:
```bash
curl <VM2-private-ip>
```

Confirmed the page loaded again — proving the fix worked end-to-end, not just locally on VM2.
