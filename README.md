# Cloud DNS Traffic Steering with Geolocation Policy

A comprehensive implementation of Google Cloud DNS routing policies using geolocation-based traffic steering. This project demonstrates how to configure DNS-based traffic routing to direct users to the nearest server based on their geographic location.

## Video

https://youtu.be/jd64jJgCw5s

## Overview

This project implements Cloud DNS routing policies that enable geographic traffic steering. When users make DNS requests, they are automatically directed to the closest server based on their location, improving performance and user experience.

### Architecture

The setup includes:
- **Client VMs**: Deployed in 3 regions (US, Europe, Asia) for testing
- **Server VMs**: Web servers deployed in 2 regions (US, Europe) 
- **Cloud DNS**: Private zone with geolocation routing policy
- **Traffic Steering**: Automatic routing based on client geographic location

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│ US Client   │    │Europe Client│    │ Asia Client │
│   VM        │    │     VM      │    │     VM      │
└─────────────┘    └─────────────┘    └─────────────┘
       │                   │                   │
       └───────────────────┼───────────────────┘
                           │
                    ┌─────────────┐
                    │  Cloud DNS  │
                    │ Geolocation │
                    │   Policy    │
                    └─────────────┘
                           │
                 ┌─────────┴─────────┐
                 │                   │
        ┌─────────────┐    ┌─────────────┐
        │ US Web      │    │Europe Web   │
        │ Server      │    │ Server      │
        └─────────────┘    └─────────────┘
```

## Features

- **Geolocation-based routing**: Automatic traffic steering based on client location
- **Nearest match fallback**: Clients without exact geographic matches are routed to the nearest server
- **Low TTL configuration**: Fast DNS propagation with 5-second TTL
- **Automated testing**: Scripts to verify routing behavior from different regions
- **Infrastructure as Code**: All resources defined and managed via gcloud commands

## Prerequisites

- Google Cloud Platform account
- `gcloud` CLI installed and configured
- Appropriate IAM permissions for Compute Engine and Cloud DNS
- Basic understanding of DNS concepts

## Quick Start

1. **Clone the repository**
   ```bash
   git clone <your-repo-url>
   cd cloud-dns-geolocation-routing
   ```

2. **Set up your environment**
   ```bash
   # Set your project ID
   export PROJECT_ID="your-project-id"
   gcloud config set project $PROJECT_ID
   ```

3. **Run the complete setup**
   ```bash
   chmod +x scripts/setup.sh
   ./scripts/setup.sh
   ```

4. **Test the configuration**
   ```bash
   chmod +x scripts/test.sh
   ./scripts/test.sh
   ```

## Manual Setup Guide

### Step 1: Enable Required APIs

```bash
# Enable Compute Engine API
gcloud services enable compute.googleapis.com

# Enable Cloud DNS API  
gcloud services enable dns.googleapis.com

# Verify APIs are enabled
gcloud services list | grep -E 'compute|dns'
```

### Step 2: Configure Firewall Rules

```bash
# Allow SSH access via Identity Aware Proxy
gcloud compute firewall-rules create fw-default-iapproxy \
--direction=INGRESS \
--priority=1000 \
--network=default \
--action=ALLOW \
--rules=tcp:22,icmp \
--source-ranges=35.235.240.0/20

# Allow HTTP traffic to web servers
gcloud compute firewall-rules create allow-http-traffic \
--direction=INGRESS \
--priority=1000 \
--network=default \
--action=ALLOW \
--rules=tcp:80 \
--source-ranges=0.0.0.0/0 \
--target-tags=http-server
```

### Step 3: Launch Client VMs

```bash
# US Client
gcloud compute instances create us-client-vm \
--machine-type=e2-micro \
--zone=us-east1-b

# Europe Client  
gcloud compute instances create europe-client-vm \
--machine-type=e2-micro \
--zone=europe-west2-a

# Asia Client
gcloud compute instances create asia-client-vm \
--machine-type=e2-micro \
--zone=asia-south1-a
```

### Step 4: Launch Server VMs with Web Servers

```bash
# US Web Server
gcloud compute instances create us-web-vm \
--machine-type=e2-micro \
--zone=us-east1-b \
--network=default \
--subnet=default \
--tags=http-server \
--metadata=startup-script='#! /bin/bash
 apt-get update
 apt-get install apache2 -y
 echo "Page served from: US Region" | \
 tee /var/www/html/index.html
 systemctl restart apache2'

# Europe Web Server
gcloud compute instances create europe-web-vm \
--machine-type=e2-micro \
--zone=europe-west2-a \
--network=default \
--subnet=default \
--tags=http-server \
--metadata=startup-script='#! /bin/bash
 apt-get update
 apt-get install apache2 -y
 echo "Page served from: Europe Region" | \
 tee /var/www/html/index.html
 systemctl restart apache2'
```

### Step 5: Configure Environment Variables

```bash
# Get internal IP addresses
export US_WEB_IP=$(gcloud compute instances describe us-web-vm \
--zone=us-east1-b \
--format="value(networkInterfaces.networkIP)")

