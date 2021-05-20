# kdec-share.sh
## Share&Show Bash script for KDE Connect Linux App
Script intended to run on linux HTPC alongside KDE Connect. It will show media shared on mobile with KDE Connect App on PC fullscreen. 
Script shows both photos and videos from smartphone memory and shared internet hyperlinks to photos and videos.

## Principle of operation
By default when you share something in KDE Connect mobile app, it will work one of two ways:
* If shared content is a file saved in smartphone memory (in example a photo), then that file will be uploaded to PC into folder set in KDE Connect linux app settings.
* If shared content is an url (in example to youtube video), then KDE Connect opens that url on PC with default browser.

To capture both of this ways user of this script has to change KDE Connect Linux App default file receive directory, and Linux default browser (more in [Setup](#setup)).

Script detects if shared content is a file uploaded from a smartphone or an url. 
* If it is a file(s), then KDEConnect Linux App downloads that file to directory $WORKDIR, which is watched by script (thanks to inotify).
  * If that file is an image, then it's opened by $image_viewer (default: eom --fullscreen).
  * If it's a video or sound, then it's opened by fullscreen Smplayer. Multiple media files will be equeue in a playlist.
    * With individual media file smplayer will quit at end.
    * With several media files, smplayer will keep playlist at repeat.

* If shared content is an url, then script checks if this url can be opened by youtube-dl.
  * If that's passable, then url is opened by Smplayer (which uses youtube-dl).
  * If youtube-dl is not supporting that url, then it is downloaded.
    * If it turns out to be an image, sound or video - script is progressing in the same way as with shared file.
    * If it's not image, sound or video, then url is opened by $web_browser (default: firefox).

## Required packages
kdeconnect, file, inotify-tools, smplayer, youtube-dl, eom

## Setup
1. Set up a connection between linux KDE Connect and android KDE Connect

2. Download kdec-share.sh, run `chmod +x kdec-share.sh`

3. In linux KDEConnect Settings/[Phone Selection]/Share and Receive/[Settings button] set path to dir:
* $WORKDIR (run `./kdec-share.sh -H` to resolve that variable)
* or use command `kdec-share.sh setup-kdeconnect-plugin` - see [below](#commands).

4. Change linux default web browser to 'PATH/TO/kdec-share.sh urlopen'
* In example, in XFCE: 
  * run xfce4-settings-manager,
  * In 'Preferred Applications' / 'Web Browser' choose 'Other...'
  * Type: `/PATH/TO/kdec-share.sh urlopen "%s"` (ofcourse fix the path)
  * Click OK.

5. Run `/PATH/TO/kdec-share.sh watch`

6. On Android: 
* choose image/video file(s) from internal memory or image/video/youtube link 
* share it with KDE Connect
* it should be displayed on a PC screen.

___

# SYNTAX 
### kdec-share.sh [OPTIONS] COMMAND

## OPTIONS
	 -v, --verbose
	     Enable verbose mode

	 -h, --help
	     Display this help.

	 -H, --longhelp
	     Display longer help: required preparation steps, principle of operation

	 -l FILE, --logfile FILE
	     If FILE is plain filename, then redirect all output to 
		     $WORKDIR/log/FILE
	     if FILE is full path to a file, then redirect output to that path.

## COMMANDS
	 setup-kdeconnect-plugin
	     Set download directory in linux KDE Connect Share and Receive plugin
	     for ALL configured connections to $WORKDIR

	 watch 
	     Watch $WORKDIR for new images and movies using 
	     inotify-watch. Then open it with 'kdec-share.sh fileopen'

	 fileopen FILE 
	     Open FILE with smplayer, if it's a sound or movie,
	     or with 'eom --fullscreen' - if it's an image.

	 open-last-mediafile
	     Open last uploaded media file.

	 urlopen URL 
	     Try if URL is supported by youtube-dl. If yes - open URL with 
	     smplayer. If not and it's an image - open with 'eom --fullscreen'. 
	     Otherwise open URL with $web_browser (default: firefox)

	 closeall
	     Close all instances of 'kdec-share.sh fileopen' 
	     and 'kdec-share.sh urlopen'
	     Can be used by Android KDE Connect Commands plugin.

	 clear-tmpdir
	     Removes all files downloaded to temp dir: $WORKDIR
