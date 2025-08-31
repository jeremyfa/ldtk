#!/bin/bash

if [ ! -d ".haxelib" ]; then
    haxelib newrepo
    haxe setup.hxml
    haxelib list
fi

cd app
npm install
npm run pack-prepare
CSC_IDENTITY_AUTO_DISCOVERY=false npm run pack-macos
cd ..
