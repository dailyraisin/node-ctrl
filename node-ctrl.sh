#!/bin/bash
# @company Daily Raisin LLC
# @author Joe Kovach
# @role control script to take a node service up and down
# @usage: node-ctrl.sh /full/path/app.js 8000 {start|stop|restart}

#how many seconds to wait before respawning a node server
PAUSE=5

#functions
usage() {
	echo "usage: $ME {app.js} {port} {env} {start|stop|restart} [--debug]";
}

echo_success() {
  [ "$BOOTUP" = "color" ] && $MOVE_TO_COL
  echo -n "["
  [ "$BOOTUP" = "color" ] && $SETCOLOR_SUCCESS
  echo -n $"  OK  "
  [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
  echo -n "]"
  echo -ne "\r"
  return 0
}

echo_failure() {
  [ "$BOOTUP" = "color" ] && $MOVE_TO_COL
  echo -n "["
  [ "$BOOTUP" = "color" ] && $SETCOLOR_FAILURE
  echo -n $"FAILED"
  [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
  echo -n "]"
  echo -ne "\r"
  return 1
}



#path to app.js
SERVER=$1

#port
PORT=$2

#node environment
ENV=$3

#action is start, stop, or restart
ACTION=$4

case "$ENV" in
production)
    #okay
;;
development)
    #okay
;;
*)
    #not okay, usage message
	usage;
    exit 1
esac

ME=`basename $1`
THIS_PATH="`dirname \"$0\"`" # relative
THIS_PATH="`( cd \"$THIS_PATH\" && pwd )`" #normalized

# get optional --debug as fourth argument, if it’s set then $DO_DEBUG == true
argc="$@ flubber"
x=0
# x=0 for unset variable
for arg in $argc
    do
        case $x in
            "--debug" )
                DO_DEBUG=true;;
        esac
        x=$arg
done

BOOTUP="color"
RES_COL=60
MOVE_TO_COL="echo -en \\033[${RES_COL}G"
SETCOLOR_SUCCESS="echo -en \\033[1;32m"
SETCOLOR_FAILURE="echo -en \\033[1;31m"
SETCOLOR_WARNING="echo -en \\033[1;33m"
SETCOLOR_NORMAL="echo -en \\033[0;39m"


# set up logging locations
# if tmp not available, log to this directory
TMP_PID_FILE="/var/tmp/${ME}-${ENV}-${PORT}.pids"
if [ -a "$TMP_PID_FILE" ]; then  #if exists
	if [ ! -w "$TMP_PID_FILE" ]; then #if not writable
		echo "Cannot write .pids to /var/tmp, !-w";
		echo "Try it with sudo!";
        echo_failure;
		exit 1;
	fi;
else #doesn't exist
	if [ ! -w "/var/tmp/" ]; then #cannot write to directory
		echo "Cannot write .pids to /var/tmp";
		echo "Try it with sudo!";
        echo_failure;
		exit 1;
	fi;
fi;

TMP_QUIT_FILE="/var/tmp/${ME}-${ENV}-${PORT}.quit"
if [ -a "$TMP_QUIT_FILE" ]; then  #if exists
	if [ ! -w "$TMP_QUIT_FILE" ]; then #if not writable
		echo "Cannot possibly write .quit to /var/tmp, !-w";
		echo "Try it with sudo!";
        echo_failure;
		exit 1;
    else
        #remove it, it's not supposed to be there on startup!
        rm $TMP_QUIT_FILE;
	fi;
else #doesn't exist
	if [ ! -w "/var/tmp/" ]; then #cannot write to directory
		echo "Cannot possibly write .quit to /var/tmp";
		echo "Try it with sudo!";
        echo_failure;
		exit 1;
	fi;
    #doesn't exist and I can write to /var/tmp, cool, proceed! normal operation
fi;


OUTPUT="/var/tmp/${ME}-${ENV}-${PORT}.out"
if [ -a "$OUTPUT" ]; then  #if exists
	if [ ! -w "$OUTPUT" ]; then #if not writable
		echo "Cannot write .out to /var/tmp, !-w";
		echo "Try it with sudo!";
        echo_failure;
		exit 1;
	fi;
fi;

if [ ! -r $SERVER ]; then #cannot find node app to run
	echo "Cannot find node server to run. Check the path to $SERVER";
    echo_failure;
	exit 1;
fi;

if [ -r $OUTPUT ]; then
	chown $(whoami) $OUTPUT
fi;

