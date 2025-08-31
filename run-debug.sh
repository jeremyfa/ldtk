#!/bin/bash

haxe main.debug.hxml && haxe renderer.debug.hxml && cd app && npm run start && cd ..
