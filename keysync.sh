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

	echo "Please enter bucket name:"
	read BUCKET_NAME
	BUCKET_URI="s3://$BUCKET_NAME/"
	AWS_PATH="$(which aws)"

	echo -e "BUCKET_URI=$BUCKET_URI\nAWS_PATH=$AWS_PATH" > config.conf
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
	CHRON_REGEX=$"(@(annually|yearly|monthly|weekly|daily|hourly|reboot))|(@every ([0-9]+(ns|us|µs|ms|s|m|h))+)|(((([0-9]+,)+[0-9]+|([0-9]+(\/|-)[0-9]+)|[0-9]+|\*) ?){5,7})"

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
			BUCKET_URI)
				BUCKET_URI="${LINE[1]}"
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
	PUB_KEYS_DIR=/home/$USER/.ssh/pub_key_files

	# Add marker, if not present, and copy static content.
	grep -Fxq "$START_MARKER" $KEYS_FILE || echo -e "\n$START_MARKER" >> $KEYS_FILE
	LINE=$(grep -n "$START_MARKER" $KEYS_FILE | cut -d ":" -f 1)
	head -n $LINE $KEYS_FILE > $TEMP_KEYS_FILE

	# Synchronize the keys from the bucket.
	mkdir -p $PUB_KEYS_DIR
	if ! $AWS_PATH s3 sync --delete $BUCKET_URI $PUB_KEYS_DIR; then
		echo "There was an error with AWS CLI."
		exit 1
	fi

	for FILENAME in $PUB_KEYS_DIR/*; do
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