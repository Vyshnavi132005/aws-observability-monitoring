# AWS Observability & Monitoring Project

An AWS-based observability and monitoring project using Prometheus, Node Exporter, Grafana, and PagerDuty.

## Architecture

AWS EC2 Instances
        |
        v
  Node Exporter
        |
        v
    Prometheus
        |
        v
     Grafana
        |
        v
 Monitoring & Visualization
        |
        v
    Alert Rules
        |
        v
    PagerDuty

## Technologies

- AWS EC2
- Linux
- Prometheus
- Node Exporter
- Grafana
- PromQL
- PagerDuty

## Project Work

### 1. AWS EC2
Created and configured EC2 instances for the monitoring environment.

### 2. Node Exporter
Installed Node Exporter on monitored EC2 instances to expose system-level metrics such as CPU, memory, disk, and network statistics.

Default endpoint:
`http://<SERVER-IP>:9100/metrics`

### 3. Prometheus
Configured Prometheus to scrape metrics exposed by Node Exporter and collect monitoring data.

### 4. Grafana
Connected Grafana with Prometheus and created dashboards to visualize infrastructure metrics including:

- CPU utilization
- Memory usage
- Disk usage
- Network metrics
- System uptime

### 5. Alerting
Configured monitoring alerts based on infrastructure metrics.

### 6. PagerDuty
Integrated PagerDuty for incident management and tested alert notifications when monitoring conditions were triggered.

## Repository Structure

```text
aws-observability-monitoring/
├── README.md
├── prometheus/
│   └── prometheus.yml
├── grafana/
│   ├── dashboards/
│   └── datasource/
├── node-exporter/
│   └── installation.md
├── alerting/
│   ├── alert-rules.yml
│   └── pagerduty.md
├── scripts/
│   └── installation-commands.sh
└── screenshots/
```

## Note

Do not commit AWS credentials, private SSH keys, API keys, passwords, or other secrets.
