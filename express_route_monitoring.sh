#!/bin/bash
# Express Route Monitoring and Continuous Analysis Scripts

TESTING_DIR="/opt/expressroute-testing"
RESULTS_DIR="$TESTING_DIR/results"
LOGS_DIR="$TESTING_DIR/logs"
CONFIG_DIR="$TESTING_DIR/configs"

# Function to collect Azure Express Route metrics
collect_expressroute_metrics() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local metrics_file="$RESULTS_DIR/expressroute_metrics_$timestamp.json"
    
    echo "=== Collecting Express Route Metrics ===" | tee -a "$LOGS_DIR/monitoring.log"
    
    # Get all Express Route circuits in the subscription
    az network express-route list \
        --query '[].{name:name,resourceGroup:resourceGroup,location:location,serviceProviderState:serviceProviderProperties.serviceProviderState,bandwidth:serviceProviderProperties.bandwidthInMbps,sku:sku.tier}' \
        > "$metrics_file"
    
    # Get detailed metrics for specific resource group
    az network express-route list \
        --resource-group "NWAVE-EAST" \
        --query '[].{name:name,provisioningState:provisioningState,circuitProvisioningState:circuitProvisioningState,serviceKey:serviceKey}' \
        > "$RESULTS_DIR/expressroute_east_details_$timestamp.json"
    
    # Get route table information
    az network route-table list \
        --resource-group "NWAVE-EAST" \
        --query '[].{name:name,location:location,routes:length(routes),associatedSubnets:length(subnets),disableBgpRoutePropagation:disableBgpRoutePropagation}' \
        > "$RESULTS_DIR/route_tables_$timestamp.json"
    
    # Get VNet Gateway information (Express Route Gateways)
    az network vnet-gateway list \
        --resource-group "NWAVE-EAST" \
        --query '[].{name:name,gatewayType:gatewayType,vpnType:vpnType,sku:sku.name,provisioningState:provisioningState}' \
        > "$RESULTS_DIR/vnet_gateways_$timestamp.json" 2>/dev/null
    
    echo "Express Route metrics collected at $timestamp" | tee -a "$LOGS_DIR/monitoring.log"
    return 0
}

# Function to analyze bandwidth utilization patterns
analyze_bandwidth_patterns() {
    local days_back=${1:-7}
    echo "=== Analyzing Bandwidth Patterns (Last $days_back days) ===" | tee -a "$LOGS_DIR/monitoring.log"
    
    # Find all bandwidth test results from the last N days
    local analysis_file="$RESULTS_DIR/bandwidth_analysis_$(date +%Y%m%d).txt"
    
    echo "Bandwidth Analysis Report - Generated: $(date)" > "$analysis_file"
    echo "=========================================" >> "$analysis_file"
    echo "" >> "$analysis_file"
    
    # Analyze results from recent sessions
    for session_dir in $(find "$RESULTS_DIR" -name "session_*" -type d -mtime -$days_back | sort); do
        if [ -f "$session_dir/bandwidth_summary.csv" ]; then
            echo "Session: $(basename $session_dir)" >> "$analysis_file"
            echo "----------------------------------------" >> "$analysis_file"
            
            # Calculate average bandwidth per target
            awk -F',' '
            NR>1 && $4=="TCP" && $5=="Download" {
                target_sum[$2] += $7
                target_count[$2]++
            }
            END {
                for (target in target_sum) {
                    avg = target_sum[target] / target_count[target]
                    printf "%-20s: %.2f Mbps (avg from %d tests)\n", target, avg, target_count[target]
                }
            }' "$session_dir/bandwidth_summary.csv" >> "$analysis_file"
            echo "" >> "$analysis_file"
        fi
    done
    
    # Generate recommendations
    echo "RECOMMENDATIONS:" >> "$analysis_file"
    echo "---------------" >> "$analysis_file"
    echo "1. Monitor targets with bandwidth < 10 Mbps" >> "$analysis_file"
    echo "2. Check routing for targets with high latency (>100ms)" >> "$analysis_file"
    echo "3. Investigate packet loss > 1%" >> "$analysis_file"
    echo "" >> "$analysis_file"
    
    echo "Bandwidth analysis completed: $analysis_file" | tee -a "$LOGS_DIR/monitoring.log"
}

