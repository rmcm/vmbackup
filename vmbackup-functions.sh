#!/bin/sh
# vmbackup-functions.sh ---
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
## Basic Variables
## ############################################################
DEBUG=${DEBUG:=""}
MSGLINE="###########################################################"
ERRORTAG=":ERROR::"
SENDTO="root@localhost"
SITENAME="SITE-NAME"
BACKUPMOUNT=/backups
DAILYMOUNT=/daily-backups
VMCMD=vmware-vim-cmd
VM_USER=root
VM_PWD=password
VMHOST_EXEMPT="/backups /daily-backups /vm"
VMHOST_DAYS_KEEP=5
VMGUEST_EXEMPT=""
VMGUEST_DAYS_KEEP=5

## ############################################################
## Configuration file
## ############################################################
## RC file can change above defaults, or execute additional commands
## at this point, before the main script begins ... eg spin-up disk;
##
## # wake mirror drive up - hack for Seagate FreeAgent USB disk
## /sbin/sdparm --command=start /dev/sdc
##
## To execute additional commands at the end of this script, eg spin-down
## disk, use the _EXECUTE_AT_END envvar which is eval'd at the end of this
## script
##
## # stop mirror drive - hack for Seagate FreeAgent USB disk
## _EXECUTE_AT_END="/sbin/sdparm --command=stop /dev/sdc"
##
## Include local configuration
if test -s .vmbackuprc ; then
    . .vmbackuprc
fi


## ############################################################
## Derived Variables
## ############################################################
VMHOST_DIR=$BACKUPMOUNT/vmhost/directories
VMHOST_ARC=$BACKUPMOUNT/vmhost/archives
VMGUEST_DIR=$BACKUPMOUNT/vmguest/directories
VMGUEST_ARC=$BACKUPMOUNT/vmguest/archives
BACKUPDAILYDIR=$BACKUPMOUNT/daily-archives
TS_STR=`/bin/date +%G%m%d`

## ############################################################
## Support Functions
## ############################################################

## Exit with error message
exerr() {
    echo "${ERRORTAG} <$*>"
    exit 1
}

# Print a banner'd message
bannermsg() {
    echo
    echo ${MSGLINE}
    echo $*
    echo ${MSGLINE}
}

## Parse the command-line arguments
parse_args() {

    local USAGE="
-n    debug: display actions without performing them
-h    print this message
"
    while getopts :hn OPT; do
        case $OPT in
            h|+h)
                printf "
$USAGE"
                exit 1
                ;;
            n|+n)
                DEBUG="echo ... "
                ;;
            *)
                echo "usage: `basename $0` [+-hn} [--] ARGS..."
                exit 2
        esac
    done
    shift `expr $OPTIND - 1`
    OPTIND=1
}

## set a target list from possible, include and exclude lists
set_list() {
    # arg1 = baselist, arg2 = method (+=inclusive, -=exclusive), arg3 = supplementary-list
    test $# -ne 3 && exerr "function set_list() requires 3 args"

    local _base="$1"
    local _mode=$2
    local _supp="$3"

    # iterate throught the list, if we get a match
    # return true, else false
    _final=""
    for check_base in $_base ; do
        for check_supp in $_supp ; do
	    if [ "$check_base" = "$check_supp" ]; then
                if [ $_mode = "+" ] ; then
                    _final="${_final} ${check_base}"
                fi
                # match - so skip to next base item
                continue 2
            fi
        done
        # if we get to here, there's not been a match
        if [ $_mode = "-" ] ; then
            _final="${_final} ${check_base}"
        fi
    done
    echo $_final
}


## Mount or remount media
mount_media() {
    # arg1 = mount-point (from /etc/fstab)
    test $# -ne 1 && exerr "function mount_media() requires 1 arg"

    local _mountpoint=$1

    if test -z ${_mountpoint} ; then
        exerr "<SYSTEM ERROR>>> mountmedia requires name of mount point"
    fi

    echo "Mounting $_mountpoint"

    if grep -q $_mountpoint /etc/mtab ; then
        echo "$_mountpoint is already mounted - unmounting"
        if ! umount $_mountpoint ; then
            echo "${ERRORTAG} failed to umount $_mountpoint"
            return 1
        fi
    fi

    echo "mount $_mountpoint"
    if ! mount $_mountpoint ; then
        echo "${ERRORTAG} failed to mount $_mountpoint"
        return 2
    fi
    return 0
}

