#!/bin/bash
docker stats --no-stream --format "table {{.Container}}\t{{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}" | tail -n +2 | sort -k3 -h -r | head -5
