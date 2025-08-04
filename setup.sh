#!/bin/bash
# Manual setup script for ExpressRoute monitoring
# Run this script to create all monitoring scripts and directories

echo "Setting up ExpressRoute monitoring scripts..."

# Create directory structure
mkdir -p ~/expressroute-validation/{scripts,logs,data,reports}

# Create network metrics script
cat > ~/expressroute-validation/scripts/network-metrics.sh << 'EOF'
#!/bin/bash
# ExpressRoute Network Metrics Collection Script

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_DIR="$HOME/expressroute-validation/logs"
DATA_DIR="$HOME/expressroute-validation/data"

# Create directories if they don't exist
mkdir -p "$LOG_DIR" "$DATA_DIR"

# Create log entry
echo "[$TIMESTAMP] Starting network metrics collection" >> "$LOG_DIR/metrics.log"

# Test internet connectivity
echo "[$TIMESTAMP] Testing internet connectivity" >> "$LOG_DIR/metrics.log"
if ping -c 4 8.8.8.8 > "$DATA_DIR/ping-internet-$(date +%Y%m%d_%H%M%S).txt" 2>&1; then
    echo "[$TIMESTAMP] Internet connectivity: SUCCESS" >> "$LOG_DIR/metrics.log"
else
    echo "[$TIMESTAMP] Internet connectivity: FAILED" >> "$LOG_DIR/metrics.log"
fi

# Test DNS resolution
echo "[$TIMESTAMP] Testing DNS resolution" >> "$LOG_DIR/metrics.log"
if nslookup google.com > "$DATA_DIR/dns-test-$(date +%Y%m%d_%H%M%S).txt" 2>&1; then
    echo "[$TIMESTAMP] DNS resolution: SUCCESS" >> "$LOG_DIR/metrics.log"
else
    echo "[$TIMESTAMP] DNS resolution: FAILED" >> "$LOG_DIR/metrics.log"
fi

# Capture routing table
ip route > "$DATA_DIR/route-table-$(date +%Y%m%d_%H%M%S).txt"

# Capture network interfaces
ip addr > "$DATA_DIR/interfaces-$(date +%Y%m%d_%H%M%S).txt"

# Test connectivity to peer VM
PEER_IP="137.75.100.10"
if [[ $(hostname) == *"hub"* ]]; then
    PEER_IP="137.75.101.10"
fi

echo "[$TIMESTAMP] Testing connectivity to peer VM: $PEER_IP" >> "$LOG_DIR/metrics.log"
if ping -c 4 "$PEER_IP" > "$DATA_DIR/ping-peer-$(date +%Y%m%d_%H%M%S).txt" 2>&1; then
    echo "[$TIMESTAMP] Peer connectivity: SUCCESS" >> "$LOG_DIR/metrics.log"
else
    echo "[$TIMESTAMP] Peer connectivity: FAILED" >> "$LOG_DIR/metrics.log"
fi

# Test traceroute to peer
echo "[$TIMESTAMP] Running traceroute to peer VM" >> "$LOG_DIR/metrics.log"
traceroute "$PEER_IP" > "$DATA_DIR/traceroute-peer-$(date +%Y%m%d_%H%M%S).txt" 2>&1

# Test traceroute to internet
echo "[$TIMESTAMP] Running traceroute to internet" >> "$LOG_DIR/metrics.log"
traceroute 8.8.8.8 > "$DATA_DIR/traceroute-internet-$(date +%Y%m%d_%H%M%S).txt" 2>&1

# Capture network statistics
ss -tuln > "$DATA_DIR/network-stats-$(date +%Y%m%d_%H%M%S).txt"

echo "[$TIMESTAMP] Network metrics collection completed" >> "$LOG_DIR/metrics.log"
EOF

# Create iPerf test script
cat > ~/expressroute-validation/scripts/iperf-test.sh << 'EOF'
#!/bin/bash
# iPerf3 Performance Testing Script

TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
LOG_DIR="$HOME/expressroute-validation/logs"
DATA_DIR="$HOME/expressroute-validation/data"

