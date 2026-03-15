#!/usr/bin/env bash
set -ex

KUBECTL=$(which kubectl)

$KUBECTL rollout restart deployment aws-load-balancer-controller -n kube-system
$KUBECTL rollout status deployment aws-load-balancer-controller -n kube-system

$KUBECTL get ingress crystolia-alb -n crystolia
$KUBECTL describe ingress crystolia-alb -n crystolia
