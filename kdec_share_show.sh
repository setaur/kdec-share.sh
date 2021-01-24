#!/bin/bash
##################################################################################
#customizable:
web_browser=firefox
image_viewer="eom --fullscreen"

#maximum size of $WORKDIR in MB. If exceeded, oldest downloaded files will
#be deleted, until going below limit.
#to disable - set to 0
max_workdir_size=512

#uncomment for custom working dir:
WORKDIR="/dev/shm/$USER/$(basename "$0" | cut -d '.' -f1)"

#uncomment to disable colors in verbose mode
#export DISABLE_COLORED_DEBUG=1

#default DISPLAY
export DISPLAY=:0
##################################################################################

self_path="$(realpath "$0" )"
[[ "$XDG_CONFIG_HOME" ]] || export XDG_CONFIG_HOME="$HOME/.config"
[[ "$XDG_RUNTIME_DIR" ]] || export XDG_RUNTIME_DIR="/run/user/$(id -u "$USER" )"
[[ -d "$XDG_RUNTIME_DIR" && -w "$XDG_RUNTIME_DIR" ]] || export XDG_RUNTIME_DIR='/tmp'

#path to smplayer 'playlist.ini' config file
smplayer_playlist_ini="$XDG_CONFIG_HOME/smplayer/playlist.ini"

[[ "$WORKDIR" ]] ||\
    export WORKDIR="$XDG_RUNTIME_DIR/$(basename "$0" | cut -d '.' -f1)"

required_apps=(kdeconnect-cli kdeconnect-handler file "$web_browser"
	       inotifywatch smplayer "$(echo "$image_viewer" | cut -d' ' -f1)")

help() {
    echo -e "Share&Show script for KDE Connect Linux App

Script intended to run on linux HTPC alongside KDE Connect linux app
so it can show media shared on Android KDE Connect App on PC fullscreen.

Script detects if shared content is a file or an url. 
If it is a file(s), then KDEConnect Linux App downloads that 
file to directory $WORKDIR, which is watched by script (thanks to inotify).
If that file is an image, then it's opened by $image_viewer.
If it's a video or sound then it's opened by smplayer. Multiple video/audio files 
will be equeue in playlist. With individual video/audio file smplayer will quit at end.
With several media files, smplayer will keep playlist at repeat.

If shared content is an url, then script checks if this url can be opened by youtube-dl. 
If that's passable, then url is opened by smplayer (which uses youtube-dl).
If youtube-dl is not supporting that url, then it is downloaded and if it turns out 
to be an image, sound or video - script is progressing in the same way as with shared
file. If not - url is opened by $web_browser.

Required packages: kdeconnect, file, inotify-tools, smplayer, $(echo "$image_viewer" | cut -d' ' -f1)

Prepariation:
1. Set up a connection between linux KDE Connect and android KDE Connect

2. In linux KDEConnect Settings/[Phone Selection]/Share and Receive/[Settings button]
set path to dir:
$WORKDIR/
OR use command setup-kdeconnect-plugin - see below.

3. Change linux default web browser to $0
In example, in XFCE: run xfce4-settings-manager,
In 'Preferred Applications' / 'Web Browser' choose 'Other...'
Type '$(realpath "$0") urlopen', click OK

4. Run $0 --watch

5. On Android: choose image/video file(s) or image/video/youtube link and share it with KDE Connect

SYNTAX: $0 [OPTIONS] COMMAND

OPTIONS:
\t -v, --verbose
\t     Enable verbose mode

\t -h, --help
\t     Display this help.

\t -l FILE
\t  --logfile FILE
\t     If FILE is plain filename, then redirect all output to $WORKDIR/log/FILE
\t     if FILE is full path of file, then redirect output to that file.

COMMANDS:
\t setup-kdeconnect-plugin
\t     Set download directory in linux KDE Connect Share and Receive plugin
\t     for ALL configured connections to $WORKDIR

\t watch 
\t     Watch $WORKDIR for new images and movies using inotify-watch. 
\t     Then open it with $0 fileopen

\t fileopen FILE 
\t     Open FILE with smplayer, if it's a sound or movie,
\t     or with $image_viewer - if it's an image.

\t urlopen URL 
\t     Try if URL is supported by youtube-dl. If yes - open URL with 
\t     smplayer. If not - open URL with $web_browser

\t closeall
\t     Close all instances of $0 fileopen and $0 urlopen
\t     Can be used by Android KDE Connect Commands plugin.

\t clear-tmpdir
\t     Removes all files downloaded to temp dir: $WORKDIR
"
}

