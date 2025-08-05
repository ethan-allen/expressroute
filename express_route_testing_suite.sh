#!/bin/bash
# Express Route Performance Testing Suite Installation Script
# Run this on SPOKE1-Public-Monitor-VM

echo "=== Express Route Performance Testing Suite Installation ==="
echo "Installing comprehensive network testing tools..."

# Update system packages
sudo apt update && sudo apt upgrade -y

# Install essential network testing tools
echo "Installing network testing tools..."
sudo apt install -y \
    iperf3 \
    netperf \
    hping3 \
    tcptraceroute \
    mtr-tiny \
    nmap \
    curl \
    wget \
    jq \
    bc \
    dnsutils \
    net-tools \
    iproute2 \
    tcpdump \
    wireshark-common \
    tshark \
    iftop \
    nethogs \
    vnstat \
    bmon \
    nload \
    speedtest-cli \
    fping

# Install Azure CLI if not present
if ! command -v az &> /dev/null; then
    echo "Installing Azure CLI..."
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
fi

# Install additional performance tools
echo "Installing additional performance monitoring tools..."

# Install ntttcp (Microsoft's network throughput tool)
cd /tmp
wget https://github.com/Microsoft/ntttcp-for-linux/archive/master.zip
sudo apt install -y unzip build-essential
unzip master.zip
cd ntttcp-for-linux-master/src
make && sudo make install

# Install qperf for RDMA and other advanced testing
sudo apt install -y qperf

# Create testing directories
sudo mkdir -p /opt/expressroute-testing/{scripts,logs,results,configs}
sudo chown -R $USER:$USER /opt/expressroute-testing/

# Create system info collection script
cat > /opt/expressroute-testing/scripts/system-info.sh << 'EOF'
#!/bin/bash
echo "=== System Information ==="
echo "Hostname: $(hostname)"
echo "Date: $(date)"
echo "Uptime: $(uptime)"
echo "Kernel: $(uname -r)"
echo "OS: $(lsb_release -d | cut -f2)"
echo ""
echo "=== Network Interfaces ==="
ip addr show
echo ""
echo "=== Routing Table ==="
ip route show
echo ""
echo "=== Network Statistics ==="
ss -tuln
echo ""
echo "=== Memory Usage ==="
free -h
echo ""
echo "=== CPU Info ==="
lscpu | grep -E "Model name|CPU\(s\)|Thread|Core"
EOF

chmod +x /opt/expressroute-testing/scripts/system-info.sh

# Create CIDR ranges configuration file
cat > /opt/expressroute-testing/configs/cidr-ranges.conf << 'EOF'
# SPOKE and HUB CIDR Ranges for Testing
# Format: NAME|PRIVATE_CIDR|PUBLIC_CIDR|TEST_IP|DESCRIPTION

HUB|10.28.128.0/25|137.75.100.0/25|10.28.128.11|Hub Virtual Appliances
SPOKE-1|10.28.159.0/24|137.75.101.0/28|10.28.159.4|Current Spoke
OAR-ITMO|10.28.132.0/23|137.75.101.32/27|10.28.132.10|OAR ITMO Lab
OAR-ARL|10.28.134.0/23|137.75.101.64/28|10.28.134.10|OAR ARL Lab  
OAR-GSL|10.28.136.0/23|137.75.101.80/28|10.28.136.10|OAR GSL Lab
OAR-PMEL|10.28.138.0/23|137.75.101.96/28|10.28.138.10|OAR PMEL Lab
OAR-NSSL|10.28.140.0/23|137.75.101.112/28|10.28.140.10|OAR NSSL Lab
OAR-PSL|10.28.142.0/23|137.75.101.128/28|10.28.142.10|OAR PSL Lab
OCIO-HAES-VTI|10.28.158.0/24|137.75.101.240/28|10.28.158.10|OCIO HAES VTI
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

# Create virtual appliance endpoints configuration
cat > /opt/expressroute-testing/configs/virtual-appliances.conf << 'EOF'
# Virtual Appliance Endpoints
# Format: NAME|IP|PORT|DESCRIPTION

EAST-FGT-A|137.75.100.6|443|Primary FortiGate Appliance
EAST-FGT-B|137.75.100.7|443|Secondary FortiGate Appliance  
HUB-NEXTHOP-PRV|10.28.128.11|22|Private Network Next Hop
HUB-NEXTHOP-PUB|137.75.100.11|22|Public Network Next Hop
HUB-IPV6-NEXTHOP|2610:20:90E2::11|22|IPv6 Next Hop
EOF

