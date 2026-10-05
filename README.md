# 📊 AWS Observability & Monitoring Project

## 📌 Project Overview

This project demonstrates an end-to-end **AWS infrastructure observability and monitoring solution** using **Amazon EC2, Node Exporter, Prometheus, Grafana, and PagerDuty**.

The main goal of this project is to monitor EC2 server performance, collect infrastructure metrics, visualize those metrics through Grafana dashboards, configure alerts, and send incidents to PagerDuty.

The monitoring solution provides visibility into important system resources such as:

- CPU utilization
- Memory utilization
- Disk usage
- Network traffic
- Filesystem usage
- System uptime
- Server health

---

# 🏗️ Architecture

```text
                         AWS Cloud
                            │
             ┌──────────────┴──────────────┐
             │                             │
             ▼                             ▼
       EC2 Node Server              EC2 Node Server
             │                             │
             │                             │
      Node Exporter                 Node Exporter
          :9100                         :9100
             │                             │
             └──────────────┬──────────────┘
                            │
                            ▼
                       Prometheus
                          :9090
                            │
                  ┌─────────┴─────────┐
                  │                   │
                  ▼                   ▼
               Grafana           Alert Rules
                :3000                 │
                  │                   ▼
                  │              Alertmanager
                  │                   │
                  │                   ▼
                  │               PagerDuty
                  │                   │
                  │                   ▼
                  │                Incident
                  │
                  ▼
             Monitoring
             Dashboards
