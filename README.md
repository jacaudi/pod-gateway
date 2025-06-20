# pod-gateway

This container includes scripts used to route traffic from pods through another gateway pod. Typically
the gateway pod then runs a openvpn client to forward the traffic.

The connection between the pods is done via a VXLAN. The gateway provides a DHCP server to let client
pods to get automatically an IP.

Outgoing traffic is masqueraded (SNAT). It is also possible to define port forwarding so ports of client
pods can be reached from the outside.

The [.github](.github) folder will get PRs from this template so you can apply the latest workflows.

## Design

Client pods are connected through a tunnel to the gateway pod and route default traffic and DNS queries
through it. The tunnel is implemented as VXLAN overlay.

This container provides the required init/sidecar containers for clients and gateway pods:
- client pods connecting through gateway pod:
   - [client_init.sh](bin/client_init.sh): starts the VXLAN tunnel and change the default gateway
     in the pod. It can get its IP via DHCP or use an static IP within the VXLAN (needed for port)
     forwarding.
   - [client_sidecar.sh](bin/client_sidecar.sh): periodically checks connection to the gateway is still
     working. Reset the VXLAN if this is not the case. This happens, for example, when the gateway pod
     is restarted and it gets a new IP from K8S.
- gateway pod:
   - [gateway_init.sh](bin/gateway_init.sh): creates the VXLAN tunnel and set traffic forwarding rules.
     Optionally, if a VPN is used in the gateway, blocks non VPN outbound traffic.
   - [gateway_sidecar.sh](bin/gateway_sidecar.sh): deploys a DHCP and DNS server

Settings are expected in the `/config` folder - see examples under [config](config):
- [config/settings.sh](config/settings.sh): variables used by all helper scripts
- [config/nat.conf](config/nat.conf): static IP and nat rules for pods exposing ports through the gateway (and optional VPN) pod
Default settings might be overwritten by attaching a container volume with the new values to the helper pods.

## Container Package Overview

The container image includes the following packages:

- **coreutils**: Provides full-featured chown and chmod.
- **dnsmasq-dnssec**: DNS & DHCP server with DNSSEC support.
- **iproute2**: Provides advanced networking tools (e.g., bridge, ip, etc.).
- **bind-tools**: Includes dig and other DNS utilities.
- **inotify-tools**: Provides inotifyd, used for monitoring resolv.conf changes for dnsmasq reload circumvention.
- **iptables/ip6tables**: For firewall and NAT rules (IPv4 and IPv6).
- **curl, wget**: For external IP checks and debugging.

These packages are required for the pod-gateway's networking, DNS, DHCP, and firewall functionality.

## Container Image

The container image is published to GitHub Container Registry (GHCR):

- **Image:** `ghcr.io/jacaudi/pod-gateway:latest` 
- **Tags:** `latest` (on every merge to `main`), and semantic version tags (e.g., `v1.2.3`) on release.
- **Builds:** Multi-arch (amd64, arm64). Built and published automatically by GitHub Actions workflows.

## Helm Chart

A Helm chart is provided for easy deployment and configuration in Kubernetes:

- **Chart Repository:** OCI (GHCR): `ghcr.io/jacaudi/charts/pod-gateway-chart` 
- **Tags:** `latest` and semantic version tags (e.g., `v1.2.3`).
- **Installation:**
  ```sh
  helm pull oci://ghcr.io/jacaudi/charts/pod-gateway-chart --version <version>
  helm install pod-gateway oci://ghcr.io/jacaudi/charts/pod-gateway-chart --version <version> [--values my-values.yaml]
  ```
- **Configuration:**
  - All configurable values are in `values.yaml` in the chart directory.
  - See the chart's `README.md` for detailed configuration options and examples.

## Example: Minimal Custom Values (with all required settings)

```yaml
settings:
  # VXLAN configuration (required)
  VXLAN_ID: 42
  VXLAN_IP_NETWORK: "172.20.0.0/24"
  VXLAN_GATEWAY_FIRST_DYNAMIC_IP: 20
  GATEWAY_NAME: pod-gateway

  # VPN and routing (optional but recommended for VPN setups)
  VPN_INTERFACE: tun0
  VPN_BLOCK_OTHER_TRAFFIC: false
  VPN_TRAFFIC_PORT: 1194
  VPN_LOCAL_CIDRS: "10.0.0.0/8 192.168.0.0/16"

  # DNS and routing
  DNS_LOCAL_CIDRS: "local"
  NOT_ROUTED_TO_GATEWAY_CIDRS: ""

# Top-level chart values
DNS: "172.16.0.1,172.16.0.2"
DNSPolicy: None
clusterName: "cluster.local"

# Port forwarding (optional)
publicPorts: []
publicPortsV6: []

# VPN add-on (optional)
addons:
  vpn:
    enabled: false
    type: openvpn
    # networkPolicy, etc.

# CoreDNS and advanced settings (optional)
coredns:
  bindAddress: "127.0.0.2"
  logClass: "error"
  upstreamDns: "tls://9.9.9.9 tls://149.112.112.112"
  tlsServerName: "dns.quad9.net"
  clusterDns: "172.17.0.10"
```

> See the chart's `values.yaml` and `README.md` for all available configuration options and detailed descriptions.

## Workflows

This repository uses GitHub Actions for CI/CD automation:

- **Linting:**
  - Lints Helm charts on PRs to `main` and on all branches except `main` (not on tags).
- **Testing & Rendering:**
  - Renders Helm templates and runs integration/unit tests on PRs to `main` and on all branches except `main` (not on tags).
- **Release:**
  - Publishes the Helm chart as an OCI artifact to GHCR and updates GitHub Pages on merges to `main` and on tag pushes.
- **Container Image:**
  - Builds and pushes the container image to GHCR as `latest` on merges to `main` and as a versioned tag on tag pushes.
- **Renovate:**
  - Keeps dependencies up to date via scheduled Renovate runs.

