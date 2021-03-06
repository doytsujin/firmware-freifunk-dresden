#!/bin/bash
tabs 4

#echo "ACHTUNG: aktuell stuerst firmware auf ubnt geraeten ab. Daher habe ich erstmal das bauen hier deaktiviert."
#exit 1

# gitlab variables
# FF_REGISTERKEY_PREFIX
# FF_BUILD_TAG

#change to directory where build.sh is
cd $(dirname $0)

#usage: see below
SCRIPT_VERSION="6"

# target file
PLATFORMS_JSON="build.json"

DL_DIR=dl
WORK_DIR=workdir
CONFIG_DIR=openwrt-configs
OPENWRT_PATCHES_DIR=openwrt-patches
OPENWRT_PATCHES_TARGET_DIR=openwrt-patches-target
DDMESH_STATUS_DIR=".ddmesh"	# used to store build infos like openwrt_patches_target states
DDMESH_PATCH_STATUS_DIR="$DDMESH_STATUS_DIR/patches-applied"


# -------------------------------------------------------------------

#Black        0;30     Dark Gray     1;30
#Red          0;31     Light Red     1;31
#Green        0;32     Light Green   1;32
#Brown/Orange 0;33     Yellow        1;33
#Blue         0;34     Light Blue    1;34
#Purple       0;35     Light Purple  1;35
#Cyan         0;36     Light Cyan    1;36
#Light Gray   0;37     White         1;37
C_NONE='\033[0m' # No Color
C_GREY='\033[1;30m'
C_RED='\033[0;31m'
C_LRED='\033[1;31m'
C_GREEN='\033[0;32m'
C_LGREEN='\033[1;32m'
C_ORANGE='\033[0;33m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[0;34m'
C_LBLUE='\033[1;34m'
C_PURPLE='\033[0;35m'
C_LPURPLE='\033[1;35m'
C_CYAN='\033[0;36m'
C_LCYAN='\033[1;36m'
C_GREY='\033[0;37m'
C_LGREY='\033[1;37m'

#save current directory when copying config file
RUN_DIR=$(pwd)

# jq: first selects the array with all entries and every entry is pass it to select().
#       select() checks a condition and returns the input data (current array entry)
#       if condition is true
# Die eckigen klammern aussenherum erzeugt ein array, in welches alle gefundenen objekte gesammelt werden.
# Fuer die meisten filenamen ist das array 1 gross. aber fuer files die fuer verschiedene router
# verwendet werden, koennen mehrere eintraege sein.

getTargetsJson()
{
cat $RUN_DIR/$PLATFORMS_JSON | sed -n "
#delete comments
s/#.*//

# delete empty lines
# delete leading and tailing spaces
s/^[ 	]*//
s/[ 	]*$//
/^$/d
p
" | jq "[ .targets[] ]"
}

