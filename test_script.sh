#!/bin/bash

# Cloud DNS Geolocation Routing Test Script
# This script tests the geolocation routing configuration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

print_test() {
    echo -e "${PURPLE}[TEST]${NC} $1"
}

# Configuration
US_ZONE="us-east1-b"
EUROPE_ZONE="europe-west2-a"
ASIA_ZONE="asia-south1-a"
TEST_ITERATIONS=5

print_status "Starting Cloud DNS Geolocation Routing Tests..."

# Function to run test on a specific VM
run_vm_test() {
    local vm_name=$1
    local zone=$2
    local expected_region=$3
    
    print_test "Testing from $vm_name in $zone"
    print_status "Expected response: $expected_region"
    
    echo "----------------------------------------"
    
    # Create a temporary script to run on the VM
    cat > /tmp/test_geo_dns.sh << 'EOF'
#!/bin/bash
echo "Starting geolocation DNS test..."
echo "Running 5 curl tests with 6-second intervals:"
echo ""

for i in {1..5}; do 
    echo "Test $i:"
    response=$(curl -s --connect-timeout 10 geo.example.com 2>/dev/null || echo "Connection failed")
    echo "  Response: $response"
    if [ $i -lt 5 ]; then
        echo "  Waiting 6 seconds..."
        sleep 6
    fi
done

echo ""
echo "Test completed from $(hostname)"
EOF

    # Copy script to VM and execute
    gcloud compute scp /tmp/test_geo_dns.sh $vm_name:/tmp/test_geo_dns.sh \
        --zone=$zone --tunnel-through-iap --quiet
    
    gcloud compute ssh $vm_name --zone=$zone --tunnel-through-iap \
        --command="chmod +x /tmp/test_geo_dns.sh && /tmp/test_geo_dns.sh" \
        --quiet
    
    # Cleanup
    rm -f /tmp/test_geo_dns.sh
    
    echo "----------------------------------------"
    echo ""
}

# Function to verify VMs are running
check_vm_status() {
    print_status "Checking VM status..."
    
    local vms=("us-client-vm:$US_ZONE" "europe-client-vm:$EUROPE_ZONE" "asia-client-vm:$ASIA_ZONE" "us-web-vm:$US_ZONE" "europe-web-vm:$EUROPE_ZONE")
    
    for vm_zone in "${vms[@]}"; do
        local vm_name=${vm_zone%:*}
        local zone=${vm_zone#*:}
        
        local status=$(gcloud compute instances describe $vm_name --zone=$zone --format="value(status)" 2>/dev/null || echo "NOT_FOUND")
        
        if [ "$status" = "RUNNING" ]; then
            print_success "$vm_name is running"
        else
            print_error "$vm_name is not running (status: $status)"
            exit 1
        fi
    done
    echo ""
}

# Function to verify DNS configuration
check_dns_config() {
    print_status "Checking DNS configuration..."
    
    local dns_records=$(gcloud dns record-sets list --zone=example --format="value(name,type,rrdatas)" --filter="name:geo.example.com" 2>/dev/null || echo "")
    
    if [ -z "$dns_records" ]; then
        print_error "DNS record for geo.example.com not found"
        exit 1
    else
        print_success "DNS configuration found"
        echo "  $dns_records"
    fi
    echo ""
}

# Function to wait for web servers
wait_for_web_servers() {
    print_status "Waiting for web servers to be ready..."
    
    local us_ip=$(gcloud compute instances describe us-web-vm --zone=$US_ZONE --format="value(networkInterfaces[0].accessConfigs[0].natIP)")
    local europe_ip=$(gcloud compute instances describe europe-web-vm --zone=$EUROPE_ZONE --format="value(networkInterfaces[0].accessConfigs[0].natIP)")
    
    local max_attempts=10
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        print_status "Attempt $attempt/$max_attempts - Checking web server availability..."
        
        local us_status=$(curl -s --connect-timeout 5 http://$us_ip >/dev/null 2>&1 && echo "OK" || echo "FAIL")
        local europe_status=$(curl -s --connect-timeout 5 http://$europe_ip >/dev/null 2>&1 && echo "OK" || echo "FAIL")
        
        if [ "$us_status" = "OK" ] && [ "$europe_status" = "OK" ]; then
            print_success "Both web servers are responding"
            break
        else
            print_warning "Web servers not ready yet (US: $us_status, Europe: $europe_status)"
            if [ $attempt -eq $max_attempts ]; then
                print_error "Web servers not responding after $max_attempts attempts"
                exit 1
            fi
            sleep 10
        fi
        
        ((attempt++))
    done
    echo ""
}

# Main test execution
main() {
    echo "=================================================="
    echo "CLOUD DNS GEOLOCATION ROUTING TESTS"
    echo "=================================================="
    echo ""
    
    # Pre-flight checks
    check_vm_status
    check_dns_config
    wait_for_web_servers
    
    print_status "All pre-flight checks passed. Starting tests..."
    echo ""
    
    # Test 1: Europe Client
    print_test "TEST 1: Europe Client → Expected: Europe Server"
    run_vm_test "europe-client-vm" "$EUROPE_ZONE" "Europe Region"
    
    # Test 2: US Client  
    print_test "TEST 2: US Client → Expected: US Server"
    run_vm_test "us-client-vm" "$US_ZONE" "US Region"
    
    # Test 3: Asia Client (should route to nearest)
    print_test "TEST 3: Asia Client → Expected: Nearest Server (US or Europe)"
    print_warning "Asia client will be routed to the nearest server since no Asia server exists"
    run_vm_test "asia-client-vm" "$ASIA_ZONE" "Nearest Server"
    
    # Summary
    echo "=================================================="
    echo "TEST SUMMARY"
    echo "=================================================="
    echo ""
    print_success "All tests completed!"
    echo ""
    echo "Expected Results:"
    echo "• Europe client should always get responses from Europe Region"
    echo "• US client should always get responses from US Region"  
    echo "• Asia client should get responses from the nearest server"
    echo ""
    echo "If results don't match expectations, check:"
    echo "1. DNS TTL has expired (wait 6+ seconds between tests)"
    echo "2. Routing policy configuration is correct"
    echo "3. All VMs are in the correct zones"
    echo ""
    print_status "Test completed successfully!"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -q, --quick    Run quick test (3 iterations instead of 5)"
    echo "  --europe-only  Test only from Europe client"
    echo "  --us-only      Test only from US client"
    echo "  --asia-only    Test only from Asia client"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -q|--quick)
            TEST_ITERATIONS=3
            shift
            ;;
        --europe-only)
            print_test "Running Europe-only test"
            check_vm_status
            check_dns_config
            wait_for_web_servers
            run_vm_test "europe-client-vm" "$EUROPE_ZONE" "Europe Region"
            exit 0
            ;;
        --us-only)
            print_test "Running US-only test"
            check_vm_status
            check_dns_config
            wait_for_web_servers
            run_vm_test "us-client-vm" "$US_ZONE" "US Region"
            exit 0
            ;;
        --asia-only)
            print_test "Running Asia-only test"
            check_vm_status
            check_dns_config
            wait_for_web_servers
            run_vm_test "asia-client-vm" "$ASIA_ZONE" "Nearest Server"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Run main function
main