DEBUG_COLOR_START="$(tput setaf 1 2>/dev/null)"
DEBUG_COLOR_END="$(tput sgr 0 2>/dev/null)"
[[ "$DISABLE_COLORED_DEBUG" ]] && unset DEBUG_COLOR_START DEBUG_COLOR_END
debug() {
    #if variable DEBUG is set, then prints to stderr
    #can use standard echo parameters
    #extra parameters: -d,-t - adds date; -f - adds parent function name
    [[ "$DEBUG" ]] || return 0
    
    while [ $# -gt 0 ]; do
        case "$1" in
            -d|-t) local debug_date="[$(date +'%F %X' )] " ;;
            -f) local debug_function="{${FUNCNAME[1]}}: " ;;
            -*) [[ "${#debug_args[@]}" -eq 0 ]] && local debug_args=( )
                debug_args+=("$1") ;;
            *)  break;;
        esac
        shift
    done
    
    echo "${debug_args[@]}" "${DEBUG_COLOR_START}${debug_date}${debug_function}$*${DEBUG_COLOR_END}" >&2
}

prepare_dir() {
    local verbose_arg
    [[ "$DEBUG" ]] && verbose_arg='-v'
    
    mkdir -p $verbose_arg "$workdir_downloaded"
    cd "$WORKDIR" || exit
}

setup_kdeconnect_plugin() {
    cd "$XDG_CONFIG_HOME"/kdeconnect || return 1
    local dir dir_share config_file recursion
    
    for dir in *; do
	[[ -d "$dir" ]] || continue
	dir_share="$dir/kdeconnect_share"
	config_file="$dir_share/config"
	
	if ! [[ -s "$config_file" ]]; then
	    debug -f "$(mkdir -v "$dir_share" )"
	    debug -f "file $config_file doesn't exists - creating"
	    echo "[General]
incoming_path=$WORKDIR" > "$config_file"
	elif grep -q '^incoming_path=' "$config_file"; then
	    if grep -q "^incoming_path=${WORKDIR}/$" "$config_file"; then
		debug -f "$config_file - already ok"
		continue
	    fi
	    debug -f "file $config_file exists - modyfing"
	    sed -i 's#^incoming_path=.*$#incoming_path='"${WORKDIR}/#g" "$config_file"
	else
	    debug -f "non-empty file $config_file exists, but it has strange format(?)"
	    debug -f "renaming that file to ${config_file}.bak and creating new one"
	    mv -v "$config_file" "${config_file}.bak"
	    recursion=1
	fi
    done

    if [[ "$recursion" ]]; then
	unset recursion
	debug -f "recursion... oh shit here we go again!"
	"$0" "$@"
    fi
}