# Create directories if they don't exist
mkdir -p "$LOG_DIR" "$DATA_DIR"

# Determine peer IP based on current VM
PEER_IP="137.75.100.10"
if [[ $(hostname) == *"hub"* ]]; then
    PEER_IP="137.75.101.10"
    echo "Running from HUB VM, testing to SPOKE VM: $PEER_IP"
else
    echo "Running from SPOKE VM, testing to HUB VM: $PEER_IP"
fi

echo "Starting iPerf3 performance tests at $TIMESTAMP"
echo "Target: $PEER_IP"

# Check if iPerf3 server is running on target
echo "Checking if iPerf3 server is accessible on $PEER_IP:5201..."
if nc -z "$PEER_IP" 5201 -w 5; then
    echo "✓ iPerf3 server is accessible"
else
    echo "✗ iPerf3 server is not accessible. Make sure it's running on the target VM."
    echo "Run: sudo systemctl start iperf3-server"
    exit 1
fi

# TCP Test - 30 seconds
echo "Running TCP test (30 seconds)..."
iperf3 -c "$PEER_IP" -p 5201 -t 30 -i 5 --json > "$DATA_DIR/iperf-tcp-$TIMESTAMP.json" 2>&1
if [ $? -eq 0 ]; then
    echo "✓ TCP test completed successfully"
    # Extract key metrics
    grep -E '"sum_sent"|"sum_received"' "$DATA_DIR/iperf-tcp-$TIMESTAMP.json" | tail -2
else
    echo "✗ TCP test failed"
fi

sleep 2

# UDP Test - 30 seconds, 100Mbps target
echo "Running UDP test (30 seconds, 100Mbps target)..."
iperf3 -c "$PEER_IP" -p 5201 -u -b 100M -t 30 -i 5 --json > "$DATA_DIR/iperf-udp-$TIMESTAMP.json" 2>&1
if [ $? -eq 0 ]; then
    echo "✓ UDP test completed successfully"
else
    echo "✗ UDP test failed"
fi

sleep 2

# Parallel streams test
echo "Running parallel streams test (10 streams, 20 seconds)..."
iperf3 -c "$PEER_IP" -p 5201 -t 20 -P 10 --json > "$DATA_DIR/iperf-parallel-$TIMESTAMP.json" 2>&1
if [ $? -eq 0 ]; then
    echo "✓ Parallel streams test completed successfully"
else
    echo "✗ Parallel streams test failed"
fi

# Log completion
echo "[$TIMESTAMP] iPerf3 tests completed. Results saved to $DATA_DIR" >> "$LOG_DIR/metrics.log"
echo "iPerf3 tests completed. Results saved to $DATA_DIR"
echo ""
echo "To view results:"
echo "  TCP: cat $DATA_DIR/iperf-tcp-$TIMESTAMP.json"
echo "  UDP: cat $DATA_DIR/iperf-udp-$TIMESTAMP.json"
echo "  Parallel: cat $DATA_DIR/iperf-parallel-$TIMESTAMP.json"
EOF

# Create continuous monitoring script
cat > ~/expressroute-validation/scripts/continuous-monitoring.sh << 'EOF'
#!/bin/bash
# Continuous Network Monitoring Script

LOG_DIR="$HOME/expressroute-validation/logs"
DATA_DIR="$HOME/expressroute-validation/data"

echo "Starting continuous network monitoring..."
echo "Logs: $LOG_DIR/continuous-monitor.log"
echo "Data: $DATA_DIR/"
echo "Press Ctrl+C to stop"

# Create log file
touch "$LOG_DIR/continuous-monitor.log"

# Trap Ctrl+C
trap 'echo "Monitoring stopped at $(date)" >> "$LOG_DIR/continuous-monitor.log"; exit 0' INT

echo "Continuous monitoring started at $(date)" >> "$LOG_DIR/continuous-monitor.log"