listTargets()
{

 OPT="--raw-output" # do not excape values

 cleanJson=$(getTargetsJson)

#echo $cleanJson
#exit

 # first read default
 targetIdx=0
 entry=$(echo "$cleanJson" | jq ".[$targetIdx]")
 if [ -n "$entry" ]; then
	_def_target=$(echo $entry | jq $OPT '.target')
	_def_subtarget=$(echo $entry | jq $OPT '.subtarget')
	_def_variant=$(echo $entry | jq $OPT '.variant')
	_def_name=$(echo $entry | jq $OPT '.name')
	_def_selector_config=$(echo $entry | jq $OPT '.["selector-config"]')
	_def_selector_files=$(echo $entry | jq $OPT '.["selector-files"]')
	_def_selector_feeds=$(echo $entry | jq $OPT '.["selector-feeds"]')
	_def_selector_patches=$(echo $entry | jq $OPT '.["selector-patches"]')
        _def_target_patches=$(echo $entry | jq $OPT '.["target-patches"]')
	_def_openwrt_rev=$(echo $entry | jq $OPT '.openwrt_rev')
	_def_openwrt_variant=$(echo $entry | jq $OPT '.openwrt_variant')
	_def_feeds=$(echo $entry | jq $OPT '.feeds')
	_def_packages=$(echo $entry | jq $OPT '.packages')
 fi
 targetIdx=$(( targetIdx + 1 ))

 printf -- '-------------------------------------------------------------------------------------------------\n'
 printf  " %-36s | %-7s | %-7s | %-7s | %-7s | %-7s | %-s \n" target wrt_rev wrt_var config feeds files patches
 printf -- '--------------------------------------+---------+---------+---------+---------+---------+--------\n'
 # run through rest of json
 while true
 do
 	entry=$(echo "$cleanJson" | jq ".[$targetIdx]")

	if [ "$entry" = "null" ]; then
		break;	# last entry
	else
		_name=$(echo $entry | jq $OPT '.name')
		_target=$(echo $entry | jq $OPT '.target')
		_subtarget=$(echo $entry | jq $OPT '.subtarget')

		_variant=$(echo $entry | jq $OPT '.variant')
		test "$_variant" = "null"  && _variant=""

		_openwrt_rev=$(echo $entry | jq $OPT '.openwrt_rev')
		test "$_openwrt_rev" = "null"  && _openwrt_rev="$_def_openwrt_rev"

		_openwrt_variant=$(echo $entry | jq $OPT '.openwrt_variant')
		test "$_openwrt_variant" = "null"  && _openwrt_variant="$_def_openwrt_variant"

		_selector_config=$(echo $entry | jq $OPT '.["selector-config"]')
		test "$_selector_config" = "null" && _selector_config="$_def_selector_config"

		_selector_files=$(echo $entry | jq $OPT '.["selector-files"]')
		test "$_selector_files" = "null" && _selector_files="$_def_selector_files"

		_selector_feeds=$(echo $entry | jq $OPT '.["selector-feeds"]')
		test "$_selector_feeds" = "null" && _selector_feeds="$_def_selector_feeds"

		_selector_patches=$(echo $entry | jq $OPT '.["selector-patches"]')
		test "$_selector_patches" = "null" && _selector_patches="$_def_selector_patches"

                _target_patches=$(echo $entry | jq $OPT '.["target-patches"]')
                test "$_target_patches" = "null" && _target_patches="$_def_target_patches"
	fi
	
	test -z "$_name" && echo "error: configuration has no name" && break

 	printf  " %-36s | %-7s | %-7s | %-7s | %-7s | %-7s | %-7s\n" "$_name" "${_openwrt_rev:0:7}" "$_openwrt_variant" "$_selector_config" "$_selector_feeds" "$_selector_files" "$_selector_patches"

	targetIdx=$(( targetIdx + 1 ))
 done
 printf -- '-------------------------------------------------------------------------------------------------\n'
}


setup_dynamic_firmware_config()
{
	FILES="$1"

	# modify registration credentials from envronment variable passed in by gitlabs
	# FF_REGISTERKEY_PREFIX is set in gitlab UI of freifunk-dresden-firmware: settings->CI/CD->Environment
	sed -i "/register_service_url/s#registerkey='#registerkey=${FF_REGISTERKEY_PREFIX//_/:}'#" $FILES/etc/config/credentials
}


#----------------- process argument ----------------------------------
if [ -z "$1" ]; then
	# create a simple menu
	echo "Version: $SCRIPT_VERSION"
	echo "usage: $(basename $0) list | clean | feed-revisions | (target | all  [menuconfig ] [rerun] [ <make params ...> ])"
	echo " list             - lists all available targets"
	echo " clean            - cleans buildroot/bin and buildroot/build_dir (keeps toolchains)"
	echo " feed-revisions   - returns the git HEAD revision hash for current date (now)."
	echo "                    The revisions then could be set in build.json"
	echo " target           - target to build (can have regex)"
	echo "          that are defined by build.json. use 'list' for supported targets."
	echo "          'all'                   - builds all targets"
	echo "          'ramips.*'              - builds all ramips targets only"
	echo "          'ramips.rt305x.generic' - builds exact this target"
	echo "          '^rt30.*'               - builds all that start with 'rt30'"
	echo ""
	echo " menuconfig       - displays configuration menu"
	echo " rerun            - enables a second compilation with make option 'V=s'"
	echo "                    If first make failes a second make is tried with this option"
	echo " make params      - all paramerters that follows are passed to make command"
	echo ""
	exit 1
fi

#check if next argument is "menuconfig"
if [ "$1" = "list" ]; then
	listTargets
	exit 0