# Create Express Route circuit information template
cat > /opt/expressroute-testing/configs/expressroute-circuits.conf << 'EOF'
# Express Route Circuit Information
# Update with your actual circuit details
# Format: CIRCUIT_NAME|RESOURCE_GROUP|SUBSCRIPTION_ID|PEERING_LOCATION

# Example (update with actual values):
# PRIMARY_CIRCUIT|NWAVE-EAST|f556ae2d-cc38-4d64-bb12-582f32c04de8|Washington DC
# SECONDARY_CIRCUIT|NWAVE-WEST|f556ae2d-cc38-4d64-bb12-582f32c04de8|Los Angeles

# Add your Express Route circuits here
EOF

# Install network testing web interface (optional)
echo "Setting up network testing dashboard..."
sudo apt install -y python3-pip python3-venv
python3 -m venv /opt/expressroute-testing/dashboard-env
source /opt/expressroute-testing/dashboard-env/bin/activate
pip install flask plotly pandas psutil

# Create initial dashboard
cat > /opt/expressroute-testing/scripts/dashboard.py << 'EOF'
#!/usr/bin/env python3
"""
Simple network testing dashboard
"""
import subprocess
import json
from flask import Flask, render_template_string
import plotly.graph_objs as go
import plotly.utils

app = Flask(__name__)

@app.route('/')
def dashboard():
    # Get system info
    try:
        result = subprocess.run(['bash', '/opt/expressroute-testing/scripts/system-info.sh'], 
                              capture_output=True, text=True)
        system_info = result.stdout
    except:
        system_info = "Unable to collect system information"
    
    template = '''
    <!DOCTYPE html>
    <html>
    <head><title>Express Route Testing Dashboard</title></head>
    <body>
        <h1>Express Route Performance Testing Dashboard</h1>
        <h2>System Information</h2>
        <pre>{{ system_info }}</pre>
        <h2>Available Tools</h2>
        <ul>
            <li>iperf3 - TCP/UDP bandwidth testing</li>
            <li>ntttcp - Microsoft network throughput testing</li>
            <li>qperf - RDMA and latency testing</li>
            <li>Custom Express Route testing scripts</li>
        </ul>
    </body>
    </html>
    '''
    return render_template_string(template, system_info=system_info)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=True)
EOF

deactivate

# Set up log rotation
sudo tee /etc/logrotate.d/expressroute-testing << 'EOF'
/opt/expressroute-testing/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    copytruncate
}
EOF

# Create startup script
cat > /opt/expressroute-testing/scripts/start-testing.sh << 'EOF'
#!/bin/bash
echo "=== Express Route Testing Environment ==="
echo "Installation Date: $(date)"
echo "Tools Available:"
echo "- iperf3: Network bandwidth testing"
echo "- ntttcp: Microsoft network throughput testing"  
echo "- qperf: RDMA and latency testing"
echo "- hping3: Custom packet testing"
echo "- mtr: Network route tracing"
echo "- Azure CLI: Express Route metrics"
echo ""
echo "Configuration Files:"
echo "- CIDR Ranges: /opt/expressroute-testing/configs/cidr-ranges.conf"
echo "- Virtual Appliances: /opt/expressroute-testing/configs/virtual-appliances.conf"
echo "- Express Route Circuits: /opt/expressroute-testing/configs/expressroute-circuits.conf"
echo ""
echo "Testing Scripts Location: /opt/expressroute-testing/scripts/"
echo "Results Location: /opt/expressroute-testing/results/"
echo "Logs Location: /opt/expressroute-testing/logs/"
echo ""
echo "To start dashboard: cd /opt/expressroute-testing && source dashboard-env/bin/activate && python3 scripts/dashboard.py"
EOF

chmod +x /opt/expressroute-testing/scripts/start-testing.sh

echo ""
echo "=== Installation Complete ==="
echo "Express Route testing suite installed successfully!"
echo ""
echo "Next Steps:"
echo "1. Review configuration files in /opt/expressroute-testing/configs/"
echo "2. Update Express Route circuit information"
echo "3. Run: /opt/expressroute-testing/scripts/start-testing.sh"
echo "4. Use the performance testing scripts provided"
echo ""
echo "Installation Summary:"
echo "- Testing tools: iperf3, ntttcp, qperf, hping3, mtr, and more"
echo "- Configuration templates created"
echo "- Logging and results directories set up"
echo "- Optional web dashboard available"
echo ""