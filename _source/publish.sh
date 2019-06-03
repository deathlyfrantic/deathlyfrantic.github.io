#!/usr/bin/env bash
zola build
cd public
cp -R * ../../
