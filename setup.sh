#!/usr/bin/env bash

MAGENTA="$(tput setaf 5)"
ORANGE="$(tput setaf 214)"
ABORT="$ORANGE"
RED="$(tput setaf 1)"
YELLOW="$(tput setaf 3)"
GREEN="$(tput setaf 2)"
BLUE="$(tput setaf 4)"
SKY_BLUE="$(tput setaf 6)"
RESET="$(tput sgr0)"

check_and_install_deps(){
    local commands_to_packages=(
        "tput:ncurses-bin"
        "mkpasswd:whois"
        "lsblk:util-linux"
        "mktemp:util-linux"
        "grep:grep"
        "cut:coreutils"
        "wc:coreutils"
        "cat:coreutils"
    )

    echo "${BLUE}Checking dependencies...${RESET}" >&2
    for item in "${commands_to_packages[@]}"; do
        local cmd="${item%%:*}"
        local pkg="${item##*:}"

        if ! command_exists "$cmd"; then
            echo "${YELLOW}Command '$cmd' not found. Attempting to install package '$pkg'...${RESET}" >&2
            install_pkg_dynamic "$pkg"
            if ! command_exists "$cmd"; then
                echo "${RED}Failed to install '$cmd'. Please install it manually and rerun the script. Exiting.${RESET}" >&2
                exit 1
            fi
        fi
    done

    if (( BASH_VERSINFO[0] < 4 )); then
        echo "${RED}Error: Bash version 4.0 or higher is required for 'mapfile' command. Please update Bash. Exiting.${RESET}" >&2
        exit 1
    fi

    echo "${GREEN}All dependencies are satisfied.${RESET}" >&2
}

check_sudo(){
    if sudo -n true 2>/dev/null; then
        has_sudo=1
    else
        has_sudo=0
    fi
}

command_exists(){
    command -v "$1" >/dev/null 2>&1
    return $?
}

package_manager(){
    if command_exists apt;then
        echo "apt"
    elif command_exists pacman;then
        echo "pacman"
    elif command_exists dnf;then
        echo "dnf"
    else
        echo "none"
    fi
}

install_pkg_dynamic(){ # took this func from my another proj and shrinked in usability as this proj needs less functionality

check_sudo

echo -e "\n$BLUE[Package] : $GREEN$1$RESET\n"
if [[ $has_sudo -eq 0 ]]; then
echo -e "You do NOT have sudo privileges. So, you are prompted for sudo password.\n$NOTE You'll not be asked for other packages if you use password correctly now"

fi

    if   [[ $2 == default || -z $2 ]];then #1. Install if needed with prompt (no reinstall/default/safe)
        local pm
        pm=$(package_manager)
        if   [[ $pm == "apt" ]];then
            sudo apt install -y "$1"
        elif [[ $pm == "pacman" ]];then
            sudo pacman -S --noconfirm --needed "$1"
        elif [[ $pm == "dnf" ]];then
            sudo dnf install -y "$1"
        else
            echo "${RED}Unknown package manager. Cannot install '$1'. Please install it manually.${RESET}"
        fi
    fi

    return 0;
}

# Run dependency check at the start
check_and_install_deps


