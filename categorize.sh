#!/bin/bash
#
# Puts tv-series files in the right folder structure
###The location of the temp file
tmp_location="$HOME/"
seriedb_location="$tmp_location.seriedb"
## Define dirs here
vid_target_location="$HOME/series/"
mov_target_location="$HOME/video/"

###################################################
# Cleanup temp files this script creates
# Globals:
#   seriedb_location
# Arguments:
#   None
# Returns:
#   None
###################################################
function cleanup {
    echo "Cleanup..."
    if [ -f $seriedb_location ]; then
        rm $seriedb_location
    fi
    exit 0;
}

###################################################
# Function that asks a user to confirm an action
# Globals:
#   None
# Arguments:
#   (Optional) n - Default to no instead of yes
# Returns:
#   true or false
###################################################
function confirm {
    read yesno
    value=""
    if [ -z "$yesno" -o "$yesno" == "y" ];then
        value=true
        if [ "$1" == "n" -a -z "$yesno" ]; then 
            value=""
        fi
    fi
    echo $value
}

# Create new series 
# new_series NAME SEASON FILENAME FILEPATH
###################################################
# Creates a new folder structure for a given file
# Globals:
#   None
# Arguments:
#   name: series name
#   season: season of the episode
#   filename: name of the file
#   filepath: path of the file
# Returns:
#   None
###################################################
function new_series {
    echo "Create new serie for $1? [Y/n]"
    if [ $(confirm) ];then

        # The name of the new series
        target_serie_name="$(echo $1 | sed -e "s/\b\(.\)/\u\1/g")"

        # Ask if this series name is correct and if it needs to be changed
        echo "$target_serie_name"
        echo "Change name for $target_serie_name? [y/N]"

        # If the serie name needs to be changed prompt for new name
        if [ $(confirm n) ];then
            read -ei "$target_serie_name" "target_serie_name"
        fi

        # Display what will be created
        echo "Making directory $vid_target_location$target_serie_name/"
        echo "Making directory $vid_target_location$target_serie_name/Season $2/"
        echo "Moving to $vid_target_location$target_serie_name/Season $2/$3"

        # Request confimation for file writes
        echo "Confirm? [Y/n]"
        if [ $(confirm) ];then

            # If confirmed write files
            mkdir -p "$vid_target_location$target_serie_name/"
            mkdir -p "$vid_target_location$target_serie_name/Season $2/"
            mv "$4" "$vid_target_location$target_serie_name/Season $2/$3"
        else
            return 1
        fi
    else
        return 1
    fi
}

# Flag to do cleanup or not
cleanup=true
# Read flags
for arg in "$@"; do
    if [[ "$arg" =~ ^- ]]; then
        if [ "$arg" == "-s" ]; then
            cleanup=false
        fi
    fi
done

# Make sure cleanup gets run if script is terminated
if [ $cleanup = true ]; then
    trap cleanup INT
fi

