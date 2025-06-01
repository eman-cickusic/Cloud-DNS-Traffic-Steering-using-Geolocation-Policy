# Architecture Documentation

## Overview

This document describes the architecture and components of the Cloud DNS Geolocation Routing implementation.

## System Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Google Cloud Project                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │   us-east1  │  │ europe-west2│  │ asia-south1 │             │
│  │             │  │             │  │             │             │
│  │ ┌─────────┐ │  │ ┌─────────┐ │  │ ┌─────────┐ │             │
│  │ │ Client  │ │  │ │ Client  │ │  │ │ Client  │ │             │
│  │ │   VM    │ │  │ │   VM    │ │  │ │   VM    │ │             │
│  │ └─────────┘ │  │ └─────────┘ │  │ └─────────┘ │             │
│  │ ┌─────────┐ │  │ ┌─────────┐ │  │             │             │
│  │ │   Web   │ │  │ │   Web   │ │  │      No     │             │
│  │ │ Server  │ │  │ │ Server  │ │  │    Server   │             │
│  │ │   VM    │ │  │ │   VM    │ │  │             │             │
│  │ └─────────┘ │  │ └─────────┘ │  │             │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                    Cloud DNS                                │ │
│  │              Private Zone: example.com                     │ │
│  │                                                             │ │
│  │    ┌─────────────────────────────────────────────────────┐  │ │
│  │    │              Geolocation Policy                     │  │ │
│  │    │                                                     │  │ │
│  │    │  geo.example.com (A Record, TTL=5s)               │  │ │
│  │    │                                                     │  │ │
│  │    │  us-east1    → 10.142.0.3 (US Web Server)        │  │ │
│  │    │  europe-west2 → 10.154.0.3 (Europe Web Server)   │  │ │
│  │    │  *           → Nearest Match                       │  │ │
│  │    └─────────────────────────────────────────────────────┘  │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                    VPC Network (default)                   │ │
│  │                                                             │ │
│  │  Firewall Rules:                                           │ │
│  │  • fw-default-iapproxy (SSH via IAP)                      │ │
│  │  • allow-http-traffic (HTTP to web servers)               │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. Virtual Machines

#### Client VMs
- **Purpose**: Test DNS resolution from different geographic locations
- **Machine Type**: e2-micro (cost-effective for testing)
- **Regions**: 
  - `us-east1-b` (United States)
  - `europe-west2-a` (Europe)
  - `asia-south1-a` (Asia)
- **Network**: Default VPC
- **Access**: SSH via Identity-Aware Proxy (IAP)

#### Web Server VMs
- **Purpose**: Serve HTTP content to demonstrate geographic routing
- **Machine Type**: e2-micro
- **Regions**: 
  - `us-east1-b` (United States)
  - `europe-west2-a` (Europe)
- **Network**: Default VPC
- **Tags**: `http-server` (for firewall targeting)
- **Software**: Apache HTTP Server
- **Content**: Simple HTML page identifying the server region

### 2. Cloud DNS

#### Private Zone
- **Name**: `example`
- **Domain**: `example.com`
- **Visibility**: Private (internal to VPC)
- **Network**: Default VPC
- **Purpose**: Internal DNS resolution for geolocation testing

#### DNS Record
- **Name**: `geo.example.com`
- **Type**: A Record
- **TTL**: 5 seconds (fast propagation for testing)
- **Routing Policy**: Geolocation (GEO)
- **Policy Data**: 
  - `us-east1` → Internal IP of US web server
  - `europe-west2` → Internal IP of Europe web server

### 3. Network Security

#### Firewall Rules

##### fw-default-iapproxy
- **Direction**: Ingress
- **Priority**: 1000
- **Network**: default
- **Action**: Allow
- **Protocols**: TCP:22, ICMP
- **Source Ranges**: `35.235.240.0/20` (IAP IP range)
- **Purpose**: Enable SSH access via Identity-Aware Proxy

##### allow-http-traffic
- **Direction**: Ingress
- **Priority**: 1000
- **Network**: default
- **Action**: Allow
- **Protocols**: TCP:80
- **Source Ranges**: `0.0.0.0/0` (all sources)
- **Target Tags**: `http-server`
- **Purpose**: Allow HTTP traffic to web servers

### 4. Geographic Routing Logic

#### Routing Behavior

