# Troubleshooting Guide

This guide helps you resolve common issues when working with Cloud DNS Geolocation Routing.

## Common Issues and Solutions

### 1. DNS Resolution Problems

#### Issue: `curl geo.example.com` returns "Could not resolve host"

**Possible Causes:**
- Private DNS zone not associated with the correct VPC network
- VM not in the same network as the DNS zone
- DNS propagation hasn't completed

**Solutions:**
```bash
# Check DNS zone configuration
gcloud dns managed-zones describe example

# Verify the zone is associated with the default network
gcloud dns managed-zones describe example --format="value(privateVisibilityConfig.networks)"

# Check VM network configuration
gcloud compute instances describe us-client-vm --zone=us-east1-b --format="value(networkInterfaces.network)"
```

#### Issue: DNS resolves to wrong server

**Possible Causes:**
- TTL hasn't expired (DNS cached)
- Routing policy configuration incorrect
- Client location not matching policy

**Solutions:**
```bash
# Wait for TTL to expire (6+ seconds)
sleep 10

# Check current DNS record configuration
gcloud dns record-sets list --zone=example --filter="name:geo.example.com"

# Verify routing policy data format
gcloud dns record-sets describe geo.example.com --zone=example --type=A
```

### 2. VM Connection Issues

#### Issue: Cannot SSH into VMs

**Possible Causes:**
- IAP firewall rule missing or incorrect
- VM not running
- Incorrect zone specified

**Solutions:**
```bash
# Check VM status
gcloud compute instances list --filter="name~(client|web)"

# Verify IAP firewall rule exists
gcloud compute firewall-rules describe fw-default-iapproxy

# Try with explicit project and zone
gcloud compute ssh us-client-vm --zone=us-east1-b --tunnel-through-iap --project=YOUR_PROJECT_ID
```

#### Issue: SSH connection hangs or times out

**Solutions:**
```bash
# Use --ssh-flag for debugging
gcloud compute ssh us-client-vm --zone=us-east1-b --tunnel-through-iap --ssh-flag="-v"

# Check if IAP is enabled for your project
gcloud services list --enabled --filter="name:iap.googleapis.com"

# Enable IAP if needed
gcloud services enable iap.googleapis.com
```

### 3. Web Server Issues

#### Issue: Web servers not responding

**Possible Causes:**
- Apache not started
- Firewall rules blocking HTTP traffic
- Startup script failed

**Solutions:**
```bash
# Check web server external IPs
gcloud compute instances describe us-web-vm --zone=us-east1-b --format="value(networkInterfaces[0].accessConfigs[0].natIP)"

# Test direct access to web server
curl http://EXTERNAL_IP

# Check startup script logs
gcloud compute ssh us-web-vm --zone=us-east1-b --tunnel-through-iap
# Inside VM:
sudo journalctl -u google-startup-scripts.service
```

#### Issue: Web server returns default Apache page

**Solutions:**
```bash
# SSH into web server and check the index.html
gcloud compute ssh us-web-vm --zone=us-east1-b --tunnel-through-iap

# Inside VM, check the content:
cat /var/www/html/index.html

# Restart Apache if needed:
sudo systemctl restart apache2
sudo systemctl status apache2
```

### 4. Setup Script Issues

#### Issue: Setup script fails with permission errors

**Solutions:**
```bash
# Ensure you're authenticated
gcloud auth list
gcloud auth login

# Set correct project
gcloud config set project YOUR_PROJECT_ID

# Check required permissions
gcloud projects get-iam-policy YOUR_PROJECT_ID --flatten="bindings[].members" --filter="bindings.members:YOUR_EMAIL"
```

#### Issue: APIs not enabled errors

**Solutions:**
```bash
# Enable APIs manually
gcloud services enable compute.googleapis.com
gcloud services enable dns.googleapis.com

# Wait for APIs to be fully enabled
sleep 30

# Verify APIs are enabled
gcloud services list --enabled --filter="name~(compute|dns)"
```

