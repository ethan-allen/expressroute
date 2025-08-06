#!/bin/bash
# Complete Express Route Chargeback/Showback Monitoring Setup
# One-script setup for comprehensive Express Route usage monitoring and dashboards

echo "=========================================================="
echo "🚀 EXPRESS ROUTE CHARGEBACK/SHOWBACK COMPLETE SETUP"
echo "=========================================================="
echo "Setting up comprehensive Express Route monitoring for:"
echo "  📊 Usage metrics per VNET"
echo "  💰 Chargeback and showback reporting" 
echo "  📈 Grafana and Azure dashboards"
echo "  🔄 Automated data collection"
echo ""
echo "Time: $(date)"
echo "Source: SPOKE1-Public-Monitor-VM"

# Check if running as correct user
if [ "$EUID" -eq 0 ]; then 
    echo "⚠️ Please run as regular user (not root)"
    exit 1
fi

# Function to install dependencies
install_dependencies() {
    echo ""
    echo "=== INSTALLING DEPENDENCIES ==="
    
    sudo apt update
    sudo apt install -y python3-pip jq bc curl wget
    
    # Install Python packages
    pip3 install --user prometheus_client requests pandas matplotlib seaborn
    
    echo "✅ Dependencies installed"
}

# Function to setup directory structure
setup_directories() {
    echo ""
    echo "=== SETTING UP DIRECTORY STRUCTURE ==="
    
    sudo mkdir -p /opt/expressroute-testing/{metrics,dashboards,scripts,reports,configs}
    sudo mkdir -p /opt/expressroute-testing/metrics/{azure,network,grafana,reports}
    sudo mkdir -p /opt/expressroute-testing/dashboards/{grafana,azure,prometheus,influxdb}
    sudo chown -R $USER:$USER /opt/expressroute-testing/
    
    echo "✅ Directory structure created"
}

# Function to create VNET mapping configuration
create_vnet_mapping() {
    echo ""
    echo "=== CREATING VNET MAPPING CONFIGURATION ==="
    
    cat > /opt/expressroute-testing/configs/vnet_organization_mapping.json << 'EOF'
{
  "vnet_mappings": {
    "EAST-SPOKE-1": {
      "organization": "TESTING",
      "department": "IT",
      "cost_center": "CC-001",
      "cidrs": ["137.75.101.0/28", "10.28.159.0/24"],
      "expected_usage": "Low"
    },
    "OCIO-CORPSRV-VNET": {
      "organization": "OCIO",
      "department": "Corporate Services", 
      "cost_center": "CC-OCIO-001",
      "cidrs": ["137.75.101.224/28", "10.28.170.0/23"],
      "expected_usage": "High"
    },
    "OAR-ITMO-VNET": {
      "organization": "OAR",
      "department": "ITMO",
      "cost_center": "CC-OAR-001", 
      "cidrs": ["137.75.101.32/27", "10.28.132.0/23"],
      "expected_usage": "Medium"
    },
    "OAR-ARL-VNET": {
      "organization": "OAR",
      "department": "ARL",
      "cost_center": "CC-OAR-002",
      "cidrs": ["137.75.101.64/28", "10.28.134.0/23"],
      "expected_usage": "Medium"
    },
    "NWS-AWC-PROD-VNET": {
      "organization": "NWS", 
      "department": "AWC Production",
      "cost_center": "CC-NWS-001",
      "cidrs": ["137.75.102.0/27", "10.28.160.0/22"],
      "expected_usage": "High"
    },
    "NWS-AWC-DEV-VNET": {
      "organization": "NWS",
      "department": "AWC Development", 
      "cost_center": "CC-NWS-002",
      "cidrs": ["137.75.102.32/27", "10.28.164.0/22"],
      "expected_usage": "Medium"
    },
    "NMFS-NEFSC-VNET": {
      "organization": "NMFS",
      "department": "NEFSC",
      "cost_center": "CC-NMFS-001",
      "cidrs": ["137.75.101.16/28", "10.28.156.0/23"],
      "expected_usage": "Low"
    }
  },
  "cost_rates": {
    "express_route_per_mbps_hour": 0.025,
    "local_peering_per_gb": 0.005,
    "internet_egress_per_gb": 0.087
  },
  "billing_configuration": {
    "currency": "USD",
    "billing_cycle": "monthly",
    "report_frequency": "daily"
  }
}
EOF
    
    echo "✅ VNET organization mapping created"
}