if [ ! $# -gt 0 ]; then
    echo "Usage ./cleanup DIR_TO_CATEGORIZE"
    exit 1
fi

seriedb="cat $seriedb_location"

# Generate database so that doesn't need to be rechecked for every file
if [ $cleanup = true ]; then
    echo -ne "Generating database...\r"
    ls $vid_target_location > $seriedb_location
    echo "Database generated..."
fi

# Start looping over script parameters
for arg in "$@"; do
    # If the argument is a directory call script recursively
    if [ -d "$arg" ]; then 
        find "$arg" -type f -exec $0 -s {} \;
        continue
    fi

    # If the argument is not valid
    if [ ! -f "$arg" ]; then 
        if [[ ! $arg =~ ^- ]]; then
            echo "Parameter $arg is not a valid file."
            continue
        fi
    fi

    file_name=$(echo "$arg" | sed "s/.*\///")
    echo "Running for $file_name"

    # Check file extension
    valid_extensions=( avi mp4 mkv )
    extension="$(echo $file_name | sed 's/.*\.//')"
    for i in "${valid_extensions[@]}"; do
        if [ "$extension" == $i ];then
            skip=true
            break
        fi
        skip=false
    done
    if [ $skip == false ]; then
        echo "Skipping file with invalid extension."
        continue
    fi

    # Find the S##E## in the file name
    season_ep="$(echo $file_name \
        | sed 's/\.[^.]*$//'\
        | sed 's/[^a-zA-Z0-9]/\n/g'\
        | egrep -i 's|e' | sed 's/[^0-9]//g'\
        | head -n 1\
        | tr -d "\n")"
    file_name_length="$(echo $season_ep | wc -L)"

    # Find the number of the line where the season is defined so all lines after that can be thrown away
    end_file_name_nr="$(($(echo $file_name | sed 's/[^a-zA-Z0-9]/\n/g'| egrep -in '(s|e)+.*[0-9]+' | cut -c1 | head -n 1) - 1))"

    # If the found season is invalid try to detect it better
    if [ $file_name_length -gt 4 -o $file_name_length -lt 1 ]; then
        echo "Special season check running on $file_name"
        season_ep="$(echo $file_name | sed 's/\.[^.]*$//' | sed 's/[^a-zA-Z0-9]/\n/g' | grep -vi '[^0-9]' | sed 's/[^0-9]//g' | tr -d "\n")"
        file_name_length="$(echo $season_ep | wc -L)"
        end_file_name_nr="$(echo $(echo $file_name | sed 's/[^a-zA-Z0-9]/\n/g'| egrep -in '^[0-9]+$' | sed 's/:.*$//')-1|bc)"
        echo "Special season check over"
    fi

    # If a season and ep is found then
    if [ $file_name_length -lt 5  -a $file_name_length -gt 0 ]; then

        # Isolate season and episode number seperatly
        season=$(echo $season_ep | cut -c 1)
        episode=$(echo $season_ep | cut -c 2-3)
        if [ $file_name_length -eq 4 ]; then
            episode=$(echo $season_ep | cut -c 3-4)
            season=$(echo $season_ep | cut -c 1-2)
        fi

        # Remove start 0's
        episode=$(echo $episode | sed 's/^0*//')
        season=$(echo $season | sed 's/^0*//')
        echo "Season: $season Episode: $episode"
        serie_name="$(echo $file_name | sed 's/[^a-zA-Z0-9]/\n/g'| head -$end_file_name_nr | tr "\n" " " | sed 's/ *$//')"

        # Look if the serie exists already; write possible matches to file
        found_ser="$($seriedb | grep --ignore-case "$serie_name")"

        nr_matches=$(grep -vc '^$' <<< "$found_ser")

        # Fuzzy search the serie name
        if [[ $nr_matches == 0 ]]; then
            echo "Special series check"
            found_ser+="$(echo $serie_name | tr " " "\n" | sed  "s/the\|and//I" | sed "/ +$/d"| xargs -I "{}" grep -i "{}" $seriedb_location | sort | uniq)"
        fi

        # Number of matches in the current vid target dir
        nr_matches=$(grep -vc '^$' <<< "$found_ser")

        # If there are no matches in the current vid target dir
        if [[ $nr_matches == 0 ]]; then
            # Ask to create a new serie
            new_series $serie_name $season $file_name $arg
            continue
        fi
        echo "Found $nr_matches matches: "

        # Display all possible matches numbered
        nl <<< "$found_ser"
        # This is required in the while loop
        nr_chosen="0"

        # If there is more then one match
        if [ "$nr_matches" -gt 1 ]; then
            while [ "$nr_chosen" -lt 1 -o "$nr_chosen" -gt "$nr_matches" ]; do

                # Request to choose between possible matches
                echo "Enter 1 to $nr_matches:"
                read nr_chosen
                if [ -z "$nr_chosen" ]; then
                    nr_chosen="0"
                fi

            done
        else
            nr_chosen="1"
        fi

        target_serie_name=$(echo "$found_ser" | sed -n $nr_chosen'p')
        folder="$vid_target_location$target_serie_name/Season $season/"
        echo "Moving to $folder$file_name"
        if [ ! -e "$folder" ];then
            echo "Making dir $folder"
        fi
        echo "Confirm? [Y/n]"
        if [ $(confirm) ];then
            if [ ! -e "$folder" ];then
                mkdir "$folder"
            fi
            mv "$arg" "$folder$file_name"
        else
            new_series "$serie_name" "$season" "$file_name" "$arg"
        fi
    else
        echo "No season detected for file $arg"
    fi  
    echo "--------"
done
if [ $cleanup = true ]; then
    cleanup
fi
