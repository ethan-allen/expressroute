#!/bin/bash
# Express Route Bandwidth Testing Scripts
# Comprehensive testing per CIDR space

TESTING_DIR="/opt/expressroute-testing"
RESULTS_DIR="$TESTING_DIR/results"
LOGS_DIR="$TESTING_DIR/logs"
CONFIG_DIR="$TESTING_DIR/configs"

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
    iperf3 -c $target_ip -t $duration -P $parallel -J > "$SESSION_DIR/tcp_${target_name}_${target_ip}_download.json" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        # Extract key metrics
        local bandwidth=$(jq -r '.end.sum_received.bits_per_second' "$SESSION_DIR/tcp_${target_name}_${target_ip}_download.json" 2>/dev/null)
        local mbps=$(echo "scale=2; $bandwidth / 1000000" | bc 2>/dev/null)
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
    
    iperf3 -c $target_ip -u -b $bandwidth_limit -t $duration -J > "$SESSION_DIR/udp_${target_name}_${target_ip}.json" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        local bandwidth=$(jq -r '.end.sum.bits_per_second' "$SESSION_DIR/udp_${target_name}_${target_ip}.json" 2>/dev/null)
        local loss=$(jq -r '.end.sum.lost_percent' "$SESSION_DIR/udp_${target_name}_${target_ip}.json" 2>/dev/null)
        local mbps=$(echo "scale=2; $bandwidth / 1000000" | bc 2>/dev/null)
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
        local avg_latency=$(grep "rtt min/avg/max/mdev" "$SESSION_DIR/ping_${target_name}_${target_ip}.txt" | cut -d'/' -f5)
        local packet_loss=$(grep "packet loss" "$SESSION_DIR/ping_${target_name}_${target_ip}.txt" | grep -o '[0-9]*%' | head -1)
        log_message "Latency: $target_name - Avg: ${avg_latency}ms, Loss: $packet_loss"
        echo "$TIMESTAMP,$target_name,$target_ip,ICMP,Latency,$avg_latency,$packet_loss" >> "$SESSION_DIR/latency_summary.csv"
    else
        log_message "Ping test failed for $target_name ($target_ip)"
        echo "$TIMESTAMP,$target_name,$target_ip,ICMP,Latency,999,100%" >> "$SESSION_DIR/latency_summary.csv"
    fi
}

# Function to test HTTP throughput
test_http_throughput() {
    local target_ip=$1
    local target_name=$2
    local port=${3:-80}
    
    log_message "Testing HTTP throughput to $target_name ($target_ip:$port)"
    
    # Create a test file URL or use a standard test
    local test_url="http://$target_ip:$port/"
    
    # Test with curl
    curl -w "@-" -o /dev/null -s "$test_url" << 'EOF' > "$SESSION_DIR/http_${target_name}_${target_ip}.txt" 2>&1
     time_namelookup:  %{time_namelookup}\n
        time_connect:  %{time_connect}\n
     time_appconnect:  %{time_appconnect}\n
    time_pretransfer:  %{time_pretransfer}\n
       time_redirect:  %{time_redirect}\n
  time_starttransfer:  %{time_starttransfer}\n
                     ----------\n
          time_total:  %{time_total}\n
         size_download: %{size_download}\n
         speed_download: %{speed_download}\n
EOF
    
    if [ $? -eq 0 ]; then
        local download_speed=$(grep "speed_download" "$SESSION_DIR/http_${target_name}_${target_ip}.txt" | awk '{print $2}')
        local total_time=$(grep "time_total" "$SESSION_DIR/http_${target_name}_${target_ip}.txt" | awk '{print $2}')
        log_message "HTTP: $target_name - Speed: ${download_speed} bytes/sec, Time: ${total_time}s"
        echo "$TIMESTAMP,$target_name,$target_ip,HTTP,Download,$download_speed,$total_time" >> "$SESSION_DIR/http_summary.csv"
    else
        log_message "HTTP test failed for $target_name ($target_ip:$port)"
        echo "$TIMESTAMP,$target_name,$target_ip,HTTP,Download,0,999" >> "$SESSION_DIR/http_summary.csv"
    fi
}

