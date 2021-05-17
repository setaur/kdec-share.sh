# KDEc Share - Share&Show Bash script for KDE Connect Linux App
Script intended to run on linux HTPC alongside KDE Connect linux app so it can show media shared on Android KDE Connect App on PC fullscreen. It will show both photos and videos from smartphone memory and shared hiperlinks to photos and videos from the internet.

## Principle of operation
Script detects if shared content is a file or an url. 
* If it is a file(s), then KDEConnect Linux App downloads that file to directory /dev/shm/set/kdec-share, which is watched by script (thanks to inotify).
  * If that file is an image, then it's opened by eom --fullscreen.
  * If it's a video or sound then it's opened by smplayer. Multiple media files will be equeue in playlist. With individual media file smplayer will quit at end. With several media files, smplayer will keep playlist at repeat.

* If shared content is an url, then script checks if this url can be opened by youtube-dl. 
  * If that's passable, then url is opened by smplayer (which uses youtube-dl).
  * If youtube-dl is not supporting that url, then it is downloaded and if it turns out to be an image, sound or video - script is progressing in the same way as with shared file.
    * If not - url is opened by firefox.

## Required packages
kdeconnect, file, inotify-tools, smplayer, youtube-dl, eom

## Setup
1. Set up a connection between linux KDE Connect and android KDE Connect

2. In linux KDEConnect Settings/[Phone Selection]/Share and Receive/[Settings button] set path to dir:
/dev/shm/set/kdec-share/
OR use command setup-kdeconnect-plugin - see below.

3. Change linux default web browser to './kdec-share.sh urlopen'
In example, in XFCE: run xfce4-settings-manager,
In 'Preferred Applications' / 'Web Browser' choose 'Other...'
Type: 
 /home/set/skrypty/kdec_share_show/kdec-share.sh urlopen "%s"
and click OK.

4. Run ./kdec-share.sh --watch

5. On Android: choose image/video file(s) from internal memory or image/video/youtube link and share it with KDE Connect

## SYNTAX: ./kdec-share.sh [OPTIONS] COMMAND

## OPTIONS:
	 -v, --verbose
	     Enable verbose mode

	 -h, --help
	     Display this help.

	 -H, --longhelp
	     Display longer help: required preparation steps, principle of operation

	 -l FILE, --logfile FILE
	     If FILE is plain filename, then redirect all output to 
		     /dev/shm/set/kdec-share/log/FILE
	     if FILE is full path to a file, then redirect output to that path.

## COMMANDS:
	 setup-kdeconnect-plugin
	     Set download directory in linux KDE Connect Share and Receive plugin
	     for ALL configured connections to /dev/shm/set/kdec-share

	 watch 
	     Watch /dev/shm/set/kdec-share for new images and movies using 
	     inotify-watch. Then open it with './kdec-share.sh fileopen'

	 fileopen FILE 
	     Open FILE with smplayer, if it's a sound or movie,
	     or with 'eom --fullscreen' - if it's an image.

	 open-last-mediafile
	     Open last uploaded media file.

	 urlopen URL 
	     Try if URL is supported by youtube-dl. If yes - open URL with 
	     smplayer. If not and it's an image - open with 'eom --fullscreen'. 
	     Otherwise open URL with firefox

	 closeall
	     Close all instances of './kdec-share.sh fileopen' 
	     and './kdec-share.sh urlopen'
	     Can be used by Android KDE Connect Commands plugin.

	 clear-tmpdir
	     Removes all files downloaded to temp dir: /dev/shm/set/kdec-share

