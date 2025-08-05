#!/bin/bash
# Express Route Bandwidth Testing Script
# Save as: /opt/expressroute-testing/scripts/express_route_bandwidth_testing.sh

TESTING_DIR="/opt/expressroute-testing"
RESULTS_DIR="$TESTING_DIR/results"
LOGS_DIR="$TESTING_DIR/logs"
CONFIG_DIR="$TESTING_DIR/configs"

# Create directories if they don't exist
mkdir -p "$RESULTS_DIR" "$LOGS_DIR" "$CONFIG_DIR"

# Create timestamp for this test session
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SESSION_DIR="$RESULTS_DIR/session_$TIMESTAMP"
mkdir -p "$SESSION_DIR"

echo "=== Express Route Bandwidth Testing Suite ==="
echo "Session: $TIMESTAMP"
echo "Results will be saved to: $SESSION_DIR"

# Function to log with timestamp
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGS_DIR/bandwidth_test_$TIMESTAMP.log"
}

# Function to test TCP bandwidth using iperf3
test_tcp_bandwidth() {
    local target_ip=$1
    local target_name=$2
    local duration=${3:-30}
    local parallel=${4:-1}
    
    log_message "Testing TCP bandwidth to $target_name ($target_ip)"
    
    # Test download bandwidth (we are client)
    timeout $((duration + 10)) iperf3 -c $target_ip -t $duration -P $parallel -J > "$SESSION_DIR/tcp_${target_name}_${target_ip}_download.json" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        # Extract key metrics
        local bandwidth=$(jq -r '.end.sum_received.bits_per_second // 0' "$SESSION_DIR/tcp_${target_name}_${target_ip}_download.json" 2>/dev/null)
        local mbps=$(echo "scale=2; $bandwidth / 1000000" | bc 2>/dev/null || echo "0")
        log_message "TCP Download: $target_name - ${mbps} Mbps"
        echo "$TIMESTAMP,$target_name,$target_ip,TCP,Download,$bandwidth,$mbps" >> "$SESSION_DIR/bandwidth_summary.csv"
    else
        log_message "TCP test failed for $target_name ($target_ip)"
        echo "$TIMESTAMP,$target_name,$target_ip,TCP,Download,0,0" >> "$SESSION_DIR/bandwidth_summary.csv"
    fi
}

# Function to test UDP bandwidth using iperf3
test_udp_bandwidth() {
    local target_ip=$1
    local target_name=$2
    local bandwidth_limit=${3:-100M}
    local duration=${4:-30}
    
    log_message "Testing UDP bandwidth to $target_name ($target_ip) with limit $bandwidth_limit"
    
    timeout $((duration + 10)) iperf3 -c $target_ip -u -b $bandwidth_limit -t $duration -J > "$SESSION_DIR/udp_${target_name}_${target_ip}.json" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        local bandwidth=$(jq -r '.end.sum.bits_per_second // 0' "$SESSION_DIR/udp_${target_name}_${target_ip}.json" 2>/dev/null)
        local loss=$(jq -r '.end.sum.lost_percent // 100' "$SESSION_DIR/udp_${target_name}_${target_ip}.json" 2>/dev/null)
        local mbps=$(echo "scale=2; $bandwidth / 1000000" | bc 2>/dev/null || echo "0")
        log_message "UDP: $target_name - ${mbps} Mbps, Loss: ${loss}%"
        echo "$TIMESTAMP,$target_name,$target_ip,UDP,Upload,$bandwidth,$mbps,$loss" >> "$SESSION_DIR/bandwidth_summary.csv"
    else
        log_message "UDP test failed for $target_name ($target_ip)"
        echo "$TIMESTAMP,$target_name,$target_ip,UDP,Upload,0,0,100" >> "$SESSION_DIR/bandwidth_summary.csv"
    fi
}