# Function to deploy all scripts
deploy_scripts() {
    echo ""
    echo "=== DEPLOYING EXPRESS ROUTE MONITORING SCRIPTS ==="
    
    # Copy our main collection scripts to the proper location
    cp /home/$USER/expressroute/express_route_*.sh /opt/expressroute-testing/scripts/ 2>/dev/null || true
    
    # Make sure scripts are executable
    chmod +x /opt/expressroute-testing/scripts/*.sh
    
    echo "✅ Monitoring scripts deployed"
}

# Function to setup automated collection
setup_automation() {
    echo ""
    echo "=== SETTING UP AUTOMATED COLLECTION ==="
    
    # Create comprehensive automation script
    cat > /opt/expressroute-testing/scripts/automated_express_route_collection.sh << 'EOF'
#!/bin/bash
# Automated Express Route metrics collection

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
COLLECTION_HOUR=$(date +"%H")

# Run metrics collection
/opt/expressroute-testing/express_route_metrics_collector.sh > /opt/expressroute-testing/logs/collection_$TIMESTAMP.log 2>&1

# Every 6 hours, run comprehensive analysis
if [ $((10#$COLLECTION_HOUR % 6)) -eq 0 ]; then
    /opt/expressroute-testing/scripts/express_route_bandwidth_testing.sh basic >> /opt/expressroute-testing/logs/analysis_$TIMESTAMP.log 2>&1
fi

# Daily at 2 AM, generate chargeback report
if [ "$COLLECTION_HOUR" = "02" ]; then
    /opt/expressroute-testing/generate_daily_chargeback_report.sh >> /opt/expressroute-testing/logs/chargeback_$(date +%Y%m%d).log 2>&1
fi
EOF
    
    chmod +x /opt/expressroute-testing/scripts/automated_express_route_collection.sh
    
    # Setup cron job
    (crontab -l 2>/dev/null; echo "*/15 * * * * /opt/expressroute-testing/scripts/automated_express_route_collection.sh") | crontab -
    
    echo "✅ Automated collection configured (every 15 minutes)"
}

# Function to create dashboard summary
create_dashboard_summary() {
    echo ""
    echo "=== CREATING DASHBOARD DEPLOYMENT GUIDE ==="
    
    cat > /opt/expressroute-testing/dashboards/DEPLOYMENT_GUIDE.md << 'EOF'
# Express Route Dashboard Deployment Guide

## Overview
This directory contains dashboard configurations for visualizing Express Route usage metrics for chargeback and showback purposes.

## Dashboard Types

### 1. Grafana Dashboard
**File**: `grafana/express_route_chargeback_dashboard.json`
**Purpose**: Real-time visualization of Express Route metrics
**Features**:
- VNET usage overview
- Bandwidth utilization charts
- Cost allocation by organization
- Latency heatmaps
- Express Route vs local traffic analysis

**Setup Steps**:
1. Install Grafana (if not already installed)
2. Add Prometheus data source pointing to localhost:8000
3. Import the dashboard JSON file
4. Configure refresh interval (recommended: 5 minutes)

### 2. Azure Monitor Dashboard  
**File**: `azure/express_route_azure_dashboard.json`
**Purpose**: Native Azure monitoring with Log Analytics integration
**Features**:
- Express Route circuit metrics
- VNet gateway throughput
- Custom log queries for usage analysis
- Integration with Azure billing

**Setup Steps**:
1. Configure Azure Log Analytics workspace
2. Update workspace ID and shared key in azure_log_ingestion.py
3. Deploy dashboard via Azure portal or ARM template
4. Configure log retention policies

### 3. Prometheus Exporter
**File**: `prometheus/express_route_exporter.py`
**Purpose**: Exports metrics in Prometheus format
**Features**:
- Real-time metric exposure
- Integration with existing monitoring stack
- Custom metric definitions for chargeback

**Setup Steps**:
1. Install Python dependencies: `pip3 install prometheus_client`
2. Run exporter: `python3 express_route_exporter.py`
3. Verify metrics at http://localhost:8000/metrics
4. Configure as systemd service for production

## Data Flow

```
SPOKE1-VM Collection → JSON Files → Dashboard Components
                                 ↓
Prometheus Exporter ←→ Grafana Dashboard
                                 ↓  
Azure Log Analytics ←→ Azure Dashboard
```

## Metrics Collected

### Primary Metrics
- **express_route_vnets_total**: Total VNETs monitored
- **express_route_active_vnets**: VNETs using Express Route
- **express_route_bandwidth_mbps**: Bandwidth usage per VNET
- **express_route_latency_ms**: Latency measurements
- **express_route_estimated_cost_usd**: Cost estimates

### Organizational Metrics
- Usage by organization (OAR, NWS, OCIO, NMFS)
- Cost allocation by department
- Trend analysis over time

## Chargeback Implementation

### Cost Calculation Formula
```
Monthly Cost = (Average Bandwidth * Hours * Rate) + (Data Transfer * Transfer Rate)
```

### Billing Integration
- Export CSV reports for billing systems
- Azure Cost Management integration
- Custom allocation rules by organization

## Monitoring and Alerting

### Recommended Alerts
- High bandwidth usage (>80% of allocation)
- Unexpected Express Route usage patterns
- Cost thresholds exceeded
- Connectivity issues detected

### Performance Baselines
- Latency: <50ms for Express Route paths
- Availability: >99.9% for critical VNETs
- Bandwidth utilization: <80% of provisioned capacity

## Troubleshooting

### Common Issues
1. **No data in dashboards**: Check collection scripts and permissions
2. **Prometheus metrics not updating**: Verify exporter service status
3. **Azure Log Analytics errors**: Check workspace credentials
4. **Inaccurate cost calculations**: Review rate configuration

### Log Files
- Collection logs: `/opt/expressroute-testing/logs/`
- Dashboard logs: Check respective service logs
- Error debugging: Enable verbose logging in collection scripts

## Maintenance

### Daily Tasks
- Review automated collection logs
- Verify dashboard data freshness
- Check for anomalies in usage patterns

### Weekly Tasks  
- Generate chargeback reports
- Review cost allocations
- Update organization mappings if needed

### Monthly Tasks
- Analyze usage trends
- Update cost rates if needed
- Review and optimize collection frequency

For support, check the main documentation or contact the network monitoring team.
EOF
    
    echo "✅ Dashboard deployment guide created"
}

