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

	echo "Done!"
}

Install() {
	echo "Installing..."

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