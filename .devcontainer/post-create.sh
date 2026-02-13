#!/usr/bin/env bash
#
# Post-create script for VS Code devcontainer
# This runs after the container is created to set up the development environment
#

set -euo pipefail

echo "=== Setting up development environment ==="

# Install Hex and Rebar
echo "Installing Hex and Rebar..."
mix local.hex --force
mix local.rebar --force

# Install Elixir dependencies
echo "Installing Elixir dependencies..."
cd /workspace/app
mix deps.get

# Compile the project
echo "Compiling project..."
mix compile

# Set up the database
echo "Setting up database..."
mix ecto.create || true
mix ecto.migrate

# Install Python tools for Lambda development
echo "Installing Python tools..."
pip install --user ruff mypy bandit boto3-stubs[secretsmanager,rds,ecs,elasticache]

# Install pre-commit
echo "Installing pre-commit..."
pip install --user pre-commit
cd /workspace
pre-commit install || true

# Create PLT for Dialyzer (background)
echo "Building Dialyzer PLT (background)..."
cd /workspace/app
(mix dialyzer --plt &) || true

echo ""
echo "=== Development environment ready! ==="
echo ""
echo "Quick start:"
echo "  cd app"
echo "  mix phx.server    # Start the Phoenix server"
echo "  mix test          # Run tests"
echo "  mix format        # Format code"
echo ""
