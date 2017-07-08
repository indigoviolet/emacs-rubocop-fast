#!/bin/bash

# Rubocop has an annoying behavior with --auto-correct --stdin where it combines the offense report and the corrected output
# https://github.com/bbatsov/rubocop/issues/2502#issuecomment-252184708
#
# Fix by splitting into STDOUT and STDERR

rubocop $* | perl -0777 -ne '/(.*?)^=+$\\n(.*)/ms; print STDERR $1; print STDOUT $2;'
