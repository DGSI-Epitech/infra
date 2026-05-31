#!/bin/sh
awk -F'"' '/^SSH_PUBLIC_KEY=/{print $2}' "$1"