# Function to test latency and packet loss
test_latency() {
    local target_ip=$1
    local target_name=$2
    local count=${3:-100}
    
    log_message "Testing latency to $target_name ($target_ip)"
    
    # Ping test
    ping -c $count -i 0.1 $target_ip > "$SESSION_DIR/ping_${target_name}_${target_ip}.txt" 2>&1
    
    if [ $? -eq 0 ]; then
        # Extract latency statistics
        local avg_latency=$(grep "rtt min/avg/max/mdev" "$SESSION_DIR/ping_${target_name}_${target_ip}.txt" | cut -d'/' -f5 2>/dev/null || echo "999")
        local packet_loss=$(grep "packet loss" "$SESSION_DIR/ping_${target_name}_${target_ip}.txt" | grep -o '[0-9]*%' | head -1 || echo "100%")
        log_message "Latency: $target_name - Avg: ${avg_latency}ms, Loss: $packet_loss"
        echo "$TIMESTAMP,$target_name,$target_ip,ICMP,Latency,$avg_latency,$packet_loss" >> "$SESSION_DIR/latency_summary.csv"
    else
        log_message "Ping test failed for $target_name ($target_ip)"
        echo "$TIMESTAMP,$target_name,$target_ip,ICMP,Latency,999,100%" >> "$SESSION_DIR/latency_summary.csv"
    fi
}

# Function to trace route and analyze path
trace_route_analysis() {
    local target_ip=$1
    local target_name=$2
    
    log_message "Tracing route to $target_name ($target_ip)"
    
    # Multiple trace methods
    timeout 60 traceroute -n $target_ip > "$SESSION_DIR/traceroute_${target_name}_${target_ip}.txt" 2>&1
    timeout 60 mtr -r -c 10 $target_ip > "$SESSION_DIR/mtr_${target_name}_${target_ip}.txt" 2>&1
    
    # Extract hop count and identify Express Route path
    local hop_count=$(grep -c "^ [0-9]" "$SESSION_DIR/traceroute_${target_name}_${target_ip}.txt" 2>/dev/null || echo "0")
    log_message "Route analysis: $target_name - $hop_count hops"
    echo "$TIMESTAMP,$target_name,$target_ip,Route,Analysis,$hop_count" >> "$SESSION_DIR/route_summary.csv"
}

# Function to test using speedtest for internet connectivity
test_internet_speed() {
    log_message "Testing internet connectivity speed"
    
    if command -v speedtest-cli &> /dev/null; then
        speedtest-cli --json > "$SESSION_DIR/internet_speedtest.json" 2>/dev/null
        if [ $? -eq 0 ]; then
            local download_speed=$(jq -r '.download // 0' "$SESSION_DIR/internet_speedtest.json" 2>/dev/null)
            local upload_speed=$(jq -r '.upload // 0' "$SESSION_DIR/internet_speedtest.json" 2>/dev/null)
            local ping_ms=$(jq -r '.ping // 999' "$SESSION_DIR/internet_speedtest.json" 2>/dev/null)
            log_message "Internet Speed - Download: $download_speed bps, Upload: $upload_speed bps, Ping: ${ping_ms}ms"
        fi
    else
        log_message "speedtest-cli not available, skipping internet speed test"
    fi
}

# Function to create default config files if they don't exist
create_default_configs() {
    # Create CIDR ranges configuration if it doesn't exist
    if [ ! -f "$CONFIG_DIR/cidr-ranges.conf" ]; then
        cat > "$CONFIG_DIR/cidr-ranges.conf" << 'EOF'
# SPOKE and HUB CIDR Ranges for Testing
# Format: NAME|PRIVATE_CIDR|PUBLIC_CIDR|TEST_IP|DESCRIPTION

HUB|10.28.128.0/25|137.75.100.0/25|10.28.128.11|Hub Virtual Appliances
OAR-ITMO|10.28.132.0/23|137.75.101.32/27|10.28.132.10|OAR ITMO Lab
OAR-ARL|10.28.134.0/23|137.75.101.64/28|10.28.134.10|OAR ARL Lab  
OAR-GSL|10.28.136.0/23|137.75.101.80/28|10.28.136.10|OAR GSL Lab
OAR-PMEL|10.28.138.0/23|137.75.101.96/28|10.28.138.10|OAR PMEL Lab
OAR-NSSL|10.28.140.0/23|137.75.101.112/28|10.28.140.10|OAR NSSL Lab
OAR-PSL|10.28.142.0/23|137.75.101.128/28|10.28.142.10|OAR PSL Lab
NWS-AWC-PROD|10.28.160.0/22|137.75.102.0/27|10.28.160.10|NWS AWC Production
NWS-AWC-DEV|10.28.164.0/22|137.75.102.32/27|10.28.164.10|NWS AWC Development
NMFS-NEFSC|10.28.156.0/23|137.75.101.16/28|10.28.156.10|NMFS NEFSC
OCIO-CORPSRV|10.28.170.0/23|137.75.101.224/28|10.28.170.10|OCIO Corporate Services
OAR-EPIC|10.28.32.0/23|137.75.102.96/27|10.28.32.10|OAR EPIC
NWS-AWIPS|10.28.174.0/23|137.75.102.80/28|10.28.174.10|NWS AWIPS
OCIO-NBFS|10.28.176.0/23|137.75.102.128/28|10.28.176.10|OCIO NBFS
NWS-WOFS|10.28.178.0/23|137.75.102.160/27|10.28.178.10|NWS WOFS
OCIO-EDC|10.28.180.0/25|137.75.102.144/28|10.28.180.10|OCIO EDC
OCIO-ESAE|10.28.180.128/25|137.75.102.192/28|10.28.180.138|OCIO ESAE
EOF
        log_message "Created default CIDR ranges configuration"
    fi

    # Create virtual appliances configuration if it doesn't exist
    if [ ! -f "$CONFIG_DIR/virtual-appliances.conf" ]; then
        cat > "$CONFIG_DIR/virtual-appliances.conf" << 'EOF'
# Virtual Appliance Endpoints
# Format: NAME|IP|PORT|DESCRIPTION

EAST-FGT-A|137.75.100.6|443|Primary FortiGate Appliance
EAST-FGT-B|137.75.100.7|443|Secondary FortiGate Appliance  
HUB-NEXTHOP-PRV|10.28.128.11|22|Private Network Next Hop
HUB-NEXTHOP-PUB|137.75.100.11|22|Public Network Next Hop
EOF
        log_message "Created default virtual appliances configuration"
    fi
}

