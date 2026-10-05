#!/bin/bash

# Example commands used during the monitoring setup.
# Review and adapt these commands to your Linux distribution.

# Check Node Exporter
systemctl status node_exporter

# Check Prometheus
systemctl status prometheus

# Check Grafana
systemctl status grafana-server

# Verify Node Exporter metrics
curl http://localhost:9100/metrics
