#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
# OpenZeppelin v5.6.1 and forge-std v1.12.0, pinned to immutable commit IDs.
forge install --no-git \
  OpenZeppelin/openzeppelin-contracts@5fd1781b1454fd1ef8e722282f86f9293cacf256 \
  foundry-rs/forge-std@7117c90c8cf6c68e5acce4f09a6b24715cea4de6
