#!/bin/bash -eu

echo "Installing dependencies..."

# Install jq if not available
if ! command -v jq &> /dev/null; then
    echo "Installing jq..."
    sudo apt-get update
    sudo apt-get install -y jq
fi

# Install dateutils for date calculations
echo "Installing dateutils for date calculations..."
wget -q https://bitbucket.org/hroptatyr/dateutils/downloads/dateutils-0.4.10.tar.xz
tar Jxf dateutils-0.4.10.tar.xz
cd dateutils-0.4.10/
./configure --quiet
sudo make install > /dev/null 2>&1
cd ..
rm -rf dateutils-0.4.10*

echo "Dependencies installed successfully."