force_dir_size_limits_lock="$WORKDIR/force_dir_size_limits.lock"
force_dir_size_limits() {
    #keeps size of $workdir_downloaded below limit by deleting
    #oldest files, but no logs

    if [[ "$1" = unlock ]]; then
	debug -f -n "unlock: "
	if [[ -d "$force_dir_size_limits_lock" ]]; then
	    debug -f "lock exists, unlocking"
	    rmdir "$force_dir_size_limits_lock"
	else
	    debug -f "no lock."
	fi
	
	return

    elif [[ "$max_workdir_size" -eq 0 ]]; then
	debug -f "function disabled - max_workdir_size=$max_workdir_size"
	return
    elif [[ -e "$force_dir_size_limits_lock" ]]; then
	debug ''
	debug -f "another instance already running, exiting"
	return
    else
	mkdir "$force_dir_size_limits_lock"
	debug ''
	debug -f "lock - on"
    fi

    local workdir_size i oldest_file
    
    i=0
    while true; do
	i="$((i+1))"
	if [[ "$i" -gt 1024 ]]; then
	    echo "$0: Error - too many iterations!" >&2
	    exit 1
	elif ! [[ -d "$workdir_downloaded" ]]; then
	    debug -f "$(ls "$workdir_downloaded" )"
	    return 1
	fi
	
	workdir_size="$(du -s -m "$workdir_downloaded"  | awk '{print $1;}' )"
	debug -f "workdir size = $workdir_size MB"
	debug -f "testing if inside limits..."
	if [[ "$workdir_size" -gt "$max_workdir_size" ]]; then
	    #rename filenames with newline character
	    find "${workdir_downloaded:?}" -name $'*\n*' -exec rename  $'s#\n# #g' '{}' \;
	    
	    oldest_file="$(find "${workdir_downloaded:?}" -type f -not -path '*/log/*' \
	    -printf '%T+ %p\n' | sort | head -n1 | cut -d' ' -f 2-)"
	    debug -f "oldest file: '$oldest_file'"
	    if ! [[ -f "$oldest_file" ]]; then
		debug -f "error: '$oldest_file' doesn't exists!"
		break
	    fi
	    
	    debug -f "$(rm -v "${oldest_file:?}" )"
	    continue
	    
	else
	    debug -f "inside limits."
	    break
	fi
    done
    
    force_dir_size_limits unlock
}	    

watchdir() {
    local file filepath i

    debug ''
    debug -d -f 'start'
    
    prepare_dir
    force_dir_size_limits unlock
    force_dir_size_limits
    
    while read -r file; do
	debug ''
	debug -f -d "$file detected"
	if [[ "$file" =~ .part$ ]]; then
	    
	    force_dir_size_limits
	    
	    file="$(echo "$file" | sed 's#\.part$##')"
	    debug -f "changed name: $file"
	    for (( i=1; i<=10; i++ )); do
		#waiting for downloaded 'file.part' filename to change to 'file'
		[[ -f "$file" ]] && break
		sleep 0.1
		debug -n '.'
	    done

	    if [[ -f "$file" ]]; then
		debug -f "$file downloaded"
		filepath="${workdir_downloaded}/$(basename "$file")"
		mkdir -p "$workdir_downloaded"
		debug -f "$(mv -v "$file" "$filepath" )"
		
		debug -f "opening file $filepath..."
		"$self_path" fileopen "$filepath" &
	    else
		debug -f "Error downloading file '$file'"
	    fi
	fi
	debug ''
	
    done< <(inotifywait \
		--monitor \
		--quiet \
		--event close_write \
		--format %f \
		"$WORKDIR")
}

clear_tmpdir() {
    if ! [[ -d "$WORKDIR" ]]; then
	ls "$WORKDIR"
	exit 1
    elif ! [[ -d "$workdir_downloaded" ]]; then
	ls "$workdir_downloaded"
	return 1
    fi
    
    debug -f "$(rm -rv "${workdir_downloaded:?}" )"
    find "${WORKDIR:?}" -type f -iname '*.part' -print -delete
}

media_files=( )
list_all_media_files() {
    #returns array of filenames of video and audio files in dir $workdir_downloaded/
    #except of FILE specified in $0 -except FILE
    local except file gnufile_output
    if [[ "$1" = '-except' ]]; then
	#all but $2
	except="$2"
	debug -f "except $except"
	shift 2
    fi

    cd "$workdir_downloaded" || return
    
    for file in *; do
	gnufile_output="$(file --mime --no-pad "$file" | cut -d ':' -f 2- )"
	debug -f "$file: $gnufile_output"
	if echo "$gnufile_output" |\
		grep -iwq 'media\|multimedia\|video\|sound'; then
	    debug -f "detected $file"
	    if [[ "$(basename "$file")" = "$(basename "$except" )" ]]; then
		debug -f "skipping $file"
	    else
		debug -f "adding $file"
		media_files+=("$file")
	    fi
	fi
    done
    debug -f "completed list: ${media_files[*]}"
}

