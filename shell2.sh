# Run these commands directly on both VMs to set up monitoring

# Create directory structure
mkdir -p ~/expressroute-validation/{scripts,logs,data,reports}

# Create network metrics script
cat > ~/expressroute-validation/scripts/network-metrics.sh << 'SCRIPT1'
#!/bin/bash
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_DIR="$HOME/expressroute-validation/logs"
DATA_DIR="$HOME/expressroute-validation/data"

mkdir -p "$LOG_DIR" "$DATA_DIR"

echo "[$TIMESTAMP] Starting network metrics collection" >> "$LOG_DIR/metrics.log"

# Test internet connectivity
if ping -c 4 8.8.8.8 > "$DATA_DIR/ping-internet-$(date +%Y%m%d_%H%M%S).txt" 2>&1; then
    echo "[$TIMESTAMP] Internet connectivity: SUCCESS" >> "$LOG_DIR/metrics.log"
else
    echo "[$TIMESTAMP] Internet connectivity: FAILED" >> "$LOG_DIR/metrics.log"
fi

# Test DNS resolution
if nslookup google.com > "$DATA_DIR/dns-test-$(date +%Y%m%d_%H%M%S).txt" 2>&1; then
    echo "[$TIMESTAMP] DNS resolution: SUCCESS" >> "$LOG_DIR/metrics.log"
else
    echo "[$TIMESTAMP] DNS resolution: FAILED" >> "$LOG_DIR/metrics.log"
fi

# Determine peer IP
PEER_IP="137.75.100.10"
if [[ $(hostname) == *"hub"* ]]; then
    PEER_IP="137.75.101.10"
fi

# Test peer connectivity
if ping -c 4 "$PEER_IP" > "$DATA_DIR/ping-peer-$(date +%Y%m%d_%H%M%S).txt" 2>&1; then
    echo "[$TIMESTAMP] Peer connectivity to $PEER_IP: SUCCESS" >> "$LOG_DIR/metrics.log"
else
    echo "[$TIMESTAMP] Peer connectivity to $PEER_IP: FAILED" >> "$LOG_DIR/metrics.log"
fi

# Capture network info
ip route > "$DATA_DIR/route-table-$(date +%Y%m%d_%H%M%S).txt"
ip addr > "$DATA_DIR/interfaces-$(date +%Y%m%d_%H%M%S).txt"

echo "[$TIMESTAMP] Network metrics collection completed" >> "$LOG_DIR/metrics.log"
SCRIPT1

# Create iPerf test script
cat > ~/expressroute-validation/scripts/iperf-test.sh << 'SCRIPT2'
#!/bin/bash
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
DATA_DIR="$HOME/expressroute-validation/data"
mkdir -p "$DATA_DIR"

# Determine peer IP
PEER_IP="137.75.100.10"
if [[ $(hostname) == *"hub"* ]]; then
    PEER_IP="137.75.101.10"
    echo "Running from HUB VM, testing to SPOKE VM: $PEER_IP"
else
    echo "Running from SPOKE VM, testing to HUB VM: $PEER_IP"
fi

echo "Starting iPerf3 performance tests at $TIMESTAMP"
echo "Target: $PEER_IP"

# Check if server is accessible
if nc -z "$PEER_IP" 5201 -w 5; then
    echo "✓ iPerf3 server is accessible"
else
    echo "✗ iPerf3 server not accessible on $PEER_IP:5201"
    echo "Make sure iPerf3 server is running on target VM"
    exit 1
fi

# TCP Test
echo "Running TCP test (30 seconds)..."
iperf3 -c "$PEER_IP" -p 5201 -t 30 -i 5 > "$DATA_DIR/iperf-tcp-$TIMESTAMP.txt" 2>&1
echo "✓ TCP test completed"

# UDP Test
echo "Running UDP test (30 seconds)..."
iperf3 -c "$PEER_IP" -p 5201 -u -b 100M -t 30 -i 5 > "$DATA_DIR/iperf-udp-$TIMESTAMP.txt" 2>&1
echo "✓ UDP test completed"

echo "Results saved to $DATA_DIR/"
echo "TCP: cat $DATA_DIR/iperf-tcp-$TIMESTAMP.txt"
echo "UDP: cat $DATA_DIR/iperf-udp-$TIMESTAMP.txt"
SCRIPT2

# Create diagnostics script
cat > ~/expressroute-validation/scripts/diagnose.sh << 'SCRIPT3'
#!/bin/bash
echo "=== ExpressRoute Diagnostics ==="
echo "Timestamp: $(date)"
echo "Hostname: $(hostname)"
echo ""

echo "=== Network Interfaces ==="
ip addr
echo ""

echo "=== Routing Table ==="
ip route
echo ""

echo "=== Internet Connectivity Test ==="
ping -c 3 8.8.8.8
echo ""

echo "=== DNS Test ==="
nslookup google.com
echo ""

PEER_IP="137.75.100.10"
if [[ $(hostname) == *"hub"* ]]; then
    PEER_IP="137.75.101.10"
fi

echo "=== Peer VM Connectivity (${PEER_IP}) ==="
ping -c 3 "$PEER_IP"
echo ""

echo "=== iPerf3 Server Status ==="
sudo systemctl status iperf3-server --no-pager
echo ""

echo "=== Open Ports ==="
ss -tuln | grep 5201
echo ""

echo "=== Testing Peer iPerf3 Server ==="
nc -z "$PEER_IP" 5201 -w 5 && echo "✓ Accessible" || echo "✗ Not accessible"
SCRIPT3

# Make scripts executable
chmod +x ~/expressroute-validation/scripts/*.sh

# Install required packages
sudo apt update
sudo apt install -y iperf3 netcat-openbsd traceroute net-tools

# Create and start iPerf3 server service
sudo tee /etc/systemd/system/iperf3-server.service > /dev/null << 'SERVICE'
[Unit]
Description=iPerf3 Server for ExpressRoute Testing
After=network.target

[Service]
ExecStart=/usr/bin/iperf3 -s -p 5201
Restart=always
User=azureuser
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE

# Start the service
sudo systemctl daemon-reload
sudo systemctl enable iperf3-server
sudo systemctl start iperf3-server

# Create README
cat > ~/expressroute-validation/README.txt << 'README'
ExpressRoute Monitoring Setup Complete!

Available Scripts:
- scripts/network-metrics.sh  - Collect network metrics
- scripts/iperf-test.sh      - Run performance tests  
- scripts/diagnose.sh        - Full diagnostics

Quick Commands:
- Run diagnostics: ~/expressroute-validation/scripts/diagnose.sh
- Test performance: ~/expressroute-validation/scripts/iperf-test.sh
- Collect metrics: ~/expressroute-validation/scripts/network-metrics.sh

Check iPerf3 server: sudo systemctl status iperf3-server
README

echo "✅ Setup completed successfully!"
echo ""
echo "Next steps:"
echo "1. Run diagnostics: ~/expressroute-validation/scripts/diagnose.sh"
echo "2. Check iPerf3 server: sudo systemctl status iperf3-server" 
echo "3. Test performance: ~/expressroute-validation/scripts/iperf-test.sh"