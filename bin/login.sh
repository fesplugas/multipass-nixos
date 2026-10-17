#!/usr/bin/env bash

VM_NAME=${VM_NAME:-nixos}
VM_USER=${VM_USER:-ubuntu}
VM_IP=$(multipass info "$VM_NAME" --format json | jq --raw-output ".info[\"$VM_NAME\"].ipv4[0]")

ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $VM_USER@$VM_IP