# Function to test using Microsoft ntttcp
test_ntttcp_bandwidth() {
    local target_ip=$1
    local target_name=$2
    local duration=${3:-60}
    
    log_message "Testing with ntttcp to $target_name ($target_ip)"
    
    # Note: This requires ntttcp server running on target
    # ntttcp -s -m 1 -t $duration -p 5001 on the server side
    ntttcp -r -m 1 -t $duration -s $target_ip -p 5001 > "$SESSION_DIR/ntttcp_${target_name}_${target_ip}.txt" 2>&1
    
    if [ $? -eq 0 ]; then
        local throughput=$(grep "throughput" "$SESSION_DIR/ntttcp_${target_name}_${target_ip}.txt" | tail -1)
        log_message "NTTTCP: $target_name - $throughput"
        echo "$TIMESTAMP,$target_name,$target_ip,NTTTCP,Download,$throughput" >> "$SESSION_DIR/ntttcp_summary.csv"
    else
        log_message "NTTTCP test failed for $target_name ($target_ip) - server may not be running"
        echo "$TIMESTAMP,$target_name,$target_ip,NTTTCP,Download,Failed" >> "$SESSION_DIR/ntttcp_summary.csv"
    fi
}

# Function to trace route and analyze path
trace_route_analysis() {
    local target_ip=$1
    local target_name=$2
    
    log_message "Tracing route to $target_name ($target_ip)"
    
    # Multiple trace methods
    traceroute -n $target_ip > "$SESSION_DIR/traceroute_${target_name}_${target_ip}.txt" 2>&1
    mtr -r -c 10 $target_ip > "$SESSION_DIR/mtr_${target_name}_${target_ip}.txt" 2>&1
    
    # Extract hop count and identify Express Route path
    local hop_count=$(grep -c "^ [0-9]" "$SESSION_DIR/traceroute_${target_name}_${target_ip}.txt")
    log_message "Route analysis: $target_name - $hop_count hops"
    echo "$TIMESTAMP,$target_name,$target_ip,Route,Analysis,$hop_count" >> "$SESSION_DIR/route_summary.csv"
}

# Function to test Express Route specific metrics
test_expressroute_metrics() {
    log_message "Collecting Express Route metrics from Azure"
    
    # Get Express Route circuit metrics (requires circuit details)
    if [ -f "$CONFIG_DIR/expressroute-circuits.conf" ]; then
        while IFS='|' read -r circuit_name resource_group subscription_id location; do
            if [[ ! $circuit_name =~ ^#.*$ ]] && [ ! -z "$circuit_name" ]; then
                log_message "Collecting metrics for circuit: $circuit_name"
                
                # Get circuit state
                az network express-route show \
                    --resource-group "$resource_group" \
                    --name "$circuit_name" \
                    --subscription "$subscription_id" \
                    --query '{name:name,state:serviceProviderProperties.serviceProviderState,bandwidth:serviceProviderProperties.bandwidthInMbps}' \
                    > "$SESSION_DIR/circuit_${circuit_name}_state.json" 2>/dev/null
                
                # Get peering information
                az network express-route peering list \
                    --circuit-name "$circuit_name" \
                    --resource-group "$resource_group" \
                    --subscription "$subscription_id" \
                    > "$SESSION_DIR/circuit_${circuit_name}_peerings.json" 2>/dev/null
            fi
        done < "$CONFIG_DIR/expressroute-circuits.conf"
    else
        log_message "Express Route circuit configuration not found"
    fi
    
    # Get route table metrics
    az network route-table list \
        --resource-group "NWAVE-EAST" \
        --query '[].{name:name,routes:length(routes),subnets:length(subnets)}' \
        > "$SESSION_DIR/route_tables_metrics.json" 2>/dev/null
}

# Main testing function
run_comprehensive_test() {
    local test_type=${1:-"basic"}
    
    log_message "Starting comprehensive Express Route testing - Type: $test_type"
    
    # Create CSV headers
    echo "Timestamp,Target_Name,Target_IP,Protocol,Direction,Bandwidth_bps,Bandwidth_Mbps,Loss_Percent" > "$SESSION_DIR/bandwidth_summary.csv"
    echo "Timestamp,Target_Name,Target_IP,Protocol,Metric,Value,Additional" > "$SESSION_DIR/latency_summary.csv"
    echo "Timestamp,Target_Name,Target_IP,Protocol,Direction,Speed,Time" > "$SESSION_DIR/http_summary.csv"
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
                    test_tcp_bandwidth "$ip" "$name" 30 1
                    test_udp_bandwidth "$ip" "$name" "50M" 30
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
    test_http_throughput "www.google.com" "Google" 80
    
    if [ "$test_type" = "full" ]; then
        # Additional internet bandwidth tests
        log_message "Running internet speed test..."
        speedtest-cli --json > "$SESSION_DIR/speedtest_results.json" 2>/dev/null
    fi
    
    # Collect Express Route metrics
    test_expressroute_metrics
    
    # Generate summary report
    generate_test_report
    
    log_message "Comprehensive testing completed. Results in: $SESSION_DIR"
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
        # Run only latency tests
        ;;
    "bandwidth")
        log_message "Running bandwidth-only tests"
        # Run only bandwidth tests
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