#!/bin/sh

#
# POSIX-true.sh - A POSIX-compliant shell script for Raspberry Pi first-boot setup.
# This script is a direct translation of a Bash script, demonstrating POSIX-compliant techniques.
# Password input is visible as per user's request.
#

# Color definitions
MAGENTA="$(tput setaf 5)"
ORANGE="$(tput setaf 214)"
ABORT="$ORANGE"
RED="$(tput setaf 1)"
YELLOW="$(tput setaf 3)"
GREEN="$(tput setaf 2)"
BLUE="$(tput setaf 4)"
SKY_BLUE="$(tput setaf 6)"
RESET="$(tput sgr0)"

# Determines the system's package manager
package_manager(){
    if command -v apt 1>/dev/null 2>&1; then
        echo "apt"
    elif command -v pacman 1>/dev/null 2>&1; then
        echo "pacman"
    elif command -v dnf 1>/dev/null 2>&1; then
        echo "dnf"
    else
        echo "unknown"
    fi
}

# Checks for sudo privileges
check_sudo(){
    if sudo -n true 2>/dev/null; then
        has_sudo=1
    else
        has_sudo=0
    fi
}

# Checks if a command exists on the system
command_exists(){
    command -v "$1" 1>/dev/null 2>&1
    return $?
}

# Installs a package using the detected package manager
install_pkg_dynamic(){
    check_sudo
    printf '\n%s[Package] : %s%s%s\n' "$BLUE" "$GREEN" "$1" "$RESET"
    if [ "$has_sudo" -eq 0 ]; then
        printf 'You do NOT have sudo privileges. So, you are prompted for sudo password.\n%s You will not be asked for other packages if you use password correctly now\n' "$NOTE"
    fi

    if [ "$2" = "default" ] || [ -z "$2" ]; then
        pm=$(package_manager)
        if [ "$pm" = "apt" ]; then
            sudo apt install -y "$1"
        elif [ "$pm" = "pacman" ]; then
            sudo pacman -S --noconfirm --needed "$1"
        elif [ "$pm" = "dnf" ]; then
            sudo dnf install -y "$1"
        else
            echo "${RED}Unknown package manager. Cannot install '$1'. Please install it manually.${RESET}" 1>&2
        fi
    fi
    return 0
}

# Checks for all script dependencies and attempts to install them if missing
check_and_install_deps(){
    # POSIX sh does not have arrays, so we use a space-separated string.
    commands_to_packages="tput:ncurses-bin mkpasswd:whois lsblk:util-linux mktemp:util-linux grep:grep cut:coreutils wc:coreutils cat:coreutils sed:sed expr:coreutils"

    echo "${BLUE}Checking dependencies...${RESET}" 1>&2
    
    # Use 'for' loop to iterate over the string
    for item in $commands_to_packages; do
        # Use parameter expansion to split the string. POSIX sh doesn't have fancy slicing.
        cmd=$(echo "$item" | cut -d: -f1)
        pkg=$(echo "$item" | cut -d: -f2)

        if ! command_exists "$cmd"; then
            echo "${YELLOW}Command '$cmd' not found. Attempting to install package '$pkg'...${RESET}" 1>&2
            install_pkg_dynamic "$pkg"
            if ! command_exists "$cmd"; then
                echo "${RED}Failed to install '$cmd'. Please install it manually and rerun the script. Exiting.${RESET}" 1>&2
                exit 1
            fi
        fi
    done
    echo "${GREEN}All dependencies are satisfied.${RESET}" 1>&2
}

