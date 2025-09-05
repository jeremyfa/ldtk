#!/bin/bash

# Copy LDtk.app to Applications directory
if [ -d "app/redist/mac-universal/LDtk.app" ]; then
    echo "Copy LDtk.app to Applications directory..."
    sudo rm -rf /Applications/LDtk.app
    sudo cp -r app/redist/mac-universal/LDtk.app /Applications/
    echo "LDtk.app copied to Applications directory"
else
    echo "Error: LDtk.app not found in app/redist/mac-universal/"
fi