1. **US Clients** (`us-east1` region)
   - DNS Query: `geo.example.com`
   - Policy Match: `us-east1`
   - Response: US web server IP (`10.142.0.3`)
   - Result: "Page served from: US Region"

2. **Europe Clients** (`europe-west2` region)
   - DNS Query: `geo.example.com`
   - Policy Match: `europe-west2`
   - Response: Europe web server IP (`10.154.0.3`)
   - Result: "Page served from: Europe Region"

3. **Asia Clients** (`asia-south1` region)
   - DNS Query: `geo.example.com`
   - Policy Match: No exact match
   - Fallback: Nearest server (varies by network topology)
   - Response: Either US or Europe server IP
   - Result: Geographic proximity determines routing

#### Nearest Match Algorithm

When no exact geographic match exists, Cloud DNS uses:
- **Network topology**: Physical network distance
- **Latency measurements**: Historical performance data
- **Load balancing**: Distribution across available servers

## Data Flow

### 1. Setup Phase

```
Setup Script → gcloud CLI → Google Cloud APIs
     ↓
   VMs Created → Startup Scripts → Web Servers Running
     ↓
 DNS Zone Created → A Record → Geolocation Policy
     ↓
Environment Ready
```

### 2. DNS Resolution Flow

```
Client VM → DNS Query (geo.example.com)
     ↓
Cloud DNS → Policy Evaluation
     ↓
Geographic Match → IP Address Selection
     ↓
Response → Client VM → HTTP Request
     ↓
Web Server → HTML Response
```

### 3. Testing Flow

```
Test Script → SSH to Client VM
     ↓
Execute curl Commands → DNS Resolution
     ↓
HTTP Requests → Web Server Responses
     ↓
Analyze Results → Verify Geographic Routing
```

## Scalability Considerations

### Horizontal Scaling

1. **Additional Regions**
   - Add more geographic regions to routing policy
   - Deploy web servers in new regions
   - Update DNS policy with new region mappings

2. **Load Distribution**
   - Implement weighted routing within regions
   - Use multiple servers per region
   - Configure health checks for failover

### Performance Optimization

1. **TTL Management**
   - Low TTL (5s) for testing and development
   - Higher TTL (300s+) for production stability
   - Balance between update speed and DNS load

2. **Caching Strategy**
   - Client-side DNS caching
   - Resolver caching policies
   - CDN integration for static content

## Security Architecture

### Network Security

1. **VPC Isolation**
   - Private VPC network isolation
   - Internal IP communication
   - No direct external access (except via IAP)

2. **Firewall Controls**
   - Least privilege access
   - Tag-based rule targeting
   - Source IP restrictions

### Access Control

1. **Identity-Aware Proxy**
   - Secure SSH access without VPN
   - Google identity integration
   - Audit logging of access

2. **Service Account Security**
   - Minimal required permissions
   - Project-level isolation
   - Regular key rotation

## Monitoring and Observability

### DNS Metrics

- Query volume and patterns
- Resolution latency
- Cache hit/miss ratios
- Geographic distribution

### Infrastructure Metrics

- VM health and performance
- Network connectivity
- HTTP response times
- Error rates by region

### Logging

- DNS query logs
- VM access logs
- Application logs
- Security audit trails

## Cost Optimization

### Resource Efficiency

1. **VM Sizing**
   - e2-micro instances for testing
   - Right-sizing for production workloads
   - Preemptible instances for non-critical testing

2. **Network Costs**
   - Internal IP communication
   - Regional traffic optimization
   - Egress cost management

### Operational Efficiency

1. **Automation**
   - Infrastructure as Code
   - Automated testing
   - Resource lifecycle management

2. **Resource Cleanup**
   - Automated cleanup scripts
   - Scheduled resource deletion
   - Cost monitoring and alerts

## Future Enhancements

### Advanced Routing

1. **Health-Based Routing**
   - Integrate with load balancer health checks
   - Automatic failover to healthy regions
   - Real-time health monitoring

2. **Latency-Based Routing**
   - Dynamic routing based on measured latency
   - Performance-optimized server selection
   - Quality of experience improvements

### Integration Opportunities

1. **CDN Integration**
   - Cloud CDN for static content
   - Edge location optimization
   - Global content distribution

2. **Service Mesh**
   - Istio integration for microservices
   - Advanced traffic management
   - Service-to-service security

This architecture provides a foundation for understanding DNS-based geographic traffic steering and can be extended for various production use cases.