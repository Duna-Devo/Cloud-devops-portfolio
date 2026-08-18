# Gate Check — Network Architecture

- VM1: only machine with a public IP. Accessed via SSM Session Manager — no port 22 exposed.
- VM2 & VM3: no public IP. SSH only accepted from VM1's private IP.
- NAT Gateway: gives VM2/VM3 outbound-only internet access for package installs, with zero inbound exposure.
- VM3 -> VM2: proves internal private-network connectivity without any internet exposure on either machine.



```mermaid
flowchart TB
    You((You / laptop)) -.SSM.-> VM1[VM1 — public entry point]
    subgraph Private["Private network — no internet exposure"]
        VM2[VM2 — runs nginx]
        VM3[VM3 — fetches VM2's page]
    end
    VM1 -.SSH.-> VM2
    VM1 -.SSH.-> VM3
    VM3 -->|curl| VM2
```