## Check structure of mirror media
check_media() {
    ## if the archives directory does not  exist, create it
    if ! mkdir -p $BACKUPMOUNT/{host,vmware}/{directories,archives} \
        $BACKUPMOUNT/daily-archives ; then
        return 1
    fi
    return 0
}

## check for exempt element in list
check_exempt() {
    # arg1 = element, arg2 = list
    test $# -ne 2 && exerr "function check_exempt() requires 2 args"

    local _element=$1 
    local _exempt="$2"

    # iterate throught the list, if we get a match
    # return true, else false
    for check_item in $_exempt; do
        
	if [ "$check_item" = "$_element" ]; then
            return 0
	fi
    done
    return 1
}

## Convert pathname to safe foldername
convert_path() {
    # Convert /a/b/c to a_b_c or "root"
    # arg1 = path  (print safe name to stdout)
    test $# -ne 1 && exerr "function convert_path() requires 1 arg"
    
    local _safe="`echo $1 | sed -e 's,^/,,' -e 's,/*$,,' -e 's,[/.],_,g'`"

    if test -z "$_safe" ; then
        _safe="root"
    fi
    echo $_safe
}

## rsync live tree to mirror media
exec_rsync() {
    # synchronise (update) all data to the directories tree
    # arg1 = sourcedir arg2 = destinationdir
    test $# -ne 2 && exerr "function exec_rsync() requires at 2 args"

    local _srcdir=$1
    local _dstdir=$2

    _srcdir=`echo $_srcdir | sed -e 's,/*$,/,'`
    _dstdir=`echo $_dstdir | sed -e 's,/*$,/,'`
    echo "... rsyncing $_srcdir to $_dstdir"
    if ! test -d $_dstdir ; then
        if ! ${DEBUG} mkdir -p $_dstdir ; then
            echo "${ERRORTAG} failed to create destination directory - $_dstdir/"
            return 1
        fi
    fi
    ${DEBUG} rsync -ax --delete $_srcdir $_dstdir
    return $?
}

## build archives.
exec_tgz() {
    # tar rsync'd directory tree to archive
    # arg1 = sourcedir-parent arg2 = sourcedirectory arg3 = destination archive
    test $# -ne 3 && exerr "function exec_tgz() requires 3 args"

    local _srcpar=$1
    local _srcdir=$2
    local _dsttgz=$3
    local _dsttgz_base=`basename ${_dsttgz}`

    echo "... archiving $_srcdir (in $_srcpar) to $_dstdir"
 
    if ! ${DEBUG} tar --one-file-system -C $_srcpar -zcf $_dsttgz $_srcdir ; then
        echo "... failed to create $_dsttgz"
        return 1
    fi

    # create link to archive 
    ${DEBUG} rm -f $BACKUPDAILYDIR/${_dsttgz_base}
    ${DEBUG} ln -fs ${_dsttgz} $BACKUPDAILYDIR/${_dsttgz_base}

    return 0
}
 
## purge old archives
purge_archives() {
    # tar rsync'd directory tree to archive
    # arg1 = archive dir arg2 = purge-age in days arg3 = file-pattern
    test $# -ne 3 && exerr "function purge_archives() requires 3 args"

    local _prgdir=$1
    local _prgage=$2
    local _prgptn=$3

    echo "... purging archives older than $_prgage days"
    echo ${DEBUG} find $_prgdir -name "$_prgptn" -mtime +$_prgage
    if ! ${DEBUG} find $_prgdir -name "$_prgptn" -mtime +$_prgage | ${DEBUG} xargs rm -vf ; then
        echo "${ERRORTAG} failed to purge archives in $_prgdir"
        return 1
    fi

    return 0

}

## Backup a specified folder to mirror and archive
dir_backup() {
    # backup FOLDER
    # arg1 = source arg2 = sync directory arg3 = purge-age in days
    # arg4 = archive directory
    test $# -ne 4 && exerr "function dir_backup() requires 4 args"

    local _srcdir=$1
    local _sncdir=$2
    local _prgday=$3
    local _arcdir=$4
    
    _safedir=`convert_path $_srcdir`
    _arcname=backup_${_safedir}-${TS_STR}.tgz
    echo "Current source-directory is $_srcdir"

    # actually do the directory backup
    if ! exec_rsync $_srcdir ${_sncdir}/${_safedir} ; then
        echo "${ERRORTAG} failed to rsync $_srcdir to ${_sncdir}/${_safedir}"
        continue
    fi
    ${DEBUG} sleep 5

    ## purge old archives

    if ! purge_archives ${_arcdir} ${_prgday} "backup_${_safedir}-*.tgz" ; then
        echo "${ERRORTAG} failed to purge archives in "
        continue
    fi
    ${DEBUG} sleep 5

    # tar it up
    if ! exec_tgz ${_sncdir} ${_safedir} ${_arcdir}/${_arcname} ; then
        echo "${ERRORTAG} failed to archive ${_sncdir}/${_safedir} to ${_arcdir}/${_arcname}"
        continue
    fi
    ${DEBUG} sleep 5
}