export EUROPE_WEB_IP=$(gcloud compute instances describe europe-web-vm \
--zone=europe-west2-a \
--format="value(networkInterfaces.networkIP)")
```

### Step 6: Create Private DNS Zone

```bash
gcloud dns managed-zones create example \
--description="Geolocation routing test zone" \
--dns-name=example.com \
--networks=default \
--visibility=private
```

### Step 7: Create Geolocation Routing Policy

```bash
gcloud dns record-sets create geo.example.com \
--ttl=5 \
--type=A \
--zone=example \
--routing-policy-type=GEO \
--routing-policy-data="us-east1=$US_WEB_IP;europe-west2=$EUROPE_WEB_IP"
```

## Testing the Configuration

### Test from Europe Client
```bash
gcloud compute ssh europe-client-vm --zone=europe-west2-a --tunnel-through-iap

# Inside the VM:
for i in {1..10}; do echo $i; curl geo.example.com; sleep 6; done
```

Expected output: "Page served from: Europe Region"

### Test from US Client  
```bash
gcloud compute ssh us-client-vm --zone=us-east1-b --tunnel-through-iap

# Inside the VM:
for i in {1..10}; do echo $i; curl geo.example.com; sleep 6; done
```

Expected output: "Page served from: US Region"

### Test from Asia Client
```bash
gcloud compute ssh asia-client-vm --zone=asia-south1-a --tunnel-through-iap

# Inside the VM:
for i in {1..10}; do echo $i; curl geo.example.com; sleep 6; done
```

Expected output: Routed to nearest server (varies based on network topology)

## How It Works

1. **DNS Resolution**: When a client queries `geo.example.com`, Cloud DNS evaluates the request's source location
2. **Geographic Matching**: The routing policy matches the client's location to the configured geographic regions
3. **Nearest Match**: If no exact match exists, the policy routes to the nearest available server
4. **Response**: The client receives the IP address of the appropriate server and connects directly

## Key Configuration Details

- **TTL**: Set to 5 seconds for rapid DNS propagation during testing
- **Policy Type**: GEO (geolocation-based routing)
- **Routing Data**: Semicolon-delimited format: `region=ip_address;region=ip_address`
- **Fallback**: Automatic routing to nearest server for unmatched regions

## Troubleshooting

### Common Issues

1. **DNS Resolution Fails**
   - Verify the private zone is associated with the correct VPC network
   - Check that VMs are in the same network as the DNS zone

2. **Wrong Server Response**
   - Confirm TTL has expired (wait 6+ seconds between tests)
   - Verify the routing policy data format is correct

3. **Connection Refused**
   - Ensure firewall rules allow HTTP traffic
   - Check that web servers started successfully
   - Verify the `http-server` tag is applied to server VMs

### Debugging Commands

```bash
# Check DNS record configuration
gcloud dns record-sets list --zone=example

# Verify VM status
gcloud compute instances list

# Check firewall rules
gcloud compute firewall-rules list
```

## Cleanup

To avoid ongoing charges, clean up all resources:

```bash
chmod +x scripts/cleanup.sh
./scripts/cleanup.sh
```

Or run individual cleanup commands:

```bash
# Delete VMs
gcloud compute instances delete -q us-client-vm --zone=us-east1-b
gcloud compute instances delete -q us-web-vm --zone=us-east1-b
gcloud compute instances delete -q europe-client-vm --zone=europe-west2-a
gcloud compute instances delete -q europe-web-vm --zone=europe-west2-a
gcloud compute instances delete -q asia-client-vm --zone=asia-south1-a

# Delete firewall rules
gcloud compute firewall-rules delete -q allow-http-traffic
gcloud compute firewall-rules delete -q fw-default-iapproxy

# Delete DNS records and zone
gcloud dns record-sets delete geo.example.com --type=A --zone=example
gcloud dns managed-zones delete example
```

## Use Cases

This geolocation routing pattern is ideal for:

- **Content Delivery**: Serving static content from the nearest edge location
- **Application Load Balancing**: Distributing users across regional application servers
- **Disaster Recovery**: Automatically routing traffic away from failed regions
- **Compliance**: Ensuring data stays within specific geographic boundaries
- **Performance Optimization**: Reducing latency by serving users from nearby servers

## Advanced Configurations

- **Multiple Regions**: Add more geographic regions to the routing policy
- **Weighted Routing**: Combine with weighted round-robin for traffic distribution
- **Health Checks**: Integrate with load balancer health checks for automatic failover
- **Custom Domains**: Use your own domain instead of example.com

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test the configuration
5. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Additional Resources

- [Cloud DNS Documentation](https://cloud.google.com/dns/docs)
- [DNS Routing Policies](https://cloud.google.com/dns/docs/routing-policies)
- [gcloud DNS Commands](https://cloud.google.com/sdk/gcloud/reference/dns)
- [Compute Engine Networking](https://cloud.google.com/compute/docs/networks-and-firewalls)