fi

if [ "$1" = "feed-revisions" ]; then

	REPOS="https://git.openwrt.org/feed/packages.git"
	REPOS="$REPOS https://git.openwrt.org/project/luci.git"
	REPOS="$REPOS https://git.openwrt.org/feed/routing.git"
	REPOS="$REPOS https://git.openwrt.org/feed/telephony.git"

	_date=$(date +"%b %d %Y")
	p=$(pwd)
	for r in $REPOS
	do
		name=${r##*/}
		d=/tmp/ffbuild_$name
		rm -rf $d
		git clone $r $d 2>/dev/null
		cd $d
		echo "[$name] "
		git log -1 --oneline --until="$_date"
		cd $p
	done

	exit 0
fi

#it only cleans /bin and /build_dir of openwrt directory. toolchains and staging_dir ar kept
if [ "$1" = "clean" ]; then
	MAKE_CLEAN=1
	regex=".*"	# loop through all targets. Note that targets can have different
			# buildroots (openwrt versions)

	# do not shift
else
	# target is passed as argument with its parameters

	# get target (addtional arguments are passt to command line make) 
	# last value will become DEFAULT
	regex="$1"
	shift

	if [ "$regex" = "all" ]; then
		regex=".*" 
	fi

	# remove invalid characters: '/','$'
	chars='[/$]'
	regex=${regex//$chars/}

	# append '$' to regex, to ensure that 'ar71xx.generic.xyz' is not built
	# when 'ar71xx.generic' was specified. Use 'ar71xx.generic.*' if both
	# targets should be created

	regex="$regex\$"
	echo "regex:[$regex]"

	#check if next argument is "menuconfig"
	if [ "$1" = "menuconfig" ]; then
		MENUCONFIG=1
		shift;
	fi

	#check if next argument is "rerun"
	if [ "$1" = "rerun" ]; then
		REBUILD_ON_FAILURE=1
		shift;
	fi

	BUILD_PARAMS=$*
fi

echo "### target-regex:[$regex] MENUCONFIG=$MENUCONFIG CLEAN=$MAKE_CLEAN REBUILD_ON_FAILURE=$REBUILD_ON_FAILURE"

setup_buildroot ()
{
 buildroot=$1
 openwrt_rev=$2
 openwrt_dl_dir=$3
 openwrt_patches_dir=$4
 firmware_files=$5

 openwrt_dl_tgz="$openwrt_dl_dir/openwrt-$openwrt_rev.tgz"

 git_url="https://git.openwrt.org/openwrt/openwrt.git"

	# check if directory exists. I'm not just checking
	# the build root itself, because gitlab left a working directory
	# only with freifunk files, but without all other openwrt files
	if [ ! -d "$buildroot/toolchain" ]
	then
		echo "directory [$buildroot/toolchain] not present -> re-create '$buildroot'"
		# ensure we have a clean workdir, after gitlab runner had removed
		# openwrt.org files (e.g. toolchain)
		rm -rf "$buildroot"

		# re-create buildroot
		mkdir -p "$buildroot"
		if [ ! -d "$buildroot" ]; then
			echo "Error: '$buildroot' could not be created. exit."
			exit 1
		fi

		#check if we have already downloaded the openwrt revision
		if [ -f $openwrt_dl_tgz ]
		then
			#extract into buildroot dir
			echo "using already downloaded $openwrt_dl_tgz"
			cd $buildroot
			tar xzf $RUN_DIR/$openwrt_dl_tgz
		else
			#clone from openwrt
			echo "cloning openwrt"
			git clone $git_url $buildroot
			echo "switch to specific revision"
			cd $buildroot
			git checkout $openwrt_rev >/dev/null
			echo "create openwrt tgz"
			tar czf $RUN_DIR/$openwrt_dl_tgz .
		fi
		cd $RUN_DIR

		#apply openwrt patches
		if [ -d $openwrt_patches_dir ]; then
			for i in $openwrt_patches_dir/*
			do
				echo "apply openwrt patch: $i to buildroot:$buildroot"
				# --no-backup-if-mismatch avoids creating backup files for files
				# with different names or if not exist (new files)
				patch --no-backup-if-mismatch --directory=$buildroot -p1 < $i
			done
		fi
	else
		echo -e $C_PURPLE"Buildroot [$buildroot] already present"$C_NONE
	fi

	echo -e $C_PURPLE"create dl directory/links"$C_NONE
	rm -f $buildroot/dl
	ln -s ../../$openwrt_dl_dir $buildroot/dl

	# copy common files first
	echo -e $C_PURPLE"copy rootfs$C_NONE: $C_GREEN""common"$C_NONE
	rm -rf $buildroot/files
	mkdir -p $buildroot/files
	cp -a $RUN_DIR/files/common/* $buildroot/files/

	# copy specific files over (may overwrite common)
	echo -e $C_PURPLE"copy rootfs"$C_NONE
	test -d "$RUN_DIR/files/$firmware_files)" && cp -a $RUN_DIR/files/$firmware_files/* $buildroot/files/

	echo -e $C_PURPLE"create rootfs/etc/built_info file"$C_NONE
	mkdir -p $buildroot/files/etc
	> $buildroot/files/etc/built_info

	# more dynamic changes
	setup_dynamic_firmware_config "$buildroot/files"

	echo "----- generate built_info ----"
	git_openwrt_rev=$(cd $buildroot && git log -1 --format=%H)
	git_openwrt_branch=$(cd $buildroot && git name-rev --name-only $git_openwrt_rev | sed 's#.*/##')
	echo "git_openwrt_rev:$git_openwrt_rev" >> $buildroot/files/etc/built_info
	echo "git_openwrt_branch:$git_openwrt_branch" >> $buildroot/files/etc/built_info

	# when running from gitlab only specific revision is cloned. there are no branch infos.
	# So I check if FF_BUILD_TAG is set and then use this. If not defined I use
	# the one I can determine.
	git_ddmesh_rev="$(git log -1 --format=%H)"
	if [ "$FF_BUILD_TAG" ]; then
		git_ddmesh_branch="$FF_BUILD_TAG"
	else
		git_ddmesh_branch="$(git name-rev --tags --name-only $git_ddmesh_rev | sed 's#.*/##')"

		if [ "$git_ddmesh_branch" = "undefined" ]; then
			git_ddmesh_branch="$(git branch | sed -n 's#^\* \(.*\)#\1#p')"
			echo ""
			echo -e $C_RED"WARNING: building from UN-TAGGED (git) sources"
			echo ""
			sleep 5
		fi
	fi
	echo "git_ddmesh_rev:$git_ddmesh_rev" >> $buildroot/files/etc/built_info
	echo "git_ddmesh_branch:$git_ddmesh_branch" >> $buildroot/files/etc/built_info

	echo "builtdate:$(date)" >> $buildroot/files/etc/built_info

	cat $buildroot/files/etc/built_info


} # setup_buildroot

# ---------- create directories: dl/workdir -----------
# only create top-level directories if thoses do not not
# exisist. I do not simply call 'mkdir -p'. This is because
# gitlab runner may store the content somewhere else to
# and creates a symlink to this location.
# This avoids using caching and artifacts copying between
# jobs and stages. cache and workdir are only stored on
# server where the runner is running.
# If owner of the runner doesn't setup a symlink then
# all files are stored within current directory (where build.sh
# is located)

test -L $DL_DIR || mkdir -p $DL_DIR
test -L $WORK_DIR || mkdir -p $WORK_DIR

# ---------- process all targets ------------
OPT="--raw-output" # do not excape values

targetIdx=0

# first read default values
entry=$(getTargetsJson | jq ".[$targetIdx]")
targetIdx=$(( targetIdx + 1 ))
if [ -n "$entry" ]; then
	_def_target=$(echo $entry | jq $OPT '.target')
	_def_subtarget=$(echo $entry | jq $OPT '.subtarget')
	_def_variant=$(echo $entry | jq $OPT '.variant')
	_def_name=$(echo $entry | jq $OPT '.name')
	_def_selector_config=$(echo $entry | jq $OPT '.["selector-config"]')
	_def_selector_files=$(echo $entry | jq $OPT '.["selector-files"]')
	_def_selector_feeds=$(echo $entry | jq $OPT '.["selector-feeds"]')
	_def_selector_patches=$(echo $entry | jq $OPT '.["selector-patches"]')
        _def_target_patches=$(echo $entry | jq $OPT '.["target-patches"]')
	_def_openwrt_rev=$(echo $entry | jq $OPT '.openwrt_rev')
	_def_openwrt_variant=$(echo $entry | jq $OPT '.openwrt_variant')
	_def_feeds=$(echo $entry | jq $OPT '.feeds')
	_def_packages=$(echo $entry | jq $OPT '.packages')
#echo $_def_target
#echo $_def_subtarget
#echo $_def_variant
#echo $_def_name
#echo $_def_openwrt_rev
#echo $_def_openwrt_variant
#echo $_selector_config, $_selector_feeds, $_selector_files, $_selector_patches
#echo $_def_feeds
#echo $_def_packages
fi

while true
do
	cd $RUN_DIR

	# get next potential target
 	entry=$(getTargetsJson | jq ".[$targetIdx]")
	targetIdx=$(( targetIdx + 1 ))
	test "$entry" = "null" && break

	# test "$_" = "null" && _="$_def_"

	_name=$(echo $entry | jq $OPT '.name')
	test "$_name" = "null" && _name="$_def_name"

	_target=$(echo $entry | jq $OPT '.target')
	test "$_target" = "null" && _target="$_def_target"

	_subtarget=$(echo $entry | jq $OPT '.subtarget')
	test "$_subtarget" = "null" && _subtarget="$_def_subtarget"

	_variant=$(echo $entry | jq $OPT '.variant')
	test "$_variant" = "null" && _variant="$_def_variant"

	_openwrt_rev=$(echo $entry | jq $OPT '.openwrt_rev')
	test "$_openwrt_rev" = "null" && _openwrt_rev="$_def_openwrt_rev"

	_openwrt_variant=$(echo $entry | jq $OPT '.openwrt_variant')
	test "$_openwrt_variant" = "null" && _openwrt_variant="$_def_openwrt_variant"

	_selector_config=$(echo $entry | jq $OPT '.["selector-config"]')
	test "$_selector_config" = "null" && _selector_config="$_def_selector_config"

	_selector_files=$(echo $entry | jq $OPT '.["selector-files"]')
	test "$_selector_files" = "null" && _selector_files="$_def_selector_files"

	_selector_feeds=$(echo $entry | jq $OPT '.["selector-feeds"]')
	test "$_selector_feeds" = "null" && _selector_feeds="$_def_selector_feeds"

	_selector_patches=$(echo $entry | jq $OPT '.["selector-patches"]')
	test "$_selector_patches" = "null" && _selector_patches="$_def_selector_patches"

        _target_patches=$(echo $entry | jq $OPT '.["target-patches"]')
        test "$_target_patches" = "null" && _target_patches="$_def_target_patches"

	_feeds=$(echo $entry | jq $OPT '.feeds')
	test "$_feeds" = "null" && _feeds="$_def_feeds"

	_packages=$(echo $entry | jq $OPT '.packages')
	test "$_packages" = "null" && _packages="$_def_packages"
#echo $_name
#echo $_target
#echo $_subtarget
#echo $_variant
#echo $_openwrt_rev
#echo $_openwrt_variant
#echo $_selector_config, $_selector_feeds, $_selector_files, $_selector_patches
#echo $_feeds
#echo $_packages


	#build target name to filter on
#	filter_target=$_target.$_subtarget
#	test -n "$_variant" && filter_target="$filter_target.$_variant"
#	test -n "$_openwrt_variant" && filter_target="$filter_target.$_openwrt_variant"
	filter_target="$_name"

	filterred=$(echo $filter_target | sed -n "/$regex/p")
	test -z "$filterred" && continue

	config_file="$CONFIG_DIR/$_selector_config/config.$_target.$_subtarget"
	test -n "$_variant" && config_file="$config_file.$_variant"
	test -n "$_openwrt_variant" && config_file="$config_file.$_openwrt_variant"

	echo -e $C_GREY"----------------------------------------"$C_NONE
	echo -e $C_YELLOW"Name$C_NONE              : $C_BLUE$_name"$C_NONE
	echo -e $C_YELLOW"Target$C_NONE            : $C_BLUE$_target"$C_NONE
	echo -e $C_YELLOW"Sub-Target$C_NONE        : $C_BLUE$_subtarget"$C_NONE
	echo -e $C_YELLOW"Variant$C_NONE           : $C_BLUE$_variant"$C_NONE
	echo -e $C_YELLOW"Openwrt Variant$C_NONE   : $C_BLUE$_openwrt_variant"$C_NONE
	echo -e $C_YELLOW"Config-File$C_NONE       : $C_BLUE$config_file"$C_NONE
	echo -e $C_GREY"----------------------------------------"$C_NONE


	# use short revision because openwrt build path gets too long and
	# make for ipq40xx.generic (fritzbox 4040) will fail
	# (see git log --abbrev-commit)
	buildroot="$WORK_DIR/${_openwrt_rev:0:7}"
	test -n "$_openwrt_variant" && buildroot="$buildroot.$_openwrt_variant"

	openwrt_dl_dir="$DL_DIR"
	openwrt_patches_dir="$OPENWRT_PATCHES_DIR/$_selector_patches"

	# --------- setup build root ------------------

	setup_buildroot $buildroot $_openwrt_rev $openwrt_dl_dir $openwrt_patches_dir $_selector_files

	# --------  generate feeds -----------
	echo -e $C_PURPLE"generate feed config"$C_NONE

	# create feed config from build.json
	if [ "$_feeds" = "null" ]; then
	 	echo -e $C_RED"Error: no feeds specified"$C_NONE
		exit 1
	fi

	feedConfFileName="$buildroot/feeds.conf"
	cat<<EOM > $feedConfFileName
# This file is generated by build.sh from build.json
# see: https://git.openwrt.org/feed/packages.git and others

EOM

	feedIdx=0
	while true
	do
 		feed=$(echo "$_feeds" | jq ".[$feedIdx]")
		feedIdx=$(( feedIdx + 1 ))
		test "$feed" = "null" && break

		_feed_type=$(echo $feed | jq $OPT '.type')
		_feed_name=$(echo $feed | jq $OPT '.name')
		_feed_src=$(echo $feed | jq $OPT '.src')
		_feed_rev=$(echo $feed | jq $OPT '.rev')

		# for local feeds set correct absolute filename because when workdir is a symlink, relative
		# path are note resolved correctly. Also we need to use $_selector_feeds
		if [ "$_feed_type" = "src-link" ]; then
			_feed_src="$RUN_DIR/feeds/$_selector_feeds/$_feed_src"
			_feed_rev=""	# src-link does not have a rev, because it is already in current git repo
		else
			# if we have a feed revision, then add it. "^° is a special character
			# followed by a "commit" (hash). openwrt then checks out this revision
			test "$_feed_rev" = "null" && _feed_rev=""
			test -n "$_feed_rev" && _feed_rev="^$_feed_rev"
		fi

		printf "%s %s %s\n" $_feed_type $_feed_name $_feed_src$_feed_rev  >>$feedConfFileName

	done



	echo "------------------------------"
	echo "change to buildroot [$buildroot]"
	cd $buildroot

	if [ "$MAKE_CLEAN" = "1" ]; then
		echo -e $C_PURPLE"run clean"$C_NONE
		make clean
		continue # clean next target
	fi

	# --------- update all feeds from feeds.conf (feed info) ----
	echo -e $C_PURPLE"update feeds"$C_NONE
	./scripts/feeds update -a

	echo -e $C_PURPLE"install missing packages from feeds"$C_NONE
	# install additional packages (can be selected via "menuconfig")
	idx=0
	while true
	do
	  	# use OPT to prevent jq from adding ""
		entry="$(echo $_packages | jq $OPT .[$idx])"
		test "$entry" = "null" && break
		idx=$(( idx + 1 ))

		echo -e "[$idx] $C_GREEN$entry$C_NONE"
		./scripts/feeds install $entry
	done

	echo -e $C_PURPLE"install all packages from own local feed directory (ddmesh_own)"$C_NONE
	./scripts/feeds install -a -p ddmesh_own


	# delete target dir, but only delete when no specific device/variant is built.
	# generic targets (that contains all devices) must come before specific targets.
	if [ -z "$_variant" ]; then
		echo -e $C_PURPLE"delete previous firmware$C_NONE: $C_GREEN""$buildroot/bin/targets/$_target/$_subtarget"
		rm -rf bin/targets/$_target/$_subtarget
	else
		echo -e $C_PURPLE"KEEP previous firmware$C_NONE($_variant): $C_GREEN""$buildroot/bin/targets/$_target/$_subtarget"
	fi

	#try to apply target patches
	mkdir -p $DDMESH_PATCH_STATUS_DIR
        echo -e $C_PURPLE"apply target patches"$C_NONE
        idx=0
        while true
        do
                # use OPT to prevent jq from adding ""
		test -z "$_target_patches" && break

                entry="$(echo $_target_patches | jq $OPT .[$idx])"
                test "$entry" = "null" && break
                test -z "$entry"  && break

                idx=$(( idx + 1 ))

		# check patch
		if [ -f $RUN_DIR/$OPENWRT_PATCHES_TARGET_DIR/$_selector_patches/$entry ]; then
			printf "[$idx] $C_GREEN$entry$C_NONE"

			# if patch is not applied yet
			if [ ! -f $DDMESH_PATCH_STATUS_DIR/$entry ]; then
		                if patch -t --directory=$RUN_DIR/$buildroot -p0 < $RUN_DIR/$OPENWRT_PATCHES_TARGET_DIR/$_selector_patches/$entry >/dev/null; then
					printf " -> $C_GREEN%s$C_NONE\n" "ok"
					touch $DDMESH_PATCH_STATUS_DIR/$entry
				else
					printf " -> "$C_RED"failed"$C_NONE"\n"
					exit 1
				fi
			else
					printf " -> already applied\n"
			fi
		else
			echo -e $C_RED"Warning: patch [$_selector_patches/$entry] not found!"$C_NONE
		fi
        done

	#copy after installing feeds, because .config will be overwritten by default config
	echo -e $C_PURPLE"copy configuration$C_NONE: $C_GREEN$RUN_DIR/$config_file$C_NONE"
	rm -f .config		# delete previous config in case we have no $RUN_DIR/$config_file yet and want to
				# create a new config
	cp $RUN_DIR/$config_file .config


	if [ "$MENUCONFIG" = "1" ]; then
		echo -e $C_PURPLE"run menuconfig"$C_NONE
		make menuconfig
		echo -e $C_PURPLE"copy back configuration$C_NONE: $C_GREEN$RUN_DIR/$config_file$C_NONE"
		cp .config $RUN_DIR/$config_file
		exit 0
	fi

	# run defconfig to correct config dependencies if those have changed.

	echo -e $C_PURPLE"run defconfig"$C_NONE
	make defconfig

	# make clean because openwrt could fail building targets after building different targets before
	# but keep generated directories (ddmesh-makefile-lightclean.patch)
	make lightclean

	echo -e $C_PURPLE"copy back configuration$C_NONE: $C_GREEN$RUN_DIR/$config_file$C_NONE"
	cp .config $RUN_DIR/$config_file

	# run make command
	echo -e $C_PURPLE"time make$C_NONE $C_GREEN$BUILD_PARAMS$C_NONE"
	time -p make $BUILD_PARAMS
	error=$?
	echo "make ret: $error"

	# continue with next target in build.targets
	if [ $error -ne 0 ]; then
		echo -e $C_RED"Error: build error"$C_NONE
		if [ "$REBUILD_ON_FAILURE" = "1" ]; then
			echo -e $C_PURPLE".......... rerun build with V=s ........................"$C_NONE
			time -p make $BUILD_PARAMS V=s -j1
			error=$?
			if [ $error -ne 0 ]; then
				echo -e $C_RED"Error: build error - 2nd make run reported an error"$C_NONE
				exit 1
			fi
		else
			exit 1
		fi
	fi

	# check if we have file
	if [ ! -d "$RUN_DIR/$buildroot/bin/targets/$_target/$_subtarget" ]; then
		echo -e $C_RED"Error: build error - generated directory not found"$C_NONE
		echo "     $buildroot/bin/targets/$_target/$_subtarget/"
		exit 1
	fi

	echo -e $C_PURPLE"images created in$C_NONE $C_GREEN$buildroot/bin/targets/$_target/$_subtarget/..."$C_NONE

done

echo -e $C_PURPLE".......... complete build finished ........................"$C_NONE
echo ""