## Get list of guests
vm_getlist() {
    _vmlist=
    $VMCMD -U $VM_USER -P $VM_PWD vmsvc/getallvms |sed 1d | \
        while read VMID NAME TYPE LOC OS VMVER; do
        _vmlist="${_vmlist} $NAME"
    done
    echo $_vmlist
}
## Get powerstate of specified host
vm_powerstate() {
    # get power state of vm
    # arg1 = vm id
    test $# -ne 1 && exerr "function vm_powerstate() requires 1 arg"
    local _vmid=$1

    ${DEBUG} $VMCMD -U $VM_USER -P $VM_PWD vmsvc/power.getstate $_vmid |sed 1d

    return $?
}

# Suspend vm for backup
vm_suspend() {
    # suspend vm
    # arg1 = vm id
    test $# -ne 1 && exerr "function vm_suspend() requires 1 arg"
    local _vmid=$1

    ${DEBUG} $VMCMD -U $VM_USER -P $VM_PWD vmsvc/power.suspend $_vmid

    return $?
}

# Resume vm
vm_resume() {
    # suspend vm
    # arg1 = vm id
    test $# -ne 1 && exerr "function vm_resume() requires 1 arg"
    local _vmid=$1

    ${DEBUG} $VMCMD -U $VM_USER -P $VM_PWD vmsvc/power.on $_vmid

    return $?
}

## Prepare a daily archive for offsite storage
dailyarchives() {
    # Create MD5SUM file of daily archives
    # Rsync daily archives to offsite media
    # Return status

    ( ${DEBUG} cd $BACKUPMOUNT/daily-archives/ && ${DEBUG} md5sum *tgz > MD5SUMS )
    ${DEBUG} rsync -aL --delete $BACKUPMOUNT/daily-archives/ $DAILYMOUNT/ || {
        echo "${ERRORTAG} failed to rsync $BACKUPMOUNT/daily-archives/ to $DAILYMOUNT/"
        return 1
    }
    return 0
}

## Backup the VM host system
backup_host() {

    awk '$3=="ext3"{print}' ./fstab | \
        while read DEV MOUNT TYPE OPTIONS C1 C2; do
    
        # check to see if current srcdir should be exempted
        if check_exempt $MOUNT "${VMHOST_EXEMPT}" ; then
            echo "... skipping $MOUNT which is on exempt list"
            continue
        fi

        dir_backup $MOUNT $VMHOST_DIR $VMHOST_DAYS_KEEP $VMHOST_ARC

    done

}

## Backup the VM guests
backup_guests() {

    $VMCMD -U $VM_USER -P $VM_PWD vmsvc/getallvms |sed 1d | \
        while read VMID NAME TYPE LOC OS VMVER; do

        VMDIR=${LOC%/*}
        # check to see if current vm should be exempted
        if check_exempt $VMDIR "${VMGUEST_EXEMPT}" ; then
            echo "... skipping $VMDIR which is on exempt list"
            continue
        fi
        
        
        _STATE=`get_powerstate $VMID`
        if test "${_STATE}" = "Powered on" ; then
            if ! vm_suspend $VMID ; then
                echo "${ERROR} failed to suspend $NAME ($VMID) ... skipping"
                continue
            fi
        fi
        dir_backup $VMDIR $VMGUEST_DIR $VMGUEST_DAYS_KEEP $VMGUEST_ARC "${VMGUEST_EXEMPT}"
        if test "${_STATE}" = "Powered on" ; then
            if ! vm_resume $VMID ; then
                echo "${ERROR} failed to resume $NAME ($VMID) ... skipping"
                continue
            fi
        fi
        
    done
 

}

# parse script arguments
parse_args $*

# end vmbackup-functions.sh