while true; do
    echo "Running metrics collection at $(date)..." | tee -a "$LOG_DIR/continuous-monitor.log"
    "$HOME/expressroute-validation/scripts/network-metrics.sh"
    echo "Sleeping for 5 minutes..." | tee -a "$LOG_DIR/continuous-monitor.log"
    sleep 300  # Run every 5 minutes
done
EOF

# Create diagnostic script
cat > ~/expressroute-validation/scripts/diagnose-connectivity.sh << 'EOF'
#!/bin/bash
# Comprehensive connectivity diagnostics

echo "=== ExpressRoute Connectivity Diagnostics ==="
echo "Timestamp: $(date)"
echo "Hostname: $(hostname)"
echo ""

# Basic network info
echo "=== Network Interfaces ==="
ip addr show
echo ""

echo "=== Routing Table ==="
ip route
echo ""

echo "=== DNS Configuration ==="
cat /etc/resolv.conf
echo ""

# Test local connectivity
echo "=== Local Connectivity Tests ==="
echo "Testing localhost..."
ping -c 2 127.0.0.1

echo ""
echo "Testing default gateway..."
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)
echo "Default gateway: $GATEWAY"
if [ -n "$GATEWAY" ]; then
    ping -c 2 "$GATEWAY"
fi

# Test peer VM
echo ""
echo "=== Peer VM Connectivity ==="
PEER_IP="137.75.100.10"
if [[ $(hostname) == *"hub"* ]]; then
    PEER_IP="137.75.101.10"
fi
echo "Peer VM IP: $PEER_IP"
ping -c 4 "$PEER_IP"

echo ""
echo "Traceroute to peer:"
traceroute "$PEER_IP"

# Test internet connectivity
echo ""
echo "=== Internet Connectivity ==="
echo "Testing Google DNS (8.8.8.8)..."
ping -c 4 8.8.8.8

echo ""
echo "Testing DNS resolution..."
nslookup google.com

echo ""
echo "Traceroute to internet:"
traceroute 8.8.8.8

# Test iPerf3 server
echo ""
echo "=== iPerf3 Server Status ==="
sudo systemctl status iperf3-server --no-pager

echo ""
echo "Testing iPerf3 server port..."
ss -tuln | grep 5201

echo ""
echo "Testing connection to peer iPerf3 server..."
nc -z "$PEER_IP" 5201 -w 5 && echo "✓ Peer iPerf3 server accessible" || echo "✗ Peer iPerf3 server not accessible"

echo ""
echo "=== System Resources ==="
echo "Memory usage:"
free -h
echo ""
echo "Disk usage:"
df -h
echo ""
echo "Load average:"
uptime

echo ""
echo "=== Active Connections ==="
ss -tuln

echo ""
echo "=== Recent Logs ==="
echo "Cloud-init status:"
sudo cloud-init status

echo ""
echo "Recent system messages:"
sudo journalctl --no-pager -n 20

echo ""
echo "=== Diagnostics Complete ==="
EOF

# Create report generator script
cat > ~/expressroute-validation/scripts/generate-report.sh << 'EOF'
#!/bin/bash
# Generate performance and connectivity report

REPORT_DIR="$HOME/expressroute-validation/reports"
DATA_DIR="$HOME/expressroute-validation/data"
LOG_DIR="$HOME/expressroute-validation/logs"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
REPORT_FILE="$REPORT_DIR/expressroute-report-$TIMESTAMP.txt"

mkdir -p "$REPORT_DIR"

echo "Generating ExpressRoute Performance Report..."

cat > "$REPORT_FILE" << REPORT_EOF
=== ExpressRoute Performance and Connectivity Report ===
Generated: $(date)
Hostname: $(hostname)

=== Summary of Latest Tests ===
REPORT_EOF

# Add latest connectivity results
if [ -f "$LOG_DIR/metrics.log" ]; then
    echo "" >> "$REPORT_FILE"
    echo "=== Recent Connectivity Status ===" >> "$REPORT_FILE"
    tail -20 "$LOG_DIR/metrics.log" >> "$REPORT_FILE"
fi

