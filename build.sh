#!/bin/zsh
# Builds AutumnLeaves.swift and starts it. Quit from the 🍂 menu bar icon or press Ctrl-C.
set -e
cd "${0:A:h}"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc not found. Run: xcode-select --install"
  exit 1
fi

swiftc -O AutumnLeaves.swift -o AutumnLeaves
echo "🍂 Built. Leaves are falling..."
exec ./AutumnLeaves
