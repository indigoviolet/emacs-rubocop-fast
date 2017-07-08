#!/bin/bash

rubocop $* | perl -0777 -ne '/(.*?)^=+$\\n(.*)/ms; print STDERR $1; print STDOUT $2;'