### 5. Testing Issues

#### Issue: Inconsistent test results

**Possible Causes:**
- DNS caching
- Network latency
- TTL not expired

**Solutions:**
```bash
# Increase sleep time between tests
for i in {1..5}; do echo $i; curl geo.example.com; sleep 10; done

# Clear local DNS cache (if testing from local machine)
# On macOS:
sudo dscacheutil -flushcache

# On Linux:
sudo systemd-resolve --flush-caches
```

#### Issue: Asia client gets unexpected responses

**Expected Behavior:**
The Asia client should be routed to the nearest server since there's no server in Asia.

**Debugging:**
```bash
# Check network topology to understand routing
traceroute geo.example.com

# Test from different Asia regions if available
# The result may vary based on Google's network topology
```

## Debugging Commands

### Check Overall Status
```bash
# List all VMs
gcloud compute instances list --filter="name~(client|web)" --format="table(name,zone,status,networkInterfaces[0].networkIP:label=INTERNAL_IP)"

# Check DNS configuration
gcloud dns record-sets list --zone=example

# Verify firewall rules
gcloud compute firewall-rules list --filter="name~(fw-default-iapproxy|allow-http-traffic)"
```

### Network Diagnostics
```bash
# From inside a VM, test DNS resolution
nslookup geo.example.com
dig geo.example.com

# Test network connectivity
ping -c 4 geo.example.com
traceroute geo.example.com
```

### Logs and Monitoring
```bash
# Check Cloud DNS query logs (if enabled)
gcloud logging read 'resource.type="dns_query"' --limit=10

# Check VM serial console output
gcloud compute instances get-serial-port-output us-web-vm --zone=us-east1-b
```

## Quota and Limits

### Common Quota Issues
- **Compute instances**: Default limit of 8 instances per region
- **DNS zones**: Default limit of 100 zones per project
- **Firewall rules**: Default limit of 100 rules per network

### Check Quotas
```bash
# Check compute quotas
gcloud compute project-info describe --format="table(quotas.metric,quotas.limit,quotas.usage)"

# Check if you're hitting limits
gcloud compute operations list --filter="operationType:insert AND status:ERROR"
```

## Performance Optimization

### Reduce DNS TTL for Testing
```bash
# Set TTL to 1 second for faster testing (not recommended for production)
gcloud dns record-sets update geo.example.com --zone=example --ttl=1 --type=A
```

### Parallel Operations
```bash
# Run operations in parallel for faster setup/cleanup
gcloud compute instances create vm1 --async &
gcloud compute instances create vm2 --async &
wait
```

## Getting Help

### Useful Resources
- [Cloud DNS Documentation](https://cloud.google.com/dns/docs)
- [Compute Engine Troubleshooting](https://cloud.google.com/compute/docs/troubleshooting)
- [gcloud CLI Reference](https://cloud.google.com/sdk/gcloud/reference)

### Support Commands
```bash
# Get detailed error messages
gcloud compute instances create test-vm --zone=us-east1-b --verbosity=debug

# Check gcloud configuration
gcloud info

# Validate configuration
gcloud compute instances list --format="export" > instances.yaml
```

### Contact Support
If issues persist:
1. Check [Google Cloud Status](https://status.cloud.google.com/)
2. Post on [Stack Overflow](https://stackoverflow.com/questions/tagged/google-cloud-platform) with tag `google-cloud-platform`
3. Contact Google Cloud Support if you have a support plan

## Prevention Tips

1. **Always set TTL appropriately**: Use low TTL (5s) for testing, higher (300s+) for production
2. **Monitor quotas**: Check quotas before running large deployments
3. **Use consistent naming**: Follow naming conventions for easier management
4. **Clean up resources**: Always run cleanup scripts after testing
5. **Version control**: Keep your gcloud commands in scripts for reproducibility