# Function to monitor Express Route health
monitor_expressroute_health() {
    local health_file="$RESULTS_DIR/health_check_$(date +%Y%m%d_%H%M%S).json"
    local alert_file="$LOGS_DIR/alerts.log"
    
    echo "=== Express Route Health Monitoring ===" | tee -a "$LOGS_DIR/monitoring.log"
    
    # Check virtual appliance connectivity
    local appliance_status="healthy"
    
    # Test primary appliances
    for appliance in "137.75.100.6:EAST-FGT-A" "137.75.100.7:EAST-FGT-B" "10.28.128.11:HUB-NEXTHOP-PRV"; do
        local ip=$(echo $appliance | cut -d':' -f1)
        local name=$(echo $appliance | cut -d':' -f2)
        
        if ! ping -c 3 -W 5 "$ip" >/dev/null 2>&1; then
            echo "ALERT: $(date) - $name ($ip) is unreachable" | tee -a "$alert_file"
            appliance_status="degraded"
        else
            echo "OK: $name ($ip) is reachable" | tee -a "$LOGS_DIR/monitoring.log"
        fi
    done
    
    # Check route table consistency
    local route_status="healthy"
    expected_routes=("EAST-SPOKE-1-PRV-RT" "EAST-SPOKE-1-PUB-RT" "EAST-HUB-GATEWAY-RT")
    
    for route_table in "${expected_routes[@]}"; do
        if ! az network route-table show --resource-group "NWAVE-EAST" --name "$route_table" >/dev/null 2>&1; then
            echo "ALERT: $(date) - Route table $route_table is missing" | tee -a "$alert_file"
            route_status="critical"
        fi
    done
    
    # Generate health report
    cat > "$health_file" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "overall_status": "${appliance_status}_${route_status}",
    "virtual_appliances": {
        "status": "$appliance_status",
        "tested": ["EAST-FGT-A", "EAST-FGT-B", "HUB-NEXTHOP-PRV"]
    },
    "route_tables": {
        "status": "$route_status",
        "tested": $(printf '%s\n' "${expected_routes[@]}" | jq -R . | jq -s .)
    },
    "connectivity_tests": {
        "internet_reachable": $(ping -c 1 8.8.8.8 >/dev/null 2>&1 && echo "true" || echo "false"),
        "dns_resolution": $(nslookup google.com >/dev/null 2>&1 && echo "true" || echo "false")
    }
}
EOF
    
    echo "Health check completed: $health_file" | tee -a "$LOGS_DIR/monitoring.log"
}

# Function to create performance baseline
create_performance_baseline() {
    local baseline_file="$RESULTS_DIR/performance_baseline_$(date +%Y%m%d).json"
    
    echo "=== Creating Performance Baseline ===" | tee -a "$LOGS_DIR/monitoring.log"
    
    # Run baseline tests to all key targets
    local targets=("137.75.100.6:EAST-FGT-A" "137.75.100.7:EAST-FGT-B" "8.8.8.8:Internet")
    
    echo "{" > "$baseline_file"
    echo "  \"timestamp\": \"$(date -Iseconds)\"," >> "$baseline_file"
    echo "  \"baseline_results\": {" >> "$baseline_file"
    
    local first=true
    for target in "${targets[@]}"; do
        local ip=$(echo $target | cut -d':' -f1)
        local name=$(echo $target | cut -d':' -f2)
        
        if [ "$first" = false ]; then
            echo "," >> "$baseline_file"
        fi
        first=false
        
        echo "    \"$name\": {" >> "$baseline_file"
        
        # Ping test for latency
        local ping_result=$(ping -c 10 -i 0.5 "$ip" 2>/dev/null | grep "rtt min/avg/max/mdev" | cut -d'/' -f5)
        local packet_loss=$(ping -c 10 "$ip" 2>/dev/null | grep "packet loss" | grep -o '[0-9]*%')
        
        echo "      \"latency_ms\": \"${ping_result:-999}\"," >> "$baseline_file"
        echo "      \"packet_loss\": \"${packet_loss:-100%}\"," >> "$baseline_file"
        
        # Quick bandwidth test if reachable
        if ping -c 1 -W 5 "$ip" >/dev/null 2>&1; then
            # Use a quick iperf3 test (5 seconds)
            local bandwidth=$(timeout 10 iperf3 -c "$ip" -t 5 -J 2>/dev/null | jq -r '.end.sum_received.bits_per_second // 0')
            local mbps=$(echo "scale=2; $bandwidth / 1000000" | bc 2>/dev/null)
            echo "      \"bandwidth_mbps\": \"${mbps:-0}\"" >> "$baseline_file"
        else
            echo "      \"bandwidth_mbps\": \"0\"" >> "$baseline_file"
        fi
        
        echo "    }" >> "$baseline_file"
    done
    
    echo "  }" >> "$baseline_file"
    echo "}" >> "$baseline_file"
    
    echo "Performance baseline created: $baseline_file" | tee -a "$LOGS_DIR/monitoring.log"
}