# Interactively prompts the user to select a mounted partition and returns its path
select_partition_path(){
    partition_name="$1"
    
    # Loop to allow the user to re-scan for devices
    while true; do
        # We create a temporary file to hold the parsable output, as POSIX sh has no arrays.
        parsable_output_file=$(mktemp)
        lsblk -nPo NAME,SIZE,TYPE,MOUNTPOINT > "$parsable_output_file"
        
        lsblk_output=$(lsblk)
        line_count=$(echo "$lsblk_output" | wc -l)
        
        echo "----------------------------------------" 1>&2
        echo "${YELLOW}Please select the ${partition_name} partition:${RESET}" 1>&2
        echo "$lsblk_output" | cat -n 1>&2
        echo "----------------------------------------" 1>&2
        printf '%s' "Enter the number of the partition for '${partition_name}' (or press Enter to refresh): " 1>&2
        read choice

        # If user presses enter, loop again to refresh lsblk
        if [ -z "$choice" ]; then
            echo "${ORANGE}Refreshing device list...${RESET}" 1>&2
            rm "$parsable_output_file"
            continue
        fi
        
        # POSIX way to check if input is a valid number
        case "$choice" in
            *[!0-9]*) 
                echo "${RED}Invalid input. Not a number.${RESET}" 1>&2
                rm "$parsable_output_file"
                continue
            ;; 
        esac

        if [ "$choice" -lt 1 ] || [ "$choice" -gt "$line_count" ]; then
            echo "${RED}Invalid selection. Please enter a number between 1 and ${line_count}.${RESET}" 1>&2
            rm "$parsable_output_file"
            continue
        fi
        
        data_line_index=$(expr "$choice" - 1)
        if [ "$data_line_index" -lt 1 ]; then
             echo "${RED}Invalid selection. You cannot select the header line.${RESET}" 1>&2
             rm "$parsable_output_file"
             continue
        fi
        
        # Use sed to extract the specific line from the file, simulating array access
        selected_line_data=$(sed -n "${data_line_index}p" "$parsable_output_file")
        rm "$parsable_output_file" # Clean up temp file

        mount_point=$(echo "$selected_line_data" | grep -o 'MOUNTPOINT="[^" ]*"' | cut -d'"' -f2)

        if [ -z "$mount_point" ]; then
            echo "${RED}The selected partition has no mount point. Please choose another.${RESET}" 1>&2
            continue
        fi
        
        echo "$mount_point"
        return 0
    done
}

# A POSIX-compliant user prompt function
prompt_user(){
	times=0
	while true; do
		printf '%s' "$1 [y/n]; "
		read cho
		case "$cho" in
			y|Y) return 0 ;; 
			n|N) return 1 ;; 
			*)
				times=$(expr "$times" + 1)
				if [ "$times" -gt 2 ]; then return 1; fi
				echo "invalid choice !" 1>&2
			;; 
		esac
	done
}

# Enables SSH by creating the 'ssh' file
enable_ssh(){
	if prompt_user "${YELLOW}wanna enable ssh for the first boot? ${RESET}"; then
		if [ ! -f "$rpi_root/ssh" ]; then
			touch "$rpi_root/ssh" && echo "${GREEN}Created $rpi_root/ssh successfully${RESET}" 1>&2 || echo "${RED}Failed to create $rpi_root/ssh${RESET}" 1>&2
		else
			echo "${ORANGE}$rpi_root/ssh file already exists${RESET}" 1>&2
		fi
	else
		echo "${ABORT}Aborting $rpi_root/ssh creation${RESET}" 1>&2
	fi
}

# Generates a hashed password
sha_gen(){
    # Use positional parameters to build command safely
    set -- -m "$1"
    if [ -n "$2" ]; then set -- "$@" "--salt=$2"; fi
    if [ -n "$3" ]; then set -- "$@" -R "$3"; fi
    if [ -n "$4" ]; then set -- "$@" "$4"; fi
    mkpasswd "$@"
}

# Configures WiFi settings
enable_wifi(){
	while true; do
		printf 'Type Your wifi SSID [wifi name (string)]: ' 
		read ssid
		if prompt_user "is this SSID correct ? :\"${ssid}\" "; then break; else echo "Then try again !!" 1>&2; fi
	done

	while true; do
		printf 'Type Your wifi password (string): ' 
		read passwd
		if prompt_user "is this password correct? "; then break; else echo "Then try again !!" 1>&2; fi
	done

	cat <<EOF > "$rpi_boot/wpa_supplicant.conf"
country=BD
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
	ssid="$ssid"
	psk="$passwd"
}
EOF

	if [ $? -eq 0 ]; then
		echo "${GREEN}Successfully created '$rpi_boot/wpa_supplicant.conf'${RESET}" 1>&2
	else
		echo "${RED}Failed to create '$rpi_boot/wpa_supplicant.conf'${RESET}" 1>&2
	fi
}