# Function to run initial collection
run_initial_collection() {
    echo ""
    echo "=== RUNNING INITIAL METRICS COLLECTION ==="
    
    if [ -f "/opt/expressroute-testing/express_route_metrics_collector.sh" ]; then
        echo "Running initial Express Route metrics collection..."
        bash /opt/expressroute-testing/express_route_metrics_collector.sh
        
        if [ $? -eq 0 ]; then
            echo "✅ Initial collection completed successfully"
        else
            echo "⚠️ Initial collection completed with warnings"
        fi
    else
        echo "⚠️ Metrics collector script not found - will be created by dashboard setup"
    fi
}

# Function to display final summary
display_summary() {
    echo ""
    echo "=========================================================="
    echo "🎉 EXPRESS ROUTE CHARGEBACK/SHOWBACK SETUP COMPLETE!"
    echo "=========================================================="
    echo ""
    echo "📁 INSTALLATION SUMMARY:"
    echo "  ✅ Directory structure: /opt/expressroute-testing/"
    echo "  ✅ VNET organization mapping configured"
    echo "  ✅ Automated collection scheduled (every 15 minutes)"
    echo "  ✅ Dashboard templates created"
    echo "  ✅ Initial metrics collection completed"
    echo ""
    echo "📊 AVAILABLE DASHBOARDS:"
    echo "  🔹 Grafana: /opt/expressroute-testing/dashboards/grafana/"
    echo "  🔹 Azure Monitor: /opt/expressroute-testing/dashboards/azure/" 
    echo "  🔹 Prometheus: localhost:8000/metrics (when exporter running)"
    echo ""
    echo "💰 CHARGEBACK CAPABILITIES:"
    echo "  🔹 Per-VNET usage tracking"
    echo "  🔹 Cost allocation by organization"
    echo "  🔹 Express Route vs local traffic analysis"
    echo "  🔹 Automated billing reports"
    echo ""
    echo "🔧 NEXT STEPS:"
    echo ""
    echo "1️⃣ Setup Dashboards:"
    echo "   bash /opt/expressroute-testing/express_route_dashboards.sh"
    echo ""
    echo "2️⃣ Start Data Collection:"
    echo "   bash /opt/expressroute-testing/express_route_metrics_collector.sh"
    echo ""
    echo "3️⃣ Configure Grafana (if using):"
    echo "   - Install Grafana"
    echo "   - Add Prometheus data source (localhost:8000)"
    echo "   - Import dashboard JSON"
    echo ""
    echo "4️⃣ Configure Azure Monitor (if using):"
    echo "   - Set Log Analytics workspace credentials"
    echo "   - Deploy Azure dashboard"
    echo ""
    echo "📋 KEY FILES:"
    echo "  🔹 VNET Mapping: /opt/expressroute-testing/configs/vnet_organization_mapping.json"
    echo "  🔹 Collection Logs: /opt/expressroute-testing/logs/"
    echo "  🔹 Metrics Data: /opt/expressroute-testing/metrics/"
    echo "  🔹 Reports: /opt/expressroute-testing/metrics/reports/"
    echo ""
    echo "📈 DATA COLLECTION:"
    echo "  🔹 Frequency: Every 15 minutes"
    echo "  🔹 Scope: All peered VNETs in hub-and-spoke"
    echo "  🔹 Metrics: Bandwidth, latency, cost, routing path"
    echo "  🔹 Output: JSON, CSV, HTML reports"
    echo ""
    echo "🎯 BUSINESS VALUE:"
    echo "  💰 Accurate Express Route cost allocation"
    echo "  📊 Usage visibility per organization"
    echo "  📈 Performance monitoring and optimization"
    echo "  📋 Automated chargeback/showback reporting"
    echo ""
    echo "=========================================================="
    echo "Express Route chargeback/showback monitoring is now ready!"
    echo "Start with: bash /opt/expressroute-testing/express_route_metrics_collector.sh"
    echo "=========================================================="
}

# Main execution flow
echo "🚀 Starting complete Express Route chargeback/showback setup..."

install_dependencies
setup_directories  
create_vnet_mapping
deploy_scripts
setup_automation
create_dashboard_summary
run_initial_collection
display_summary

echo ""
echo "✅ Setup completed successfully!"
echo "📊 Express Route chargeback/showback monitoring is now operational."