# Function to setup automated monitoring
setup_automated_monitoring() {
    echo "=== Setting up Automated Monitoring ===" | tee -a "$LOGS_DIR/monitoring.log"
    
    # Create monitoring script
    cat > "$TESTING_DIR/scripts/automated_monitor.sh" << 'EOF'
#!/bin/bash
# Automated Express Route monitoring script

TESTING_DIR="/opt/expressroute-testing"
source "$TESTING_DIR/scripts/express_route_monitoring.sh"

# Run health check
monitor_expressroute_health

# Collect metrics every hour
if [ $(date +%M) -eq 0 ]; then
    collect_expressroute_metrics
fi

# Run performance tests every 6 hours
if [ $(date +%H) -eq 0 ] || [ $(date +%H) -eq 6 ] || [ $(date +%H) -eq 12 ] || [ $(date +%H) -eq 18 ]; then
    if [ $(date +%M) -eq 30 ]; then
        # Run basic performance test
        bash "$TESTING_DIR/scripts/express_route_bandwidth_testing.sh" basic
    fi
fi

# Weekly analysis (Sunday at 02:00)
if [ $(date +%w) -eq 0 ] && [ $(date +%H) -eq 2 ] && [ $(date +%M) -eq 0 ]; then
    analyze_bandwidth_patterns 7
fi
EOF
    
    chmod +x "$TESTING_DIR/scripts/automated_monitor.sh"
    
    # Create cron job (run every 15 minutes)
    (crontab -l 2>/dev/null; echo "*/15 * * * * $TESTING_DIR/scripts/automated_monitor.sh") | crontab -
    
    echo "Automated monitoring setup complete" | tee -a "$LOGS_DIR/monitoring.log"
    echo "Cron job installed to run every 15 minutes" | tee -a "$LOGS_DIR/monitoring.log"
}