smplayer_() {
    smplayer \
	-close-at-end \
	-fullscreen \
	"$@"
}

fileopen() {
    local file gnufile_output
    cd "$WORKDIR" || exit
    for file in "$@"; do
	local ecode=0
	debug -d -f -e "\n$file"

	if ! [[ -s "$file" ]]; then
	    echo "'$file' doesn't exist or empty!" >&2
	    exit 1
	fi
	
	gnufile_output="$(file --mime --no-pad "$file" | cut -d ':' -f 2- )"
	debug -f "${file}: ${gnufile_output}"
    
	if echo "$gnufile_output" |\
		grep -iwq 'media\|multimedia\|video\|sound'; then
	    debug -f "opening with video player..."
	    list_all_media_files -except "$file"
	    
	    close_all

	    # This tampering with smplayer ini config file tested on smplayer 18.10.0 (version 9144):
	    if ! [[ -f "$smplayer_playlist_ini" ]]; then
		echo "Invalid path to smplayer config file: $smplayer_playlist_ini!"
	    elif ! grep -q '^repeat=' "$smplayer_playlist_ini"; then
		echo "wrong content of $smplayer_playlist_ini!"
	    else
		if [[ "${media_files[*]}" ]]; then
		    debug -f "multiple files - repeat playlist ON"
		    sed -i 's/^repeat=false$/repeat=true/g' "$smplayer_playlist_ini"
		else
		    debug -f "no multiple files - repeat playlist OFF"
		    sed -i 's/^repeat=true$/repeat=false/g' "$smplayer_playlist_ini"
		fi
	    fi
	    
	    debug -f "playing $file ${media_files[*]}..."
	    smplayer_ "$file" "${media_files[@]}"
	elif echo "$gnufile_output" |\
		grep -iwq 'image'; then
	    debug -f "opening with image viewer"
	    close_all
	    $image_viewer "$file"
	else
	    echo -e "Unsupported filetype: '$file' \n${gnufile_output}"
	    ecode=1
	    continue
	fi
    done
    return $ecode
}

close_all() {
    #close all browsers, viewers, players opened by this script
    local image_viewer_name cmd pid
    local ppids=( )
    image_viewer_name="$(echo "$image_viewer" | cut -d' ' -f1)"

    for cmd in fileopen urlopen; do
	pid="$(pgrep --full "$(basename "$0" ) $cmd" )"
	if [[ "$pid" ]]; then
	    debug -f "found parent pid: $pid"
	    ppids+=($pid)
	fi
    done

    for cmd in "$image_viewer_name" "$web_browser" smplayer; do
	for pid in "${ppids[@]}"; do
	    if pgrep -P "$pid" "$cmd" >/dev/null; then
		debug -f -n "detected $cmd - child of $pid"
		pkill -P "$pid" "$cmd" && debug ' - killed.'
		echo "$0: killed $pid - $cmd"
	    fi
	done
    done
}

