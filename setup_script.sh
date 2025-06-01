#!/bin/bash

# Cloud DNS Geolocation Routing Setup Script
# This script automates the complete setup of the geolocation routing lab

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration variables
US_ZONE="us-east1-b"
EUROPE_ZONE="europe-west2-a"
ASIA_ZONE="asia-south1-a"

print_status "Starting Cloud DNS Geolocation Routing Setup..."

# Step 1: Enable APIs
print_status "Enabling required APIs..."
gcloud services enable compute.googleapis.com
gcloud services enable dns.googleapis.com

print_status "Waiting for APIs to be fully enabled..."
sleep 10

print_success "APIs enabled successfully"

# Step 2: Configure Firewall Rules
print_status "Creating firewall rules..."

# SSH access via IAP
gcloud compute firewall-rules create fw-default-iapproxy \
--direction=INGRESS \
--priority=1000 \
--network=default \
--action=ALLOW \
--rules=tcp:22,icmp \
--source-ranges=35.235.240.0/20 \
--quiet

# HTTP traffic to web servers
gcloud compute firewall-rules create allow-http-traffic \
--direction=INGRESS \
--priority=1000 \
--network=default \
--action=ALLOW \
--rules=tcp:80 \
--source-ranges=0.0.0.0/0 \
--target-tags=http-server \
--quiet

print_success "Firewall rules created"

# Step 3: Launch Client VMs
print_status "Creating client VMs..."

# US Client
gcloud compute instances create us-client-vm \
--machine-type=e2-micro \
--zone=$US_ZONE \
--quiet &

# Europe Client
gcloud compute instances create europe-client-vm \
--machine-type=e2-micro \
--zone=$EUROPE_ZONE \
--quiet &

# Asia Client
gcloud compute instances create asia-client-vm \
--machine-type=e2-micro \
--zone=$ASIA_ZONE \
--quiet &

wait  # Wait for all client VMs to be created
print_success "Client VMs created"

# Step 4: Launch Server VMs with Web Servers
print_status "Creating web server VMs..."

# US Web Server
gcloud compute instances create us-web-vm \
--machine-type=e2-micro \
--zone=$US_ZONE \
--network=default \
--subnet=default \
--tags=http-server \
--metadata=startup-script='#! /bin/bash
 apt-get update
 apt-get install apache2 -y
 echo "Page served from: US Region ('$US_ZONE')" | \
 tee /var/www/html/index.html
 systemctl restart apache2' \
--quiet &

# Europe Web Server
gcloud compute instances create europe-web-vm \
--machine-type=e2-micro \
--zone=$EUROPE_ZONE \
--network=default \
--subnet=default \
--tags=http-server \
--metadata=startup-script='#! /bin/bash
 apt-get update
 apt-get install apache2 -y
 echo "Page served from: Europe Region ('$EUROPE_ZONE')" | \
 tee /var/www/html/index.html
 systemctl restart apache2' \
--quiet &

wait  # Wait for all server VMs to be created
print_success "Web server VMs created"

# Step 5: Wait for VMs to be ready and get IP addresses
print_status "Waiting for VMs to be ready..."
sleep 30

print_status "Getting internal IP addresses..."
US_WEB_IP=$(gcloud compute instances describe us-web-vm \
--zone=$US_ZONE \
--format="value(networkInterfaces.networkIP)")

EUROPE_WEB_IP=$(gcloud compute instances describe europe-web-vm \
--zone=$EUROPE_ZONE \
--format="value(networkInterfaces.networkIP)")

print_status "US Web Server IP: $US_WEB_IP"
print_status "Europe Web Server IP: $EUROPE_WEB_IP"

# Step 6: Create Private DNS Zone
print_status "Creating private DNS zone..."
gcloud dns managed-zones create example \
--description="Geolocation routing test zone" \
--dns-name=example.com \
--networks=default \
--visibility=private \
--quiet

print_success "Private DNS zone created"

# Step 7: Create Geolocation Routing Policy
print_status "Creating geolocation routing policy..."
gcloud dns record-sets create geo.example.com \
--ttl=5 \
--type=A \
--zone=example \
--routing-policy-type=GEO \
--routing-policy-data="us-east1=$US_WEB_IP;europe-west2=$EUROPE_WEB_IP" \
--quiet

print_success "Geolocation routing policy created"

# Step 8: Verify setup
print_status "Verifying DNS configuration..."
gcloud dns record-sets list --zone=example

print_status "Verifying VM status..."
gcloud compute instances list --filter="name~(client|web)" --format="table(name,zone,status,networkInterfaces[0].networkIP:label=INTERNAL_IP)"

# Step 9: Wait for web servers to be ready
print_status "Waiting for web servers to be ready..."
sleep 60

print_success "Setup completed successfully!"
print_status "You can now run the test script: ./scripts/test.sh"

# Display next steps
echo ""
echo "=================================================="
echo "SETUP COMPLETE - NEXT STEPS"
echo "=================================================="
echo ""
echo "1. Test the configuration:"
echo "   ./scripts/test.sh"
echo ""
echo "2. Manual testing commands:"
echo "   # Test from Europe:"
echo "   gcloud compute ssh europe-client-vm --zone=$EUROPE_ZONE --tunnel-through-iap"
echo ""
echo "   # Test from US:"
echo "   gcloud compute ssh us-client-vm --zone=$US_ZONE --tunnel-through-iap"
echo ""
echo "   # Test from Asia:"
echo "   gcloud compute ssh asia-client-vm --zone=$ASIA_ZONE --tunnel-through-iap"
echo ""
echo "   # Inside each VM run:"
echo "   for i in {1..10}; do echo \$i; curl geo.example.com; sleep 6; done"
echo ""
echo "3. Clean up when done:"
echo "   ./scripts/cleanup.sh"
echo ""
print_success "All resources are ready for testing!"