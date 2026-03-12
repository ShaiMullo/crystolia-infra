#!/usr/bin/env bash
set -ex

KUBECTL=$(which kubectl)

$KUBECTL label secret repo-crystolia-gitops -n argocd "argocd.argoproj.io/secret-type=repository" --overwrite

$KUBECTL apply -f /Users/shaimullo/projects/crystolia-gitops/argocd/bootstrap/root-app.yaml

sleep 5
$KUBECTL get application -n argocd
$KUBECTL describe application root-app -n argocd