urlopen() {
    prepare_dir
    cd "$workdir_downloaded" || return
    local url target quiet_args tmpdir

    for url in "$@"; do
	debug ''
	debug -f -d "$url"
	force_dir_size_limits

	[[ "$DEBUG" ]] || quiet_args='--quiet --no-warnings'
	
	debug -f "Trying youtube-dl..."
	if youtube-dl $quiet_args \
		      --simulate \
		      --format worstvideo \
		      "$url"; then
	    
	    debug -f "youtube-dl checks. Trying smplayer..."
	    smplayer_ -add-to-playlist \
		      "$url"
	else
	    debug -f "youtube-dl failed. Downloading $url..."
	    
	    quiet_args=''
	    [[ "$DEBUG" ]] || quiet_args='--quiet'

	    #all this tmpdir stuff to get name of downloaded file - no easy way with wget:
	    tmpdir="$(realpath "$(mktemp -d -p "$workdir_downloaded" tmpdir.XXX)" )"
	    [[ -d "$tmpdir" ]] || continue
	    
	    debug -f "$(wget -nv --no-use-server-timestamps --directory-prefix "$tmpdir" \
	    	     	     --continue "$url" 2>&1 )"
	    
	    target="$(find "$tmpdir" -type f -not -path '*/\.*' -exec realpath {} \; )"
	    debug -f "download: $target"

	    if ! [[ -f "$target" ]]; then
		debug -f "download failed. (target='$target')"
		rmdir "$tmpdir" || rm -r "${tmpdir:?}"; unset tmpdir
		debug -f "Therefore opening url with $web_browser"
		"$web_browser" "$url"
		continue
	    else
		debug -f "$(mv -v "$target" "$workdir_downloaded/" )"
		target="${workdir_downloaded}/$(basename "$target" )"
		debug -f "now target='$target'"
		rmdir "$tmpdir" || rm -r "${tmpdir:?}"; unset tmpdir
		
		debug -f "downloaded to $target.
Trying to open with fileopen function..."
		if fileopen "$target"; then
		    debug -f "file opened succesfully"
		else
		    debug -f "failed. Therefore opening url with $web_browser"
		    "$web_browser" "$url"
		    rm "$target"
		fi
	    fi
	fi
	debug ''
    done
}


##############################################################################

workdir_downloaded="$WORKDIR/downloaded"
    
while [[ $# -gt 0 ]]; do
    debug "processing argument $1"
    case "$1" in
	-v|--verbose)
	    export DEBUG=1
	    debug "Verbose mode"
	    ;;
	-l|--logfile)
	    logfile="$2"
	    shift
	    
	    if [[ "$logfile" =~ ^'/' ]]; then
		debug "$logfile - path absolute"
	    else
		debug "$logfile - plain filename."
		logfile="${WORKDIR}/log/${logfile}"
		debug "changed to $logfile."
		prepare_dir
		mkdir -p "$(dirname "$logfile" )" || exit
	    fi
	    echo "Logging all output to file '$logfile'"
	    
	    touch "$logfile" || exit 1

	    export DISABLE_COLORED_DEBUG=1

	    shift #remove both logging arguments
	    debug "starting again in next instance"
	    eval "$self_path" "$@" >> "$logfile" 2>&1
	    exit
	    
	    # https://serverfault.com/a/103569
	    #debug "logfile magic start"
	    #exec 3>&1 4>&2
	    #trap 'exec 2>&4 1>&3' 0 1 2 3
	    #exec 1>>"$logfile" 2>&1
	    #debug "logfile magic end"
	    ;;
	    
        -h|--help) help; exit ;;
        --)  shift; break;;
        -*)
	    echo -e "Invalid parameter '$1'\n"
	    help           
            exit 1;;
        *)  break;;
    esac
    shift
done

for app in "${required_apps[@]}"; do
    command -v "$app" >/dev/null 2>&1 && continue
    
    echo "command $app not found!"
    echo "this script requres: ${required_apps[*]}"
    echo "learn more: $0 --help"
    exit 1
done

if ! [[ "$1" ]]; then
    echo "Need command!"
    help
    exit
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
	setup-kdeconnect-plugin) setup_kdeconnect_plugin ;;
        watch)  watchdir ;;
        fileopen)  shift;  fileopen "$@" ;;
	urlopen) shift; urlopen "$@" ;;
	closeall) close_all ;;
	clear-tmpdir) clear_tmpdir ;;
        *)
	    echo -e "Invalid command '$1'\n"
	    help
	    exit 1
	    ;;
    esac
    shift
done