# Function to generate summary report
generate_test_report() {
    local report_file="$SESSION_DIR/test_report_$TIMESTAMP.txt"
    
    cat > "$report_file" << EOF
===============================================
Express Route Performance Testing Report
===============================================
Test Session: $TIMESTAMP
Test Duration: $(date)
Source: SPOKE1-Public-Monitor-VM
Target: Multiple CIDR spaces and virtual appliances

SUMMARY STATISTICS:
EOF
    
    # Add latency summary
    if [ -f "$SESSION_DIR/latency_summary.csv" ]; then
        echo "" >> "$report_file"
        echo "LATENCY RESULTS:" >> "$report_file"
        echo "----------------" >> "$report_file"
        awk -F',' 'NR>1 {print $2 ": " $5 "ms (Loss: " $6 ")"}' "$SESSION_DIR/latency_summary.csv" >> "$report_file"
    fi
    
    # Add bandwidth summary
    if [ -f "$SESSION_DIR/bandwidth_summary.csv" ]; then
        echo "" >> "$report_file"
        echo "BANDWIDTH RESULTS:" >> "$report_file"
        echo "------------------" >> "$report_file"
        awk -F',' 'NR>1 {print $2 " (" $4 "): " $7 " Mbps"}' "$SESSION_DIR/bandwidth_summary.csv" >> "$report_file"
    fi
    
    # Add route analysis
    if [ -f "$SESSION_DIR/route_summary.csv" ]; then
        echo "" >> "$report_file"
        echo "ROUTE ANALYSIS:" >> "$report_file"
        echo "---------------" >> "$report_file"
        awk -F',' 'NR>1 {print $2 ": " $6 " hops"}' "$SESSION_DIR/route_summary.csv" >> "$report_file"
    fi
    
    echo "" >> "$report_file"
    echo "Detailed results available in: $SESSION_DIR" >> "$report_file"
    echo "Log file: $LOGS_DIR/bandwidth_test_$TIMESTAMP.log" >> "$report_file"
    
    log_message "Test report generated: $report_file"
    cat "$report_file"
}

