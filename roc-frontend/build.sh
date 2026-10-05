#!/bin/bash
export PATH=/tmp/roc:$PATH

echo "Building Tailwind CSS..."
npx @tailwindcss/cli -i www/app.css -o www/dist.css --minify

echo "Building Roc Application..."
roc run build.roc
