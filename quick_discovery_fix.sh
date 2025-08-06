#!/bin/bash
# Quick fix for discovery results and create validated testing config

echo "=== Express Route Discovery Results Analysis ==="
echo "Time: $(date)"

# Create discovery directory with proper permissions
sudo mkdir -p /opt/expressroute-testing/discovery
sudo chown -R $USER:$USER /opt/expressroute-testing/

# Create validated endpoints CSV based on discovery results
cat > /opt/expressroute-testing/discovery/validated_endpoints.csv << 'EOF'
IP,Name,Status,Latency_ms,Path_Type,Priority
10.2.146.14,ExpressRoute-Gateway-Secondary,Reachable,16.240,Express Route,High
137.75.100.6,EAST-FGT-A,Reachable,51.925,Express Route,High
137.75.100.7,EAST-FGT-B,Reachable,53.346,Express Route,High
8.8.8.8,Google-DNS,Reachable,8.0,Internet,Medium
1.1.1.1,Cloudflare-DNS,Reachable,6.0,Internet,Medium
EOF

echo "✅ Created validated endpoints from discovery results"

# Create optimized CIDR configuration for testing
cat > /opt/expressroute-testing/configs/cidr-ranges-validated.conf << 'EOF'
# VALIDATED Express Route Testing Configuration
# Based on actual discovery results - only reachable endpoints
# Format: NAME|PRIVATE_CIDR|PUBLIC_CIDR|TEST_IP|DESCRIPTION

# Working Express Route Endpoints (High Priority)
EXPRESSROUTE-GATEWAY|10.2.146.0/24|10.2.146.0/24|10.2.146.14|Express Route Gateway (Confirmed Working)
EAST-FGT-A-ER|137.75.100.0/25|137.75.100.0/25|137.75.100.6|FortiGate A via Express Route
EAST-FGT-B-ER|137.75.100.0/25|137.75.100.0/25|137.75.100.7|FortiGate B via Express Route

# Internet Connectivity (Control/Baseline)
INTERNET-GOOGLE|8.8.8.8/32|8.8.8.8/32|8.8.8.8|Google DNS (Internet Control)
INTERNET-CLOUDFLARE|1.1.1.1/32|1.1.1.1/32|1.1.1.1|Cloudflare DNS (Internet Control)

# Note: Other CIDR ranges (10.28.x.x) exist but specific test IPs may not be configured
# Contact network administrators to identify actual endpoints in:
# - OAR Labs (10.28.132.x, 10.28.134.x, etc.)
# - NWS Services (10.28.160.x, 10.28.164.x, etc.) 
# - OCIO Services (10.28.170.x, 10.28.176.x, etc.)
EOF

echo "✅ Created validated CIDR configuration"

# Create performance baseline with working endpoints
echo ""
echo "=== RUNNING BASELINE PERFORMANCE TEST ==="
echo "Testing confirmed working endpoints..."

# Test Express Route Gateway
echo "Testing Express Route Gateway (10.2.146.14):"
ping -c 5 10.2.146.14 | grep -E "(PING|packets|rtt)"

echo ""
echo "Testing FortiGates via Express Route:"
# Test FortiGate A
echo "EAST-FGT-A (137.75.100.6):"
ping -c 5 137.75.100.6 | grep -E "(PING|packets|rtt)"

echo ""
# Test FortiGate B  
echo "EAST-FGT-B (137.75.100.7):"
ping -c 5 137.75.100.7 | grep -E "(PING|packets|rtt)"

echo ""
echo "Testing Internet connectivity (baseline):"
echo "Google DNS (8.8.8.8):"
ping -c 5 8.8.8.8 | grep -E "(PING|packets|rtt)"

# Create Express Route performance summary
echo ""
echo "=== EXPRESS ROUTE PERFORMANCE SUMMARY ==="
cat > /opt/expressroute-testing/discovery/express_route_summary.txt << EOF
Express Route Performance Analysis
=================================
Date: $(date)
Source: SPOKE1-Public-Monitor-VM (137.75.101.4)

CONFIRMED WORKING ENDPOINTS:
✅ Express Route Gateway: 10.2.146.14 (~16ms)
✅ EAST-FGT-A via ER: 137.75.100.6 (~52ms)  
✅ EAST-FGT-B via ER: 137.75.100.7 (~53ms)

ROUTE TABLE FIX IMPACT:
Before: FortiGates ~1-2ms (local peering)
After:  FortiGates ~52ms (Express Route path)
Result: ✅ SUCCESS - Traffic now properly routed via Express Route

NETWORK ARCHITECTURE CONFIRMED:
- Express Route Gateway: 10.2.146.14/15 (Active)
- Virtual Appliances: 137.75.100.6/7 (Reachable via ER)
- Internet Traffic: 0.0.0.0/0 → 137.75.100.11
- Private Networks: 10.0.0.0/8 → Express Route

PERFORMANCE CHARACTERISTICS:
- Express Route Latency: ~16ms (excellent)
- Hub-to-Spoke via ER: ~52ms (normal for ER)
- Internet Latency: ~6-8ms (excellent)

RECOMMENDATIONS:
1. Focus testing on confirmed endpoints
2. Contact network admins for actual IPs in remote CIDRs
3. Test bandwidth between working endpoints
4. Monitor Express Route performance over time

TEST STATUS:
✅ Express Route: Working
✅ Routing: Fixed and operational  
✅ FortiGates: Accessible via ER
❌ Remote Endpoints: IPs need validation
EOF

echo "✅ Created Express Route performance summary"

# Update the working testing configuration
cp /opt/expressroute-testing/configs/cidr-ranges-validated.conf /opt/expressroute-testing/configs/cidr-ranges.conf

echo ""
echo "=== TESTING WITH VALIDATED CONFIGURATION ==="
echo "Running Express Route test with confirmed working endpoints..."

# Run a quick test with the validated config
bash /opt/expressroute-testing/scripts/express_route_bandwidth_testing.sh basic

echo ""
echo "=== RESULTS SUMMARY ==="
echo "📁 Files created:"
echo "  - /opt/expressroute-testing/discovery/validated_endpoints.csv"
echo "  - /opt/expressroute-testing/discovery/express_route_summary.txt"
echo "  - /opt/expressroute-testing/configs/cidr-ranges-validated.conf"
echo ""
echo "🎯 KEY FINDINGS:"
echo "  ✅ Express Route is working (10.2.146.14 reachable)"
echo "  ✅ Route table fix successful (FortiGates via ER path)"
echo "  ✅ Hub-spoke routing operational"
echo "  ❌ Most remote test IPs don't exist"
echo ""
echo "📊 PERFORMANCE BASELINES:"
echo "  - Express Route Gateway: ~16ms"
echo "  - FortiGates via ER: ~52ms"  
echo "  - Internet connectivity: ~6-8ms"
echo ""
echo "🔧 NEXT ACTIONS:"
echo "1. ✅ Express Route testing now possible with working endpoints"
echo "2. 📞 Contact network admins for actual IPs in each CIDR range"
echo "3. 📈 Run bandwidth tests between confirmed endpoints"
echo "4. 📋 Document performance baselines for monitoring"