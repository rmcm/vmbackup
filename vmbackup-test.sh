#!/bin/sh
# vmbackup-test.sh ---
# -*- Shell-script -*-
# Copyright (C) 2009 Rex McMaster
# Author: Rex McMaster rex@mcmaster.id.au
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2, or (at
# your option) any later version.
# 
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; see the file COPYING.  If not, write to
# the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
# Boston, MA 02110-1301, USA.

## ############################################################
## vmbackup controller testing: requires support functions in
##     vmbackup-functions.sh 
## ############################################################

## Include support functions

_FUNCTFILE=vmbackup-functions.sh
if ! test -s "${_FUNCTFILE}" ; then
    echo "failed to locate ${_FUNCTFILE}"
    exit 1
fi
. $_FUNCTFILE

## Add test function calls here
##
## eg to test media-mounting
##
## check_media "up"
## check_media "down"

# end vmbackup-test.sh
