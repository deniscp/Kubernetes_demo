#!/usr/bin/bash
set -e

### Deploy a demo app on Kubernetes


kubectl apply -f mysql-resources.yaml
kubectl apply -f php_my_admin-resources.yaml
kubectl apply -f php_apache-resources.yaml