# Function to generate performance dashboard data
generate_dashboard_data() {
    local dashboard_data="$RESULTS_DIR/dashboard_data.json"
    
    echo "=== Generating Dashboard Data ===" | tee -a "$LOGS_DIR/monitoring.log"
    
    # Collect recent results for dashboard
    cat > "$dashboard_data" << EOF
{
    "last_updated": "$(date -Iseconds)",
    "recent_tests": {
EOF
    
    # Find most recent test results
    local latest_session=$(find "$RESULTS_DIR" -name "session_*" -type d | sort | tail -1)
    
    if [ -n "$latest_session" ] && [ -d "$latest_session" ]; then
        echo "        \"latest_session\": \"$(basename $latest_session)\"," >> "$dashboard_data"
        
        # Add latency summary
        if [ -f "$latest_session/latency_summary.csv" ]; then
            echo "        \"latency_results\": [" >> "$dashboard_data"
            awk -F',' 'NR>1 {printf "            {\"target\": \"%s\", \"latency\": \"%s\", \"loss\": \"%s\"}%s\n", $2, $5, $6, (NR==lines) ? "" : ","}' \
                lines=$(wc -l < "$latest_session/latency_summary.csv") "$latest_session/latency_summary.csv" >> "$dashboard_data"
            echo "        ]," >> "$dashboard_data"
        fi
        
        # Add bandwidth summary
        if [ -f "$latest_session/bandwidth_summary.csv" ]; then
            echo "        \"bandwidth_results\": [" >> "$dashboard_data"
            awk -F',' 'NR>1 {printf "            {\"target\": \"%s\", \"protocol\": \"%s\", \"bandwidth_mbps\": \"%s\"}%s\n", $2, $4, $7, (NR==lines) ? "" : ","}' \
                lines=$(wc -l < "$latest_session/bandwidth_summary.csv") "$latest_session/bandwidth_summary.csv" >> "$dashboard_data"
            echo "        ]" >> "$dashboard_data"
        else
            echo "        \"bandwidth_results\": []" >> "$dashboard_data"
        fi
    else
        echo "        \"latest_session\": null," >> "$dashboard_data"
        echo "        \"latency_results\": []," >> "$dashboard_data"
        echo "        \"bandwidth_results\": []" >> "$dashboard_data"
    fi
    
    echo "    }," >> "$dashboard_data"
    echo "    \"system_info\": {" >> "$dashboard_data"
    echo "        \"hostname\": \"$(hostname)\"," >> "$dashboard_data"
    echo "        \"uptime\": \"$(uptime -p)\"," >> "$dashboard_data"
    echo "        \"load_average\": \"$(uptime | awk -F'load average:' '{print $2}' | xargs)\"" >> "$dashboard_data"
    echo "    }" >> "$dashboard_data"
    echo "}" >> "$dashboard_data"
    
    echo "Dashboard data generated: $dashboard_data" | tee -a "$LOGS_DIR/monitoring.log"
}

# Function to create alerts based on thresholds
check_performance_alerts() {
    local alert_file="$LOGS_DIR/performance_alerts.log"
    local latest_session=$(find "$RESULTS_DIR" -name "session_*" -type d | sort | tail -1)
    
    if [ -z "$latest_session" ] || [ ! -d "$latest_session" ]; then
        return 0
    fi
    
    echo "=== Checking Performance Alerts ===" | tee -a "$LOGS_DIR/monitoring.log"
    
    # Define thresholds
    local LATENCY_THRESHOLD=100  # ms
    local LOSS_THRESHOLD=5       # percent
    local BANDWIDTH_THRESHOLD=10 # Mbps
    
    # Check latency alerts
    if [ -f "$latest_session/latency_summary.csv" ]; then
        awk -F',' -v threshold=$LATENCY_THRESHOLD '
        NR>1 && $5 > threshold {
            print "ALERT: " strftime("%Y-%m-%d %H:%M:%S") " - High latency to " $2 ": " $5 "ms (threshold: " threshold "ms)"
        }' "$latest_session/latency_summary.csv" >> "$alert_file"
        
        awk -F',' -v threshold=$LOSS_THRESHOLD '
        NR>1 && ($6+0) > threshold {
            print "ALERT: " strftime("%Y-%m-%d %H:%M:%S") " - High packet loss to " $2 ": " $6 " (threshold: " threshold "%)"
        }' "$latest_session/latency_summary.csv" >> "$alert_file"
    fi
    
    # Check bandwidth alerts
    if [ -f "$latest_session/bandwidth_summary.csv" ]; then
        awk -F',' -v threshold=$BANDWIDTH_THRESHOLD '
        NR>1 && $7 < threshold && $7 > 0 {
            print "ALERT: " strftime("%Y-%m-%d %H:%M:%S") " - Low bandwidth to " $2 ": " $7 "Mbps (threshold: " threshold "Mbps)"
        }' "$latest_session/bandwidth_summary.csv" >> "$alert_file"
    fi
    
    echo "Performance alerts check completed" | tee -a "$LOGS_DIR/monitoring.log"
}

# Main function to run all monitoring tasks
run_monitoring_suite() {
    local mode=${1:-"standard"}
    
    case "$mode" in
        "health")
            monitor_expressroute_health
            ;;
        "metrics")
            collect_expressroute_metrics
            ;;
        "baseline")
            create_performance_baseline
            ;;
        "analysis")
            analyze_bandwidth_patterns
            ;;
        "dashboard")
            generate_dashboard_data
            ;;
        "alerts")
            check_performance_alerts
            ;;
        "setup")
            setup_automated_monitoring
            ;;
        "standard")
            monitor_expressroute_health
            collect_expressroute_metrics
            generate_dashboard_data
            check_performance_alerts
            ;;
        *)
            echo "Usage: $0 {health|metrics|baseline|analysis|dashboard|alerts|setup|standard}"
            echo ""
            echo "  health    - Check Express Route component health"
            echo "  metrics   - Collect Azure Express Route metrics"
            echo "  baseline  - Create performance baseline"
            echo "  analysis  - Analyze bandwidth patterns"
            echo "  dashboard - Generate dashboard data"
            echo "  alerts    - Check for performance alerts"
            echo "  setup     - Setup automated monitoring"
            echo "  standard  - Run standard monitoring suite"
            exit 1
            ;;
    esac
}

# If script is run directly, execute the monitoring suite
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    run_monitoring_suite "$1"
fi