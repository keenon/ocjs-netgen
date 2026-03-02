#!/bin/bash
set -e

# 1. Build the Docker image (should be fast if cached)
docker build -t ocjs-netgen .

# 2. Run the build to generate ocjs_with_netgen.js and ocjs_with_netgen.d.ts
docker run --rm -it -v "$(pwd):/src" -w /src -u "$(id -u):$(id -g)" ocjs-netgen ./build.yml

# 3. Append our custom TypeScript definitions
echo "Appending custom Netgen types to ocjs_with_netgen.d.ts..."
cat netgen_types.ts >> ocjs_with_netgen.d.ts

echo "Your JS and D.TS files are ready."

# 4. Create a local npm tarball
echo "Packaging for npm..."
npm pack

echo "Build complete! Your package is ready as a .tgz file."