# Creates a new user configuration
enable_user(){
	rounds=5000 # Default value

	printf 'Type Your username: ' 
	read username
	while ! prompt_user "is this username correct ? :\"${username}\" "; do
		echo "Then try again !!" 1>&2
		printf 'Type Your username: ' 
		read username
	done

	while true; do
		echo "" 1>&2
		echo "1. give your own generated hashed password" 1>&2
		echo "2. give your password (script will generate one for you)" 1>&2
		echo "" 1>&2
		printf 'type your choice number: ' 
		read cho
		case "$cho" in
			1)
				printf 'Type Your hashed password (string): ' 
				read hashedpasswd
				while ! prompt_user "is this hashed password correct? "; do
					echo "Then try again !!" 1>&2
					printf 'Type Your hashed password (string): ' 
					read hashedpasswd
				done
				break
				;;
			2)
				echo "${MAGENTA}SHA${RESET} : ${SKY_BLUE}Secure Hash Algorithom${RESET}" 1>&2
				echo "" 1>&2
				
				printf 'Type Your password for SHA: ' 
				read passwd
				while ! prompt_user "is this password correct? "; do
					echo "Then try again !!" 1>&2
					printf 'Type Your password for SHA: ' 
					read passwd
				done

				while true; do
					echo "1. use sha-512" 1>&2
				echo "2. use sha-256" 1>&2
				printf 'type the choice number: ' 
				read method_cho
				case "$method_cho" in
					1) method="sha-512"; break ;; 
					2) method="sha-256"; break ;; 
					*) echo "invalid choice, plz type 1 or 2" 1>&2 ;; 
				esac
				done
				
				printf 'Wanna give rounds manually? default:(%s) : ' "$rounds"
				read tmp_rounds
				case "$tmp_rounds" in
					*[!0-9]*) # If not a number, do nothing
						;;
					*)
						if [ -n "$tmp_rounds" ]; then rounds="$tmp_rounds"; fi
						;;
				esac

				if prompt_user "Wanna give salt manually? : "; then
					printf 'Type the salt here: ' 
					read salt
					salt=$(echo "$salt" | sed 's/[[:space:]]//g') 
				fi

				hashedpasswd=$(sha_gen "$method" "$salt" "$rounds" "$passwd")
				break
				;;
			*)
				echo "invalid choice, plz type 1 or 2" 1>&2
				;;
		esac
	done

	cat <<EOF > "$rpi_boot/userconf"
$username:$hashedpasswd
EOF
	
	if [ $? -eq 0 ]; then
		echo "${GREEN}Successfully created '$rpi_boot/userconf'${RESET}" 1>&2
	else
		echo "${RED}Failed to create '$rpi_boot/userconf'${RESET}" 1>&2
	fi
}

# --- Main Execution ---
main() {
    check_and_install_deps

    rpi_boot=$(select_partition_path "boot")
    if [ -z "$rpi_boot" ]; then
        echo "${ABORT}Boot partition selection failed. Exiting.${RESET}" 1>&2
        exit 1
    fi
    echo "${GREEN}Boot partition set to: $rpi_boot${RESET}" 1>&2

    rpi_root=$(select_partition_path "root")
    if [ -z "$rpi_root" ]; then
        echo "${ABORT}Root partition selection failed. Exiting.${RESET}" 1>&2
        exit 1
    fi
    echo "${GREEN}Root partition set to: $rpi_root${RESET}" 1>&2

    if [ -d "$rpi_root" ]; then
        enable_ssh
    fi
    if [ -d "$rpi_boot" ]; then
        enable_wifi
        enable_user
    fi
}

main "$@"
