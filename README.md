# Cloud DevOps Portfolio

Hands-on cloud infrastructure projects: AWS, Terraform, Kubernetes, CI/CD.

## Projects

| Stage | Description | Status |
|---|---|---|
| Gate check | 3-VM network: public entry point (VM1) + two fully private machines (VM2, VM3), NAT Gateway for outbound-only access, SSM-based access with zero open SSH ports, deliberate break/fix cycle | Complete |
| AWS CLI two-tier | Manual then scripted two-tier app | Planned |
| Terraform platform | Infrastructure as code | Planned |
| CI/CD pipeline | Containerized deploy pipeline | Planned |
| Kubernetes | EKS platform | Planned |
| Observability | Monitoring & SRE practices | Planned |

## Gate check — write-up

**Goal:** build a public entry point and two fully isolated private machines, prove they can communicate internally, and recover from an induced failure using logs alone.

**What was built:**
- VM1 (public): the only machine with a public IP. Accessed exclusively via AWS SSM Session Manager — no SSH port ever opened to the internet.
- VM2 & VM3 (private): no public IP at all. SSH access restricted to VM1's private IP only, via security group rules.
- NAT Gateway: added mid-build after discovering VM2 had no path to install packages — private subnets need outbound internet access for updates, even though they must stay unreachable from outside. Routed VM2/VM3's subnet through the NAT Gateway instead of the internet gateway.

**Real issue hit and resolved:** initial SSH attempts to VM1 timed out consistently. Diagnosed methodically — verified the security group, route table, and instance health were all correct, then ruled out the network by testing over a different connection entirely. Isolated the cause to the laptop's own device-level policy blocking outbound SSH, regardless of network. Resolved by switching to SSM Session Manager, which uses HTTPS instead of SSH — arguably the more production-appropriate choice anyway, since it requires no open inbound port at all.

**Break/fix cycle:** stopped nginx on VM2 deliberately, diagnosed using `systemctl status`, `journalctl`, and `ss -tlnp` as if walking in cold, restarted it, and verified the fix from VM3 — the actual dependent machine — rather than from VM2 itself.

**Files:** see `00-fundamentals/` for setup scripts and the architecture diagram.
