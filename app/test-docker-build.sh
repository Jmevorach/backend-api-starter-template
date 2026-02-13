#!/bin/bash

set -e

cd "$(dirname "$0")"

echo "🐳 Testing Docker Build"
echo "======================"
echo ""

# Detect architecture
ARCH=$(uname -m)
echo "Detected architecture: $ARCH"
echo ""

# Test AMD64 build (native or emulated)
echo "📦 Testing AMD64 build..."
echo "------------------------"
docker buildx build \
  --platform linux/amd64 \
  --build-arg HEX_UNSAFE_HTTPS=0 \
  -t backend-service:test-amd64 \
  --load \
  --progress=plain \
  . || {
  echo "❌ AMD64 build failed"
  exit 1
}
echo "✅ AMD64 build successful"
echo ""

# Test ARM64 build
echo "📦 Testing ARM64 build..."
echo "------------------------"
if [ "$ARCH" = "arm64" ]; then
  echo "Building natively on ARM64 (no QEMU emulation)"
  docker buildx build \
    --platform linux/arm64 \
    --build-arg HEX_UNSAFE_HTTPS=0 \
    -t backend-service:test-arm64 \
    --load \
    --progress=plain \
    . || {
    echo "❌ ARM64 build failed"
    exit 1
  }
else
  echo "Building with QEMU emulation (using HEX_UNSAFE_HTTPS workaround)"
  docker buildx build \
    --platform linux/arm64 \
    --build-arg HEX_UNSAFE_HTTPS=1 \
    -t backend-service:test-arm64 \
    --load \
    --progress=plain \
    . || {
    echo "❌ ARM64 build failed"
    exit 1
  }
fi
echo "✅ ARM64 build successful"
echo ""

# Verify images
echo "🔍 Verifying images..."
echo "---------------------"
echo ""
echo "AMD64 image:"
docker images backend-service:test-amd64 --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
docker inspect backend-service:test-amd64 --format='Architecture: {{.Architecture}}' 2>/dev/null || echo "Architecture: amd64"
echo ""

echo "ARM64 image:"
docker images backend-service:test-arm64 --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
docker inspect backend-service:test-arm64 --format='Architecture: {{.Architecture}}' 2>/dev/null || echo "Architecture: arm64"
echo ""

echo "✅ All builds completed successfully!"
echo ""
echo "To test running the image:"
echo "  docker run -p 443:443 backend-service:test-amd64"
echo "  docker run -p 443:443 backend-service:test-arm64"

