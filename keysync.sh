#!/bin/sh

RUNNING_USER=$SUDO_USER
USER=$(whoami)
SCRIPT_PATH=$(realpath "$0")

START_MARKER="# Keysync Start - NO MODIFICAR - Desde este punto los registros serán administrados automáticamente por keysync"

Help() {
	echo -e "Tool for syncronizing SSH keys from S3 bucket."
	echo -e ""
	echo -e "Syntax:"
	echo -e "\tkeysync [-h -IC]"
	echo -e ""
	echo -e "Options:"
	echo -e "\t-h\tHelp:\t\tPrints this message."
	echo -e "\t-C\tConfigure:\tSet configuration needed for the script to work."
	echo -e "\t-I\tInstall:\tMake script available as command and set cron job for it."
	echo -e ""
	echo -e "Dependencies:"
	echo -e "\tAWS CLI\tUniversal Command Line Interface for Amazon Web Services."
	echo -e "\tCronie\tDaemon that runs specified programs at scheduled times and related tools."
}

Configure() {
	echo "Configure..."

	if ! command -v aws; then
		echo "AWSCLI not installed, please install it and try again."
		exit 1
	fi

	OUTPUT=""

	echo "Please enter bucket name:"
	read SUP_BUCKET_NAME
	SUP_BUCKET_URI="s3://$SUP_BUCKET_NAME/"
	OUTPUT="${OUTPUT}SUP_BUCKET_URI=$SUP_BUCKET_URI"

	echo "Do you want to grant access to the developers? [y/N]"
	read IS_DEV

	if [[ $IS_DEV == "y" ]]; then
		echo "Please enter bucket name:"
		read DEV_BUCKET_NAME
		DEV_BUCKET_URI="s3://$DEV_BUCKET_NAME/"
		OUTPUT="${OUTPUT}\nDEV_BUCKET_URI=$DEV_BUCKET_URI"
	fi

	AWS_PATH="$(which aws)"
	OUTPUT="${OUTPUT}\nAWS_PATH=$AWS_PATH"

	echo -e "$OUTPUT" > config.conf
	$AWS_PATH configure

	echo "Done!"
}

Install() {
	echo "Installing..."

	if [ ! -f $(dirname ${SCRIPT_PATH})/config.conf ]; then
		echo "Configuration needed before installing"
		Configure
	fi

	echo "Please enter frequency in crontab format. (Eg. 5,20,35,50 * * * * or @hourly)"
	read KEYS_UPDATE_FREQUENCY
	CHRON_REGEX=$"(@(annually|yearly|monthly|weekly|daily|hourly|reboot))|^((([0-9]|1[0-9]|2[0-3])|(\*(\/([0-9]|1[0-9]|2[0-3]))?)) (([0-9]|[1-5][0-9])|(\*(\/([0-9]|[1-5][0-9]))?)) (([1-9]|[12][0-9]|3[01])|(\*(\/([1-9]|[12][0-9]|3[01]))?)) (([1-9]|1[0-2])|(\*(\/([1-9]|1[0-2]))?)) (([0-6])|(\*(\/([0-6]))?)))$"

	if [[ "${KEYS_UPDATE_FREQUENCY}" =~ $CHRON_REGEX ]]; then
		CRONJOB="${KEYS_UPDATE_FREQUENCY} ${SCRIPT_PATH} > $(dirname ${SCRIPT_PATH})/keysync.log"
		( crontab -l | grep -v -F "${SCRIPT_PATH}" || : ; echo "${CRONJOB}" ) | crontab -
	else
		echo "Wrong format, try again."
		exit 1
	fi

	echo "Done!"
}

Uninstall() {
	echo "Uninstalling..."
	# TODO: Uninstall - Remove cron, remove from path, delete opt directory, delete etc config directory
	echo "Done!"
}

# TODO: No arguments means to sync - Check all configurations
Sync() {
	echo "Sync started"

	if ! test -f $(dirname $SCRIPT_PATH)/config.conf; then
		echo "Configuration missing!"
		exit 1
	fi

	while IFS="=" read -a LINE; do
		case "${LINE[0]}" in
			SUP_BUCKET_URI)
				SUP_BUCKET_URI="${LINE[1]}"
				;;
			DEV_BUCKET_URI)
				DEV_BUCKET_URI="${LINE[1]}"
				;;
			AWS_PATH)
				AWS_PATH="${LINE[1]}"
				;;
		esac
	done <<< "$(cat $(dirname ${SCRIPT_PATH})/config.conf)"

	if ! command -v $AWS_PATH &> /dev/null; then
		echo "AWSCLI not installed, please install it and try again."
		exit 1
	fi

	KEYS_FILE=/home/$USER/.ssh/authorized_keys
	TEMP_KEYS_FILE=$(mktemp /tmp/authorized_keys.XXXXXX)
	SUP_PUB_KEYS_DIR=/home/$USER/.ssh/sup_pub_key_files
	DEV_PUB_KEYS_DIR=/home/$USER/.ssh/dev_pub_key_files

	# Add marker, if not present, and copy static content.
	grep -Fxq "$START_MARKER" $KEYS_FILE || echo -e "\n$START_MARKER" >> $KEYS_FILE
	LINE=$(grep -n "$START_MARKER" $KEYS_FILE | cut -d ":" -f 1)
	head -n $LINE $KEYS_FILE > $TEMP_KEYS_FILE

	# Synchronize the keys from the bucket.
	mkdir -p $SUP_PUB_KEYS_DIR
	mkdir -p $DEV_PUB_KEYS_DIR

	if ! $AWS_PATH s3 sync --delete $SUP_BUCKET_URI $SUP_PUB_KEYS_DIR; then
		echo "There was an error with AWS CLI."
		exit 1
	fi

	if [ ! -z ${DEV_BUCKET_URI+x}  ]; then # TODO: delete dev keys if not present and there are some
		if ! $AWS_PATH s3 sync --delete $DEV_BUCKET_URI $DEV_PUB_KEYS_DIR; then
			echo "There was an error with AWS CLI."
			exit 1
		fi

		for FILENAME in $DEV_PUB_KEYS_DIR/*; do
			sed 's/\n\?$/\n/' < $FILENAME >> $TEMP_KEYS_FILE
		done
	else
		rm -rf $DEV_PUB_KEYS_DIR/*.pub
	fi 

	for FILENAME in $SUP_PUB_KEYS_DIR/*; do
		sed 's/\n\?$/\n/' < $FILENAME >> $TEMP_KEYS_FILE
	done

	# Move the new authorized keys in place.
	chown $USER:$USER $KEYS_FILE
	chmod 600 $KEYS_FILE
	mv $TEMP_KEYS_FILE $KEYS_FILE
	if [[ $(command -v "selinuxenabled") ]]; then
		restorecon -R -v $KEYS_FILE
	fi

	echo "Sync done"
}

while getopts "hIC" OPTION; do
	case $OPTION in
		h)
			Help
			exit;;
		I)
			Install
			exit;;
		C)
			Configure
			exit;;
		?)
			Help
			exit;;
	esac
done

Sync