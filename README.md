# AWS Observability & Monitoring

An end-to-end infrastructure monitoring and alerting setup for AWS EC2 using **Node Exporter, Prometheus, Grafana, Alertmanager, and PagerDuty**.

Node Exporter collects system metrics from Linux instances, Prometheus stores them, Grafana visualizes them, and Alertmanager routes alerts to PagerDuty, which creates incidents for the on-call engineer.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [Technologies Used](#3-technologies-used)
4. [AWS Infrastructure](#4-aws-infrastructure)
5. [Ports](#5-ports)
6. [Installation](#6-installation)
   - [Node Exporter](#61-node-exporter)
   - [Prometheus](#62-prometheus)
   - [Grafana](#63-grafana)
   - [Alertmanager](#64-alertmanager)
7. [Configuration](#7-configuration)
8. [PromQL Queries](#8-promql-queries)
9. [Grafana Dashboard](#9-grafana-dashboard)
10. [Alert Rules](#10-alert-rules)
11. [Alertmanager](#11-alertmanager)
12. [PagerDuty](#12-pagerduty)
13. [Testing](#13-testing)
14. [Troubleshooting](#14-troubleshooting)
15. [Security](#15-security)
16. [Project Structure](#16-project-structure)
17. [Screenshots](#17-screenshots)
18. [Learning Outcomes](#18-learning-outcomes)
19. [Future Improvements](#19-future-improvements)
20. [Push to GitHub](#20-push-to-github)
21. [Author](#21-author)

---

## 1. Project Overview

This project builds a complete monitoring and alerting pipeline on AWS EC2 instances running Linux. Each component runs as a `systemd` service, so everything starts automatically after a reboot.

**What it does:**

- Collects system metrics from EC2 instances with **Node Exporter**
- Scrapes and stores metrics with **Prometheus**
- Visualizes metrics in **Grafana** dashboards
- Evaluates **alert rules** (high CPU, memory, disk, instance down) in Prometheus
- Routes alerts through **Alertmanager** to **PagerDuty**
- Creates (and automatically resolves) **PagerDuty incidents**

**Metrics monitored:**

| Category | Examples |
|----------|----------|
| CPU | CPU utilization |
| Memory | Memory utilization |
| Disk | Disk usage, filesystem usage |
| Network | Receive and transmit traffic |
| System | System load, uptime |
| Availability | Instance up/down status |

---

## 2. Architecture

### Monitoring flow

```text
AWS EC2
   ↓
Node Exporter   (exposes metrics on :9100)
   ↓
Prometheus      (scrapes and stores metrics on :9090)
   ↓
Grafana         (dashboards on :3000)
```

### Alerting flow

```text
Prometheus Alert Rules
   ↓
Alertmanager    (:9093)
   ↓
PagerDuty
   ↓
Incident
```

### Full picture

```text
┌─────────────────────┐        scrape :9100        ┌─────────────────────────────────┐
│  Target EC2         │ ◄───────────────────────── │  Monitoring EC2                 │
│  - Node Exporter    │                            │  - Prometheus    :9090          │
└─────────────────────┘                            │  - Grafana       :3000          │
                                                   │  - Alertmanager  :9093          │
                                                   └───────────────┬─────────────────┘
                                                                   │ HTTPS (Events API v2)
                                                                   ▼
                                                           ┌───────────────┐
                                                           │   PagerDuty   │ → Incident → On-call engineer
                                                           └───────────────┘
```

> **Note:** For a small lab you can run everything on a single EC2 instance (Node Exporter will then scrape `localhost:9100`). For a more realistic setup, use one monitoring server and one or more target instances.

---

## 3. Technologies Used

| Technology | Purpose |
|------------|---------|
| AWS EC2 | Hosts the monitoring stack and monitored servers |
| Linux (Ubuntu) | Operating system |
| SSH | Remote access to instances |
| Security Groups | Network access control |
| Node Exporter 1.8.2 | Exposes Linux system metrics |
| Prometheus 2.55.1 | Metrics collection, storage, and alert evaluation |
| PromQL | Query language for Prometheus |
| Grafana | Dashboards and visualization |
| Alertmanager 0.27.0 | Alert grouping, deduplication, and routing |
| PagerDuty | Incident management and on-call notification |
| Bash | Installation scripts |
| Git & GitHub | Version control and portfolio hosting |

---

## 4. AWS Infrastructure

**Suggested lab setup:**

| Resource | Recommended value |
|----------|-------------------|
| Instance type | `t2.micro` / `t3.micro` (Free Tier) for testing, `t3.small` or larger if you notice slowness |
| OS | Ubuntu Server 22.04 LTS |
| Storage | 20 GB gp3 |
| Number of instances | 1 (all-in-one) or 2+ (monitoring server + targets) |
| Key pair | Your own `.pem` key (never commit it) |

**Security Group inbound rules:**

| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 22 | TCP | Your IP only (`<YOUR-IP>/32`) | SSH |
| 9100 | TCP | Monitoring server IP / its Security Group | Node Exporter |
| 9090 | TCP | Your IP only | Prometheus UI |
| 3000 | TCP | Your IP only | Grafana UI |
| 9093 | TCP | Your IP only | Alertmanager UI |

> Avoid `0.0.0.0/0` for these ports. Restrict them to your own IP address. Monitoring ports should never be open to the whole internet.

**Connect to an instance:**

```bash
chmod 400 <YOUR-KEY>.pem
ssh -i <YOUR-KEY>.pem ubuntu@<EC2-IP>
```

---

## 5. Ports

| Service | Port | Used on |
|---------|------|---------|
| SSH | 22 | All instances |
| Node Exporter | 9100 | Target instances |
| Prometheus | 9090 | Monitoring server |
| Grafana | 3000 | Monitoring server |
| Alertmanager | 9093 | Monitoring server |

---

## 6. Installation

Placeholders used throughout this README:

| Placeholder | Meaning |
|-------------|---------|
| `<EC2-IP>` | Public/private IP of an EC2 instance |
| `<NODE-EXPORTER-IP>` | IP of the instance running Node Exporter |
| `<PROMETHEUS-IP>` | IP of the instance running Prometheus |
| `<GRAFANA-IP>` | IP of the instance running Grafana |
| `<PAGERDUTY_ROUTING_KEY>` | PagerDuty integration key (keep it secret) |

> Within the same VPC, prefer **private IPs** for Prometheus → Node Exporter scraping.

### 6.1 Node Exporter

Run on **every instance you want to monitor**.

**1. Download Node Exporter**

```bash
cd /tmp
wget https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
```

**2. Extract it**

```bash
tar xvf node_exporter-1.8.2.linux-amd64.tar.gz
```

**3. Move the binary**

```bash
sudo mv node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/
sudo useradd --no-create-home --shell /bin/false node_exporter
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter
```

**4. Create the systemd service**

```bash
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<'EOF'
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
```

**5. Enable the service**

```bash
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
```

**6. Start the service**

```bash
sudo systemctl start node_exporter
```

**7. Check service status**

```bash
sudo systemctl status node_exporter
```

**8. Test `/metrics`**

```bash
curl http://localhost:9100/metrics | head -20
curl -s http://localhost:9100/metrics | grep node_cpu_seconds_total | head
```

From another machine (needs port 9100 open in the Security Group):

```bash
curl http://<NODE-EXPORTER-IP>:9100/metrics | head
```

---

### 6.2 Prometheus

Run on the **monitoring server**.

**1. Download Prometheus**

```bash
cd /tmp
wget https://github.com/prometheus/prometheus/releases/download/v2.55.1/prometheus-2.55.1.linux-amd64.tar.gz
```

**2. Extract it**

```bash
tar xvf prometheus-2.55.1.linux-amd64.tar.gz
```

**3. Create user, directories, and install binaries**

```bash
sudo useradd --no-create-home --shell /bin/false prometheus

sudo mkdir -p /etc/prometheus /var/lib/prometheus

sudo cp prometheus-2.55.1.linux-amd64/prometheus /usr/local/bin/
sudo cp prometheus-2.55.1.linux-amd64/promtool /usr/local/bin/

sudo chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool
sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
```

**4. Create `prometheus.yml`** (see the full example in [Configuration](#7-configuration))

```bash
sudo nano /etc/prometheus/prometheus.yml
```

**5. Create the Prometheus systemd service**

```bash
sudo tee /etc/systemd/system/prometheus.service > /dev/null <<'EOF'
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus/ \
  --storage.tsdb.retention.time=15d \
  --web.listen-address=0.0.0.0:9090
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
```

**6. Test the configuration with promtool**

```bash
promtool check config /etc/prometheus/prometheus.yml
```

**7. Start and enable Prometheus**

```bash
sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl start prometheus
```

**8. Check Prometheus status**

```bash
sudo systemctl status prometheus
curl http://localhost:9090/-/healthy
```

**9. Check Targets**

Open in your browser:

```text
http://<PROMETHEUS-IP>:9090/targets
```

The `node_exporter` target should show **UP**.

---

### 6.3 Grafana

Run on the **monitoring server** (Ubuntu / Debian).

**1. Install Grafana**

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https software-properties-common wget gnupg

sudo mkdir -p /etc/apt/keyrings
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null

echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list

sudo apt-get update
sudo apt-get install -y grafana
```

> On Amazon Linux / RHEL, add the Grafana YUM repository from the official Grafana docs and install with `sudo yum install grafana`.

**2. Start, enable, and check Grafana**

```bash
sudo systemctl daemon-reload
sudo systemctl start grafana-server
sudo systemctl enable grafana-server
sudo systemctl status grafana-server
```

**3. Open Grafana on port 3000**

```text
http://<GRAFANA-IP>:3000
```

Default login is `admin` / `admin`. Grafana will ask you to set a new password on first login. Use a strong one and do not commit it anywhere.

---

### 6.4 Alertmanager

Run on the **monitoring server**.

**1. Download Alertmanager**

```bash
cd /tmp
wget https://github.com/prometheus/alertmanager/releases/download/v0.27.0/alertmanager-0.27.0.linux-amd64.tar.gz
```

**2. Extract it**

```bash
tar xvf alertmanager-0.27.0.linux-amd64.tar.gz
```

**3. Create user, configuration directories, and install binaries**

```bash
sudo useradd --no-create-home --shell /bin/false alertmanager

sudo mkdir -p /etc/alertmanager /var/lib/alertmanager

sudo cp alertmanager-0.27.0.linux-amd64/alertmanager /usr/local/bin/
sudo cp alertmanager-0.27.0.linux-amd64/amtool /usr/local/bin/

sudo chown alertmanager:alertmanager /usr/local/bin/alertmanager /usr/local/bin/amtool
sudo chown -R alertmanager:alertmanager /etc/alertmanager /var/lib/alertmanager
```

**4. Create `alertmanager.yml`** (full example in [Alertmanager](#11-alertmanager))

```bash
sudo nano /etc/alertmanager/alertmanager.yml
sudo chown alertmanager:alertmanager /etc/alertmanager/alertmanager.yml
sudo chmod 640 /etc/alertmanager/alertmanager.yml
```

**5. Create the systemd service**

```bash
sudo tee /etc/systemd/system/alertmanager.service > /dev/null <<'EOF'
[Unit]
Description=Alertmanager
Wants=network-online.target
After=network-online.target

[Service]
User=alertmanager
Group=alertmanager
Type=simple
ExecStart=/usr/local/bin/alertmanager \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=/var/lib/alertmanager \
  --web.listen-address=0.0.0.0:9093
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
```

**6. Validate, start, and enable Alertmanager**

```bash
amtool check-config /etc/alertmanager/alertmanager.yml

sudo systemctl daemon-reload
sudo systemctl start alertmanager
sudo systemctl enable alertmanager
```

**7. Check Alertmanager status**

```bash
sudo systemctl status alertmanager
curl http://localhost:9093/-/healthy
```

Web UI: `http://<PROMETHEUS-IP>:9093`

**8. Connect Prometheus to Alertmanager**

This is done in `prometheus.yml` under the `alerting:` block (shown in the next section).

---

## 7. Configuration

### Complete `prometheus.yml`

File: `/etc/prometheus/prometheus.yml` (also saved as `prometheus/prometheus.yml` in this repo)

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

# Connect Prometheus to Alertmanager
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - "localhost:9093"

# Load alert rules
rule_files:
  - "/etc/prometheus/alert-rules.yml"

scrape_configs:
  # Prometheus monitors itself
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  # Node Exporter targets (add one entry per EC2 instance)
  - job_name: "node_exporter"
    static_configs:
      - targets:
          - "<NODE-EXPORTER-IP>:9100"
          # - "<ANOTHER-EC2-IP>:9100"
        labels:
          environment: "dev"
```

If Node Exporter runs on the same server as Prometheus, use `localhost:9100`.

Validate and reload:

```bash
promtool check config /etc/prometheus/prometheus.yml
sudo systemctl restart prometheus
```

---

## 8. PromQL Queries

Run these in the Prometheus UI (`http://<PROMETHEUS-IP>:9090/graph`) or use them as Grafana panel queries.

| Metric | PromQL query |
|--------|--------------|
| **CPU usage (%)** | `100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` |
| **Memory usage (%)** | `(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100` |
| **Disk usage (%)** | `(1 - (node_filesystem_avail_bytes{mountpoint="/",fstype!="rootfs"} / node_filesystem_size_bytes{mountpoint="/",fstype!="rootfs"})) * 100` |
| **Network receive (bytes/s)** | `rate(node_network_receive_bytes_total{device!="lo"}[5m])` |
| **Network transmit (bytes/s)** | `rate(node_network_transmit_bytes_total{device!="lo"}[5m])` |
| **System load (1 min)** | `node_load1` |
| **System load (5 min)** | `node_load5` |
| **Uptime (seconds)** | `time() - node_boot_time_seconds` |
| **Uptime (days)** | `(time() - node_boot_time_seconds) / 86400` |
| **Instance availability** | `up{job="node_exporter"}` (1 = up, 0 = down) |

---

## 9. Grafana Dashboard

### Add Prometheus as a datasource

1. Open `http://<GRAFANA-IP>:3000` and log in.
2. Go to **Connections → Data sources → Add data source**.
3. Select **Prometheus**.
4. Set **URL** to `http://localhost:9090` (or `http://<PROMETHEUS-IP>:9090` if Grafana is on a different server).
5. Click **Save & test**. You should see *"Successfully queried the Prometheus API"*.

### Create a monitoring dashboard

1. Go to **Dashboards → New → New dashboard → Add visualization**.
2. Select the Prometheus datasource.
3. Paste a query from the [PromQL Queries](#8-promql-queries) section.
4. Choose a visualization type and set the title and unit.
5. Repeat for each panel, then click **Save dashboard**.

**Suggested panels:**

| Panel | Visualization | Unit | Query |
|-------|---------------|------|-------|
| CPU Usage | Time series / Gauge | Percent (0-100) | CPU query |
| Memory Usage | Time series / Gauge | Percent (0-100) | Memory query |
| Disk Usage | Gauge | Percent (0-100) | Disk query |
| Network Receive | Time series | bytes/sec | Network receive query |
| Network Transmit | Time series | bytes/sec | Network transmit query |
| System Load | Time series | none | `node_load1`, `node_load5` |
| Uptime | Stat | seconds (s) | Uptime query |
| Instance Status | Stat | none | `up{job="node_exporter"}` |

### Import a ready-made dashboard (optional)

The community dashboard **Node Exporter Full** (ID `1860`) works well:

1. **Dashboards → New → Import**
2. Enter ID `1860` and click **Load**
3. Select your Prometheus datasource and click **Import**

To keep your own dashboard in this repo: open the dashboard → **Share → Export → Save to file**, and save it as `grafana/dashboards/dashboard.json`.

---

## 10. Alert Rules

### What is an alert rule?

An alert rule is a PromQL expression that Prometheus evaluates regularly. If the expression stays true for the time set in `for:`, the alert moves from **pending** to **firing** and is sent to Alertmanager.

### Create `alert-rules.yml`

```bash
sudo nano /etc/prometheus/alert-rules.yml
```

```yaml
groups:
  - name: node-alerts
    rules:
      # High CPU usage
      - alert: HighCPUUsage
        expr: 100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          description: "CPU usage is above 80% (current value: {{ $value | printf \"%.1f\" }}%) for more than 2 minutes."

      # High memory usage
      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          description: "Memory usage is above 80% (current value: {{ $value | printf \"%.1f\" }}%) for more than 5 minutes."

      # High disk usage
      - alert: HighDiskUsage
        expr: (1 - (node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs|rootfs"} / node_filesystem_size_bytes{fstype!~"tmpfs|overlay|squashfs|rootfs"})) * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High disk usage on {{ $labels.instance }} ({{ $labels.mountpoint }})"
          description: "Disk usage is above 80% (current value: {{ $value | printf \"%.1f\" }}%)."

      # Instance down
      - alert: InstanceDown
        expr: up{job="node_exporter"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Instance {{ $labels.instance }} is down"
          description: "Prometheus has not been able to scrape {{ $labels.instance }} for more than 1 minute."
```

Set the ownership:

```bash
sudo chown prometheus:prometheus /etc/prometheus/alert-rules.yml
```

### Connect the rules to Prometheus

In `prometheus.yml`:

```yaml
rule_files:
  - "/etc/prometheus/alert-rules.yml"
```

### Validate the rules

```bash
promtool check rules /etc/prometheus/alert-rules.yml
promtool check config /etc/prometheus/prometheus.yml
```

Expected output: `SUCCESS`.

### Restart Prometheus

```bash
sudo systemctl restart prometheus
sudo systemctl status prometheus
```

Check the rules in the UI: `http://<PROMETHEUS-IP>:9090/alerts`

| Alert state | Meaning |
|-------------|---------|
| Inactive | Condition is false |
| Pending | Condition is true, waiting for the `for:` duration |
| Firing | Condition held long enough; alert sent to Alertmanager |

---

## 11. Alertmanager

### Complete `alertmanager.yml`

File: `/etc/alertmanager/alertmanager.yml` (template saved as `alerting/alertmanager.yml` in this repo, with a **placeholder** key only)

```yaml
global:
  resolve_timeout: 5m

route:
  receiver: "pagerduty"
  group_by: ["alertname", "instance"]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h

receivers:
  - name: "pagerduty"
    pagerduty_configs:
      - routing_key: "<PAGERDUTY_ROUTING_KEY>"
        send_resolved: true
        description: "{{ .CommonAnnotations.summary }}"
        severity: "{{ if .CommonLabels.severity }}{{ .CommonLabels.severity }}{{ else }}warning{{ end }}"
        details:
          alertname: "{{ .CommonLabels.alertname }}"
          instance: "{{ .CommonLabels.instance }}"
          description: "{{ .CommonAnnotations.description }}"

inhibit_rules:
  # If an instance is down, don't also page for its other alerts
  - source_match:
      alertname: "InstanceDown"
    target_match_re:
      alertname: "HighCPUUsage|HighMemoryUsage|HighDiskUsage"
    equal: ["instance"]
```

> The real key goes **only** on the server, never in Git. For extra safety, Alertmanager also supports `routing_key_file: /etc/alertmanager/pagerduty_key` so the key lives in a separate file (`chmod 600`, owned by `alertmanager`).

### Apply changes

```bash
amtool check-config /etc/alertmanager/alertmanager.yml
sudo systemctl restart alertmanager
sudo systemctl status alertmanager
```

### Verify Prometheus is connected to Alertmanager

```bash
curl -s http://localhost:9090/api/v1/alertmanagers
```

The response should list `http://localhost:9093/api/v2/alerts` under `activeAlertmanagers`. You can also check **Status → Runtime & Build Information** in the Prometheus UI.

---

## 12. PagerDuty

### 1. Create a PagerDuty service

1. Log in to PagerDuty (a free trial account is enough).
2. Go to **Services → Service Directory → + New Service**.
3. Enter a name, for example `AWS Observability Monitoring`.
4. Choose an **Escalation Policy** (the default is fine for testing).
5. Set alert grouping as required (or leave the default).

### 2. Configure the Prometheus integration

1. In the **Integrations** step, search for **Prometheus** and select it.
2. Click **Create Service**.

If you already created the service: **Services → your service → Integrations → + Add an integration → Prometheus**.

### 3. Obtain the routing / integration key

1. Open your service → **Integrations** tab.
2. Find the **Prometheus** integration.
3. Copy the **Integration Key** (a 32-character key for Events API v2).

This is your `<PAGERDUTY_ROUTING_KEY>`. Treat it like a password.

### 4. Configure Alertmanager

Put the key into the config **on the server only**:

```bash
sudo nano /etc/alertmanager/alertmanager.yml
```

```yaml
routing_key: "<PAGERDUTY_ROUTING_KEY>"   # replace with your real key on the server
```

Validate and restart:

```bash
amtool check-config /etc/alertmanager/alertmanager.yml
sudo systemctl restart alertmanager
```

### 5. Send Prometheus alerts to PagerDuty

The route in `alertmanager.yml` already sends all alerts to the `pagerduty` receiver. The flow is:

```text
Prometheus alert rule fires
        ↓
Alertmanager receives and groups the alert
        ↓
Alertmanager calls the PagerDuty Events API v2
        ↓
PagerDuty creates an incident
```

To check that Alertmanager received the alert:

```bash
amtool alert query --alertmanager.url=http://localhost:9093
```

### 6. Verify an incident is created

1. Trigger an alert (see the [CPU test](#cpu-alert-test-using-stress)).
2. Wait for the alert to go **Pending → Firing** in Prometheus (`/alerts`).
3. Alertmanager waits `group_wait` (30s) before sending.
4. In PagerDuty open **Incidents**. A new **Triggered** incident for `HighCPUUsage` should appear.

### 7. Resolve the alert and verify the incident resolves

1. Stop the load test (for example `pkill stress`).
2. CPU drops below 80% and the alert resolves in Prometheus.
3. Alertmanager sends a resolved notification (`send_resolved: true`).
4. In PagerDuty the incident status changes to **Resolved**.

> Resolution can take a few minutes because of the 5m rate window and the Alertmanager timing settings.

---

## 13. Testing

### Test 1: Node Exporter

```bash
sudo systemctl status node_exporter
curl -s http://localhost:9100/metrics | grep -E "node_load1|node_memory_MemTotal_bytes"
```

Expected: metric lines with values are returned.

### Test 2: Prometheus target

```bash
curl -s http://localhost:9090/api/v1/targets | grep -o '"health":"[a-z]*"'
```

Or open `http://<PROMETHEUS-IP>:9090/targets`. Expected: `node_exporter` is **UP**.

### Test 3: PromQL

In the Prometheus UI run:

```promql
up
node_load1
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

Expected: `up` returns `1` for every target, and the other queries return values.

### Test 4: Grafana

```bash
sudo systemctl status grafana-server
curl -s http://localhost:3000/api/health
```

Open `http://<GRAFANA-IP>:3000`, check the datasource (**Save & test**), and confirm dashboard panels show data.

### Test 5: Alertmanager

```bash
sudo systemctl status alertmanager
curl http://localhost:9093/-/healthy
```

Send a manual test alert straight to Alertmanager:

```bash
curl -X POST http://localhost:9093/api/v2/alerts \
  -H "Content-Type: application/json" \
  -d '[
    {
      "labels": { "alertname": "ManualTestAlert", "severity": "warning", "instance": "test-instance" },
      "annotations": { "summary": "Manual test alert", "description": "Testing Alertmanager to PagerDuty" }
    }
  ]'
```

Check it in the UI at `http://<PROMETHEUS-IP>:9093` or with:

```bash
amtool alert query --alertmanager.url=http://localhost:9093
```

### Test 6: PagerDuty

The manual test alert above will also be forwarded to PagerDuty. After about 30 seconds an incident named *Manual test alert* should appear under **Incidents**. Resolve it manually in PagerDuty when done.

### CPU alert test using `stress`

Install the tool (Ubuntu):

```bash
sudo apt-get install -y stress
```

Generate CPU load on the instance being monitored. This runs one worker per CPU core and **stops automatically after 10 minutes**:

```bash
stress --cpu $(nproc) --timeout 600
```

Watch the alert progress:

```text
Prometheus  →  http://<PROMETHEUS-IP>:9090/alerts   (Inactive → Pending → Firing)
Alertmanager → http://<PROMETHEUS-IP>:9093          (alert appears)
PagerDuty   →  Incidents page                       (incident Triggered)
```

**How to stop the test:**

```bash
# Press Ctrl+C in the terminal running stress, or from another terminal:
pkill stress

# Confirm nothing is still running:
pgrep stress || echo "stress is stopped"
```

> Always use `--timeout` so the test cannot run forever. On burstable instances (`t2` / `t3`) sustained load can use up CPU credits, so keep the test short.

### Expected alert flow

```text
EC2
 → Node Exporter
 → Prometheus
 → Alert Rule
 → Alertmanager
 → PagerDuty
 → Incident
```

---

## 14. Troubleshooting

### Node Exporter target is DOWN

| Check | Command / action |
|-------|------------------|
| Is the service running? | `sudo systemctl status node_exporter` |
| Is it listening? | `sudo ss -tulnp \| grep 9100` |
| Does it respond locally? | `curl http://localhost:9100/metrics` |
| Is the target IP/port right? | Check `targets:` in `/etc/prometheus/prometheus.yml` |
| Is the port open? | Check the Security Group inbound rule for 9100 |

### Prometheus cannot scrape Node Exporter

```bash
# From the Prometheus server
curl -v http://<NODE-EXPORTER-IP>:9100/metrics
```

- `Connection timed out` → Security Group or network ACL is blocking port 9100. Allow it from the Prometheus server's IP or Security Group.
- `Connection refused` → Node Exporter is not running or is bound to a different address.
- Use **private IPs** inside the same VPC.
- Check the error message shown beside the target at `http://<PROMETHEUS-IP>:9090/targets`.

### Grafana cannot connect to Prometheus

- Make sure Prometheus is running: `curl http://localhost:9090/-/healthy`
- Use the correct URL in the datasource: `http://localhost:9090` when on the same server, otherwise `http://<PROMETHEUS-IP>:9090`.
- If Grafana is on another server, port 9090 must be open to it in the Security Group.
- Check Grafana logs: `sudo journalctl -u grafana-server -n 50 --no-pager`

### Alertmanager not receiving alerts

- Confirm `alerting:` and `rule_files:` exist in `prometheus.yml`.
- Validate: `promtool check config /etc/prometheus/prometheus.yml` and `promtool check rules /etc/prometheus/alert-rules.yml`.
- Make sure the alert is actually **Firing**, not only Pending (`http://<PROMETHEUS-IP>:9090/alerts`).
- Check Prometheus knows the Alertmanager: `curl -s http://localhost:9090/api/v1/alertmanagers`
- Check that Alertmanager is up: `sudo systemctl status alertmanager`
- Restart Prometheus after any config change: `sudo systemctl restart prometheus`

### PagerDuty incident not being created

- Check the routing key is correct and has no extra spaces or quotes.
- Make sure the integration type is **Prometheus** (Events API v2).
- Look at Alertmanager logs for notification errors:

  ```bash
  sudo journalctl -u alertmanager -n 100 --no-pager | grep -i -E "pagerduty|error|notify"
  ```

- The server needs outbound internet access to `events.pagerduty.com` (HTTPS 443). Check:

  ```bash
  curl -I https://events.pagerduty.com
  ```

- Validate the config: `amtool check-config /etc/alertmanager/alertmanager.yml`
- Check the `route:` actually points to the `pagerduty` receiver.
- Alertmanager waits `group_wait` (30s) before the first notification, so wait a short time.

### Security Group / port issues

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Cannot open Grafana/Prometheus in browser | Port not open, or your IP changed | Update the inbound rule with your current IP |
| Prometheus can't reach Node Exporter | Port 9100 not open to the Prometheus server | Add an inbound rule for 9100 |
| SSH timeout | Port 22 not open to your IP | Update the SSH rule |
| Works on public IP but not private | Wrong source in the rule | Reference the Security Group or VPC CIDR |

Check the ports from your own machine:

```bash
nc -zv <EC2-IP> 9090
nc -zv <EC2-IP> 3000
```

### systemd service failures

```bash
# Status and recent logs
sudo systemctl status <service-name>
sudo journalctl -u <service-name> -n 50 --no-pager

# After editing a .service file
sudo systemctl daemon-reload
sudo systemctl restart <service-name>
```

Common causes:

| Error | Fix |
|-------|-----|
| `status=203/EXEC` | Wrong binary path or the file is not executable (`chmod +x`) |
| `status=217/USER` | The service user does not exist (`useradd ...`) |
| `permission denied` on data directory | `sudo chown -R prometheus:prometheus /var/lib/prometheus` |
| YAML errors | Run `promtool check config` / `amtool check-config` |
| `address already in use` | Another process uses the port: `sudo ss -tulnp \| grep <port>` |

---

## 15. Security

**Never commit any of the following to GitHub:**

- `.pem` / `.ppk` key files
- AWS access keys
- AWS secret keys
- PagerDuty routing / integration keys
- Passwords (Grafana admin password, etc.)
- API tokens
- Any other credentials

**Best practices:**

- Use placeholders such as `<PAGERDUTY_ROUTING_KEY>` in the repository. Put real values only on the server.
- Restrict Security Group rules to your own IP. Never open 9090, 9093, 9100, or 3000 to `0.0.0.0/0`.
- Change the default Grafana password on first login.
- Use an IAM role for EC2 instead of storing AWS keys on the instance.
- Set `chmod 400` on your `.pem` file.
- If a secret is accidentally committed, **revoke or rotate it immediately** (generate a new PagerDuty key, deactivate AWS keys). Deleting the file in a later commit is not enough because Git history keeps it.

### Example `.gitignore`

```gitignore
# Keys and certificates
*.pem
*.ppk
*.key
*.crt

# Environment and secrets
.env
.env.*
*.env
secrets/
*.secret
credentials
credentials.json

# AWS
.aws/
aws_credentials*

# Local config containing real keys
alertmanager.local.yml
alertmanager-prod.yml
pagerduty_key

# Terraform (if added later)
*.tfstate
*.tfstate.*
.terraform/

# OS / editor files
.DS_Store
Thumbs.db
.vscode/
.idea/
*.swp
```

---

## 16. Project Structure

```text
aws-observability-monitoring/
├── README.md
├── prometheus/
│   ├── prometheus.yml
│   └── alert-rules.yml
├── node-exporter/
│   └── installation.md
├── grafana/
│   ├── dashboards/
│   │   └── dashboard.json
│   └── datasource/
│       └── prometheus.md
├── alerting/
│   ├── alert-rules.yml
│   ├── alertmanager.yml
│   └── pagerduty.md
├── scripts/
│   └── installation-commands.sh
└── screenshots/
```

| Path | Description |
|------|-------------|
| `prometheus/prometheus.yml` | Prometheus config with scrape targets and Alertmanager connection |
| `prometheus/alert-rules.yml` | Alert rules loaded by Prometheus |
| `node-exporter/installation.md` | Node Exporter install steps |
| `grafana/dashboards/dashboard.json` | Exported Grafana dashboard |
| `grafana/datasource/prometheus.md` | Steps to add the Prometheus datasource |
| `alerting/alert-rules.yml` | Copy of the alert rules for the alerting section |
| `alerting/alertmanager.yml` | Alertmanager config (placeholder key only) |
| `alerting/pagerduty.md` | PagerDuty setup notes |
| `scripts/installation-commands.sh` | Bash script collecting the install commands |
| `screenshots/` | Proof-of-work screenshots |

---

## 17. Screenshots

Add screenshots to the `screenshots/` folder. These make the project much stronger as a portfolio piece.

| # | Screenshot | What to capture |
|---|-----------|-----------------|
| 1 | EC2 | Instances list showing the monitoring server and targets |
| 2 | Security Group | Inbound rules (blur or crop your IP if you like) |
| 3 | Node Exporter metrics | Browser or terminal showing `/metrics` output |
| 4 | Prometheus Targets | Targets page with `node_exporter` **UP** |
| 5 | Prometheus queries | Graph page with a PromQL query (for example CPU usage) |
| 6 | Grafana dashboard | Dashboard with CPU, memory, disk, and network panels |
| 7 | Alertmanager | Alertmanager UI with a firing alert |
| 8 | PagerDuty incident | Incident page showing Triggered and later Resolved |

Embed them in this README like this:

```markdown
![Prometheus Targets](screenshots/prometheus-targets.png)
![Grafana Dashboard](screenshots/grafana-dashboard.png)
```

> Before taking screenshots, make sure no routing keys, passwords, or full account details are visible.

---

## 18. Learning Outcomes

- Launched and secured EC2 instances using Security Groups and SSH key authentication
- Installed and ran services on Linux as `systemd` units
- Exposed and scraped system metrics with Node Exporter and Prometheus
- Wrote PromQL queries for CPU, memory, disk, network, load, and uptime
- Built Grafana dashboards backed by a Prometheus datasource
- Wrote and validated Prometheus alert rules with `promtool`
- Configured Alertmanager routing and grouping
- Integrated Alertmanager with PagerDuty and verified the incident lifecycle
- Debugged real-world issues: closed ports, failing services, and bad configs
- Practised secure handling of secrets and repository hygiene with Git and GitHub

---

## 19. Future Improvements

- Provision the infrastructure with **Terraform** or **CloudFormation**
- Use **EC2 service discovery** (`ec2_sd_configs`) instead of static targets
- Add **HTTPS** and authentication using Nginx as a reverse proxy
- Add **Blackbox Exporter** for website and endpoint monitoring
- Add Slack or email as extra Alertmanager receivers
- Run the stack with **Docker Compose**
- Monitor containers with **cAdvisor** and Kubernetes with **kube-prometheus-stack**
- Store Grafana dashboards and datasources as provisioning files
- Add Prometheus long-term storage (for example Thanos or Amazon Managed Service for Prometheus)
- Add a CI pipeline to run `promtool check` on every commit

---

## 20. Push to GitHub

Run these commands from the project folder:

```bash
git init
git add .
git commit -m "Add AWS observability and monitoring project"
git branch -M main
git remote add origin https://github.com/Vyshnavi132005/aws-observability-monitoring.git
git push -u origin main
```

Before `git add .`, double-check nothing sensitive is staged:

```bash
git status
grep -rniE "routing_key: *\"?[A-Za-z0-9]{32}|AKIA[0-9A-Z]{16}|BEGIN (RSA|OPENSSH) PRIVATE KEY" . || echo "No obvious secrets found"
```

Updating the repository later:

```bash
git add .
git commit -m "Update documentation"
git push
```

---

## 21. Author

**Vyshnavi Srikakulam**

- GitHub: [https://github.com/Vyshnavi132005](https://github.com/Vyshnavi132005)
- LinkedIn: [https://www.linkedin.com/in/vyshnavi-srikakulam/](https://www.linkedin.com/in/vyshnavi-srikakulam/)

---

If this project helped you, consider giving the repository a star.