# Add latest iPerf3 results
echo "" >> "$REPORT_FILE"
echo "=== Latest Performance Tests ===" >> "$REPORT_FILE"

# Find latest iPerf3 files
LATEST_TCP=$(ls -t "$DATA_DIR"/iperf-tcp-*.json 2>/dev/null | head -1)
LATEST_UDP=$(ls -t "$DATA_DIR"/iperf-udp-*.json 2>/dev/null | head -1)

if [ -n "$LATEST_TCP" ]; then
    echo "TCP Test Results:" >> "$REPORT_FILE"
    if command -v jq >/dev/null 2>&1; then
        jq '.end.sum_sent.bits_per_second, .end.sum_received.bits_per_second' "$LATEST_TCP" 2>/dev/null >> "$REPORT_FILE" || echo "Could not parse TCP results" >> "$REPORT_FILE"
    else
        echo "Latest TCP test: $(basename $LATEST_TCP)" >> "$REPORT_FILE"
    fi
fi

if [ -n "$LATEST_UDP" ]; then
    echo "UDP Test Results:" >> "$REPORT_FILE"
    if command -v jq >/dev/null 2>&1; then
        jq '.end.sum.bits_per_second, .end.sum.jitter_ms, .end.sum.lost_percent' "$LATEST_UDP" 2>/dev/null >> "$REPORT_FILE" || echo "Could not parse UDP results" >> "$REPORT_FILE"
    else
        echo "Latest UDP test: $(basename $LATEST_UDP)" >> "$REPORT_FILE"
    fi
fi

# Add network information
echo "" >> "$REPORT_FILE"
echo "=== Current Network Configuration ===" >> "$REPORT_FILE"
ip route >> "$REPORT_FILE"

echo "" >> "$REPORT_FILE"
echo "=== Available Data Files ===" >> "$REPORT_FILE"
ls -la "$DATA_DIR" >> "$REPORT_FILE"

echo ""
echo "Report generated: $REPORT_FILE"
echo "To view: cat $REPORT_FILE"
EOF

# Make all scripts executable
chmod +x ~/expressroute-validation/scripts/*.sh

# Create README
cat > ~/expressroute-validation/README.txt << 'EOF'
ExpressRoute VM Bootstrap completed!

Available Scripts:
- scripts/network-metrics.sh          - Collect connectivity and network metrics
- scripts/iperf-test.sh              - Run comprehensive iPerf3 performance tests
- scripts/continuous-monitoring.sh    - Start continuous monitoring (every 5 minutes)
- scripts/diagnose-connectivity.sh   - Full network diagnostics
- scripts/generate-report.sh         - Generate performance report

Directories:
- logs/: Monitoring and test logs
- data/: Raw performance and connectivity data  
- reports/: Generated reports and summaries

Services:
- iPerf3 server should be running on port 5201
- Check status: sudo systemctl status iperf3-server

Quick Commands:
- Run diagnostics: ./expressroute-validation/scripts/diagnose-connectivity.sh
- Test performance: ./expressroute-validation/scripts/iperf-test.sh
- Monitor logs: tail -f expressroute-validation/logs/metrics.log
- Generate report: ./expressroute-validation/scripts/generate-report.sh

Troubleshooting:
- Check cloud-init: sudo cloud-init status
- View cloud-init logs: sudo cat /var/log/cloud-init-output.log
- Restart iPerf3: sudo systemctl restart iperf3-server
EOF

echo "✓ Directory structure created"
echo "✓ All monitoring scripts created and made executable"
echo "✓ README file created"
echo ""
echo "Next steps:"
echo "1. Check if iPerf3 server is running: sudo systemctl status iperf3-server"
echo "2. If not running, start it: sudo systemctl start iperf3-server"
echo "3. Run diagnostics: ./expressroute-validation/scripts/diagnose-connectivity.sh"
echo "4. Test performance: ./expressroute-validation/scripts/iperf-test.sh"
echo ""
echo "To check what went wrong with cloud-init:"
echo "sudo cloud-init status"
echo "sudo cat /var/log/cloud-init-output.log | tail -50"