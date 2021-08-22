#!/usr/bin/env bash

carthage update \
    --platform iOS \
    --use-xcframeworks \
    --no-use-binaries \
    --use-ssh \
    --cache-builds \
    --new-resolver \
    "$@"
