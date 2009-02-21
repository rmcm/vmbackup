#!/bin/bash
# vmbackup.sh ---
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
## vmbackup controller: requires support functions in
##     vmbackup-functions.sh 
## ############################################################

## Include support functions

_FUNCTFILE=vmbackup-functions.sh
if ! test -s "${_FUNCTFILE}" ; then
    echo "failed to locate ${_FUNCTFILE}"
    exit 1
fi
. $_FUNCTFILE

# Perform in subshell to manage output
(
    if test -n "${_EXECUTE_AT_BEG}" ; then
        ${_EXECUTE_AT_BEG}
    fi

    ## check the backup media
    bannermsg "Checking backup media"
    if ! check_media "up" ; then
        exerr "Media checked failed ... aborting"
    fi

    ## Backup the host directories
    bannermsg "Backing up VMHOST Folders"
    sleep 60
    backup_host
    
    ## backup VM Guests
    bannermsg "Backing up VM Guest Folders"
    sleep 60
    backup_guests
    
    ## Backup daily archives to offsite media
    bannermsg "Creating daily offsite backup"
    sleep 60
    dailyarchives

    ## Execute locals before umounting the drives
    if test -n "${_EXECUTE_AT_END}" ; then
        ${_EXECUTE_AT_END}
    fi

    ## Check backup media - umount
    bannermsg "Final media check"
    sleep 60
    if ! check_media "down" ; then
        echo "${ERRORTAG} failed final media check"
    fi

    ) 2>&1 | tee -a ${VMBACKUPLOG}/backups.log \
        > ${VMBACKUPLOG}/backup-daily.log

MSGSTATUS="Succeeded"
if grep -q "$ERRORTAG" ${VMBACKUPLOG}/backup-daily.log ; then
    MSGSTATUS="Failed"
fi

grep -v 'socket ignored' ${VMBACKUPLOG}/backup-daily.log | \
    mail -s "${SITENAME}:Backup ${MSGSTATUS}" ${SENDTO}

# end vmbackup.sh