# Main testing function
run_comprehensive_test() {
    local test_type=${1:-"basic"}
    
    log_message "Starting comprehensive Express Route testing - Type: $test_type"
    
    # Create default configs if needed
    create_default_configs
    
    # Create CSV headers
    echo "Timestamp,Target_Name,Target_IP,Protocol,Direction,Bandwidth_bps,Bandwidth_Mbps,Loss_Percent" > "$SESSION_DIR/bandwidth_summary.csv"
    echo "Timestamp,Target_Name,Target_IP,Protocol,Metric,Value,Additional" > "$SESSION_DIR/latency_summary.csv"
    echo "Timestamp,Target_Name,Target_IP,Protocol,Metric,Hops" > "$SESSION_DIR/route_summary.csv"
    
    # Test virtual appliances first
    log_message "Testing Virtual Appliances..."
    if [ -f "$CONFIG_DIR/virtual-appliances.conf" ]; then
        while IFS='|' read -r name ip port description; do
            if [[ ! $name =~ ^#.*$ ]] && [ ! -z "$name" ]; then
                log_message "Testing appliance: $name ($ip)"
                test_latency "$ip" "$name" 20
                trace_route_analysis "$ip" "$name"
                
                if [ "$test_type" = "full" ]; then
                    # Only test bandwidth if we can reach the target
                    if ping -c 1 -W 5 "$ip" >/dev/null 2>&1; then
                        test_tcp_bandwidth "$ip" "$name" 30 1
                        test_udp_bandwidth "$ip" "$name" "50M" 30
                    fi
                fi
            fi
        done < "$CONFIG_DIR/virtual-appliances.conf"
    fi
    
    # Test CIDR ranges
    log_message "Testing CIDR Ranges..."
    if [ -f "$CONFIG_DIR/cidr-ranges.conf" ]; then
        while IFS='|' read -r name private_cidr public_cidr test_ip description; do
            if [[ ! $name =~ ^#.*$ ]] && [ ! -z "$name" ] && [ "$name" != "SPOKE-1" ]; then
                log_message "Testing CIDR: $name ($test_ip)"
                test_latency "$test_ip" "$name" 10
                
                if [ "$test_type" = "full" ]; then
                    trace_route_analysis "$test_ip" "$name"
                    # Only test bandwidth if we can reach the target
                    if ping -c 1 -W 5 "$test_ip" >/dev/null 2>&1; then
                        test_tcp_bandwidth "$test_ip" "$name" 20 1
                    fi
                fi
            fi
        done < "$CONFIG_DIR/cidr-ranges.conf"
    fi
    
    # Test external connectivity (internet)
    log_message "Testing External Connectivity..."
    test_latency "8.8.8.8" "Google_DNS" 20
    test_latency "1.1.1.1" "Cloudflare_DNS" 20
    
    if [ "$test_type" = "full" ]; then
        # Additional internet tests
        test_internet_speed
    fi
    
    # Generate summary report
    generate_test_report
    
    log_message "Comprehensive testing completed. Results in: $SESSION_DIR"
}

# Command line interface
case "$1" in
    "basic")
        run_comprehensive_test "basic"
        ;;
    "full")
        run_comprehensive_test "full"
        ;;
    "latency")
        log_message "Running latency-only tests"
        create_default_configs
        echo "Timestamp,Target_Name,Target_IP,Protocol,Metric,Value,Additional" > "$SESSION_DIR/latency_summary.csv"
        
        # Test virtual appliances
        if [ -f "$CONFIG_DIR/virtual-appliances.conf" ]; then
            while IFS='|' read -r name ip port description; do
                if [[ ! $name =~ ^#.*$ ]] && [ ! -z "$name" ]; then
                    test_latency "$ip" "$name" 50
                fi
            done < "$CONFIG_DIR/virtual-appliances.conf"
        fi
        
        # Test external
        test_latency "8.8.8.8" "Google_DNS" 50
        test_latency "1.1.1.1" "Cloudflare_DNS" 50
        ;;
    "bandwidth")
        log_message "Running bandwidth-only tests"
        create_default_configs
        echo "Timestamp,Target_Name,Target_IP,Protocol,Direction,Bandwidth_bps,Bandwidth_Mbps,Loss_Percent" > "$SESSION_DIR/bandwidth_summary.csv"
        
        # Test virtual appliances
        if [ -f "$CONFIG_DIR/virtual-appliances.conf" ]; then
            while IFS='|' read -r name ip port description; do
                if [[ ! $name =~ ^#.*$ ]] && [ ! -z "$name" ]; then
                    if ping -c 1 -W 5 "$ip" >/dev/null 2>&1; then
                        test_tcp_bandwidth "$ip" "$name" 60 1
                    fi
                fi
            done < "$CONFIG_DIR/virtual-appliances.conf"
        fi
        ;;
    *)
        echo "Usage: $0 {basic|full|latency|bandwidth}"
        echo ""
        echo "  basic    - Quick connectivity and latency tests"
        echo "  full     - Comprehensive bandwidth and performance tests"
        echo "  latency  - Latency and connectivity tests only"
        echo "  bandwidth- Bandwidth tests only"
        echo ""
        echo "Results will be saved to: $RESULTS_DIR/session_TIMESTAMP/"
        exit 1
        ;;
esac