# Interactively prompts the user to select a mounted partition and returns its path.
# Arg1: The name of the partition to ask the user for (e.g., "boot", "root").
select_partition_path(){
    local partition_name="$1"
    
    
    local choice
    while true; do
			# Get raw lsblk output for parsing later. Use a format that's easy to parse.
			# We use a temporary file to hold the output.
			local parsable_output_file=$(mktemp)
			lsblk -nPo NAME,SIZE,TYPE,MOUNTPOINT > "$parsable_output_file"
			
			# Use mapfile (or readarray) to read lines into a Bash array.
			mapfile -t parsable_lines < "$parsable_output_file"
			rm "$parsable_output_file" # Clean up the temp file

			local lsblk_output
			lsblk_output=$(lsblk) # Get the pretty output for display
			
			local line_count # Total lines in the pretty lsblk output (including header)
			line_count=$(echo "$lsblk_output" | wc -l)
			
        echo "----------------------------------------" >&2
        echo "${YELLOW}Please select the ${partition_name} partition:${RESET}" >&2
        echo "$lsblk_output" | cat -n >&2 # Display lsblk output with line numbers to stderr
        echo "----------------------------------------" >&2
		echo -e "${ORANGE}if you can't find your devices then insert the device and\npress enter keeping the input field blank${RESET}" >&2
		echo "----------------------------------------" >&2
        
        read -p "Enter the number of the partition to use for '${partition_name}': " choice >&2
        
        # Validate input is a number and within range
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 )) || (( choice > line_count )); then
            echo "${RED}Invalid selection. Please enter a number between 1 and ${line_count}.${RESET}" >&2
            continue
        fi

        # Get the line chosen by the user (adjusting for 0-based array index)
        # The first line of `lsblk` is the header, so we look at the line in the parsable output
        # that corresponds to the user's choice minus the header (line 1 is header, line 2 is first data)
        local data_line_index=$((choice - 2)) # -1 for 0-based, -1 for header
        if (( data_line_index < 0 )) || (( data_line_index >= ${#parsable_lines[@]} )); then
             echo "${RED}Invalid selection. You cannot select the header line or an empty line.${RESET}" >&2
            continue
        fi
        
        local selected_line_data="${parsable_lines[$data_line_index]}"

        # Safely extract the MOUNTPOINT value from the key-value pair line
        local mount_point
        mount_point=$(echo "$selected_line_data" | grep -o 'MOUNTPOINT="[^"]*"' | cut -d'"' -f2)

        if [[ -z "$mount_point" ]]; then
            echo "${RED}The selected partition has no mount point. Please choose a mounted partition.${RESET}" >&2
            continue
        fi
        
        # If we get here, the selection is valid. Echo the mount point to be captured.
        echo "$mount_point" # This echo goes to stdout, intended for capture
        return 0
    done
}

# Get boot and root paths interactively
rpi_boot=$(select_partition_path "boot")
if [[ -z "$rpi_boot" ]]; then
    echo "${ABORT}Boot partition selection failed. Exiting.${RESET}"
    exit 1
fi
echo "${GREEN}Boot partition set to: $rpi_boot${RESET}"

rpi_root=$(select_partition_path "root")
if [[ -z "$rpi_root" ]]; then
    echo "${ABORT}Root partition selection failed. Exiting.${RESET}"
    exit 1
fi
echo "${GREEN}Root partition set to: $rpi_root${RESET}"

prompt_user(){ # ready func
	local cho
	local times=0
	while true;do
		read -p "$1 [y/n]; " cho
		case $cho in
		y|Y)
			return 0
			;;
		n|N)
			return 1
			;;
		*)
			((times++));if ((times>2));then return 1; fi # max 3 attempt
			echo "invalid choice !"
		esac
	done
}
enable_ssh(){ # ready func
	if prompt_user "${YELLOW}wanna enable ssh for the first boot? ${RESET}";then
		if [[ ! -f "$rpi_root/ssh" ]];then
			touch "$rpi_root/ssh" && echo "${GREEN}Created $rpi_root/ssh successfully${RESET}" || echo "${RED}Failed to create $rpi_root/ssh${RESET}"
		else
			echo "${ORANGE}$rpi_root/ssh file already exists${RESET}"
		fi
		if [[ $? == 0 ]];then
			echo "${GREEN}Created $rpi_root/ssh${RESET}"
		else
			echo "${RED}Failed to create $rpi_root/ssh${RESET}" 
		fi
	else
		echo "${ABORT}Aborting $rpi_root/ssh creation${RESET}"
		return 0
	fi
}
sha_gen(){ # $1 sha-256/512 $2 salt $3 rounds $4 passwd
	local cmd_arg=(-m "$1")
	if [[ -n $2 ]];then
		cmd_arg+=("--salt=$2")
	fi
	if [[ -n $3 ]];then
		cmd_arg+=(-R "$3")
	fi
	if [[ -n $4 ]];then
		cmd_arg+=("$4")
	fi
	echo "$(mkpasswd "${cmd_arg[@]}")"
}
#sha_gen_cli(){
#}
enable_wifi(){ # ready func
	local ssid
	local passwd
	while true;do
		read -p "Type Your wifi SSID [wifi name (string)] : " ssid
		if prompt_user "is this SSID correct ? :\"${ssid}\" ";then
			break
		else
			echo "Then try again !!"
		fi
	done
	while true;do
		read -p "Type Your wifi password (string) : " passwd
		if prompt_user "is this password correct ? :\"${passwd}\" ";then
			break
		else
			echo "Then try again !!"
		fi
	done

	if [[ ! -f "$rpi_boot/wpa_supplicant.conf" ]];then
		touch "$rpi_boot/wpa_supplicant.conf"
	fi

	cat <<-EOF > "$rpi_boot/wpa_supplicant.conf"
		country=BD
		ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
		update_config=1

		network={
			ssid="$ssid"
			psk="$passwd"
		}
	EOF

	if [[ $? == 0 ]];then
		echo "${GREEN}Successfully created '$rpi_boot/wpa_supplicant.conf'${RESET}"
	else
		echo "${RED}Failed to create '$rpi_boot/wpa_supplicant.conf'${RESET}"
	fi
}
enable_user(){
	local username
	local passwd
	local hashedpasswd

	local method
	local rounds=5000
	local salt

	while true;do																# gain user name
		read -p "Type Your username : " username
		if prompt_user "is this username correct ? :\"${username}\" ";then
			break
		else
			echo "Then try again !!"
		fi
	done

	while true;do																# gain hashed password
		local cho
		echo ""
		echo "1. give your own generated hashed password"
		echo "2. give your password (script will generate one for you)"
		echo ""
		read -p "type your choice number : " cho
		if [[ $cho == "1" ]];then													# manual
			while true;do
				read -p "Type Your hashed password (string)" hashedpasswd
				if prompt_user "is this hashed password correct ? :\"${hashedpasswd}\" ";then
					break
				else
					echo "Then try again !!"
				fi
			done
			break
		elif [[ $cho == 2 ]];then													# sha_gen by script
			echo "${MAGENTA}SHA${RESET} : ${SKY_BLUE}Secure Hash Algorithom${RESET}"
			echo
			while true;do # gain password
				read -p "Type Your password for SHA : " passwd
				if prompt_user "is this password correct ? :\"${passwd}\" ";then
					break
				else
					echo "Then try again !!"
				fi
			done
			while true;do
				local cho
				echo "1. use sha-512"
				echo "2. use sha-256"
				read -p "type the choice number : " cho
				case $cho in
				1)
					method="sha-512"
					break
				;;
				2)
					method="sha-256"
					break
				;;
				*)
					echo "invalid choice, plz type 1 or 2"
				;;
				esac
			done
			
			local tmp_rounds
			read -p "Wanna give rounds manually ? default:($rounds) : " tmp_rounds   # rounds
			if [[ "$tmp_rounds" =~ ^[0-9]+$ ]]; then
				rounds="$tmp_rounds"
			fi
			
    		if prompt_user "Wanna give salt manually? : "; then						 # salt
    			read -p "Type the salt here: " salt
    			# Remove all whitespace from the salt
    			salt="${salt//[[:space:]]/}" 
    		fi

			hashedpasswd="$(sha_gen "$method" "$salt" "$rounds" "$passwd")"

			break
		else
			echo "invalid choice, plz type 1 or 2"
		fi
	done


	if [[ ! -f "$rpi_boot/userconf" ]];then
		touch "$rpi_boot/userconf"
	fi

	cat <<-EOF > "$rpi_boot/userconf"
		$username:$hashedpasswd
	EOF
	

	if [[ $? == 0 ]];then
		echo "${GREEN}Successfully created '$rpi_boot/userconf'${RESET}"
	else
		echo "${RED}Failed to create '$rpi_boot/userconf'${RESET}"
	fi
}


if [[ -d "$rpi_root" ]];then
	enable_ssh
fi
if [[ -d "$rpi_boot" ]];then
	enable_wifi
	enable_user
fi