# find necessary commands
NODE=`command -v node`
EXIT=$?
if [ $EXIT -ne 0 ]; then
    NODE=`command -v nodejs`
    EXIT=$?
    if [ $EXIT -ne 0 ]; then
        echo "node-ctrl: Cannot find node nor nodejs $EXIT" >> $OUTPUT;
        echo_failure;
        exit 1;
    fi;
fi;

PGREP=`command -v pgrep`
EXIT=$?
if [ $EXIT -ne 0 ]; then
	echo "node-ctrl: Cannot find pgrep $EXIT" >> $OUTPUT;
    echo_failure;
	exit 1;
fi;

# start, stop, restart actions
case $ACTION in
start)
	{
        #following echoes are logged
		THIS_INSTANCE=$$
		$PGREP -f "$SERVER $PORT $ENV start" > $TMP_PID_FILE

		for POSSIBLE_PID in `cat $TMP_PID_FILE`; do
			if [ "$THIS_INSTANCE" -ne "$POSSIBLE_PID" ] ; then #inner shell‘s id is not one found
                if [ "$PPID" -ne "$POSSIBLE_PID" ] ; then #parent pid is not one found (happens when bash -c "" remote commanding)
                    # if /proc/POSSIBLE_PID/stat exists
                    if [ -e "/proc/$POSSIBLE_PID/stat" ]; then
                        AM_I_DADDY=`cat /proc/$POSSIBLE_PID/stat | perl -ne '@s = split(/ /); print $s[3]'`;
                        #echo "AM I DADDY? " $AM_I_DADDY;

                        # if 4th column is NOT THIS_INSTANCE
                        if [ $AM_I_DADDY -ne $THIS_INSTANCE ]; then
                            #I am not the parent of this process, so I think it’s another instance
                            echo "node-ctrl: Another instance is running. Please stop first (pid=$POSSIBLE_PID).";
                            touch $TMP_QUIT_FILE; #use file to communicate this to outer shell
                        fi;
                    else
                        #no /proc exists, assume this is another instance
                        echo "node-ctrl: No /proc, must be already running. Please stop first (pid=$POSSIBLE_PID).";
                        touch $TMP_QUIT_FILE; #use file to communicate this to outer shell
                    fi;
                fi;
			fi;
		done
		rm $TMP_PID_FILE;
	} 2>&1 | logger

    #this shell knows about the possible error above from the existance of the file
    if [ -a "$TMP_QUIT_FILE" ]; then  #if exists
        echo "node-ctrl: Already running, stop first.";
        rm $TMP_QUIT_FILE;
        echo_failure;
        exit 1;
    fi;

    echo "Starting";

    EXPR="$NODE $SERVER $PORT -env=$ENV"
    (

        if [ $DO_DEBUG ]; then
            export DEBUG=*
        else
            export DEBUG=0
        fi;

        #subshell so I can daemonize it
        exec >> $OUTPUT
        exec 2>&1

        until $EXPR; do
            echo "Server '$SERVER' crashed with exit code $?.  Respawning..." >&2
            sleep $PAUSE;
        done
    ) &
    echo_success;

;;
stop)
	PARENT_PID=`$PGREP -f "$SERVER $PORT $ENV start"`
	if [ -n "$PARENT_PID" ] ; then #actually running the parent (parent=former instance of this script with the until loop)
		$PGREP -f "$NODE $SERVER $PORT -env=$ENV" > $TMP_PID_FILE #children
		echo "Attempting to stop $SERVER";
		echo "Killing parent $PARENT_PID";
		echo "Killing parent $PARENT_PID" >> $OUTPUT;
		kill -TERM $PARENT_PID; #kill parent first so it doesn't respawn the child

		for CHILD_PID in `cat $TMP_PID_FILE`; do
			echo "Killing child $CHILD_PID";
			echo "Killing child $CHILD_PID" >> $OUTPUT;
			kill -TERM $CHILD_PID;
		done
		rm $TMP_PID_FILE;
	else
		echo "No parent bash loop running.";
	fi;

	#straggler, i.e. a node server that has broken away from the parent bash loop and needs to be stopped
	#might exist after parent bash loop is killed
    #note: has -env=
	STRAGGLER_PID=`$PGREP -f "$SERVER $PORT -env=$ENV"`
	if [ -n "$STRAGGLER_PID" ]; then #straggler PID exists
		kill -TERM $STRAGGLER_PID;
        echo_success;
	else
		echo "No lingering node server running.";
	fi;
    echo_success;
;;
restart)
	$0 $1 $PORT -env=$ENV stop;
	$0 $1 $PORT -env=$ENV start;
;;
*)
	usage;
	exit 1;
;;
esac
exit 0;
