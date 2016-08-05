#!/bin/bash
###The location of the temp file
tmp_location="$HOME/"
seriedb_location="$tmp_location.seriedb"
## Define dirs here
vid_target_location="$HOME/series/"
mov_target_location="$HOME/video/"

###Cleanup function called after each script call
function cleanup {
    if [ -f "$tmp_location.found_vid" ]; then
        rm "$tmp_location.found_vid" 
    fi
    if [ -f "$tmp_location.found_ser" ]; then
        rm "$tmp_location.found_ser"
    fi
    if [ -f $seriedb_location ]; then
        rm $seriedb_location
    fi
    exit 0;
}

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
function new_series {
    echo "Create new serie for $1? [Y/n]"
    if [ $(confirm) ];then

        # The name of the new series
        target_serie_name=$(echo $1 | sed -e "s/\b\(.\)/\u\1/g")

        # Ask if this series name is correct and if it needs to be changed
        echo $target_serie_name
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
            mkdir "$vid_target_location$target_serie_name/"
            mkdir "$vid_target_location$target_serie_name/Season $2/"
            mv "$4" "$vid_target_location$target_serie_name/Season $2/$3"
        else
            return 1
        fi
    else
        return 1
    fi
}

# Create new movie
# new_series NAME FILEPATH
function new_movie {
    movie_name=$(echo $1 | sed "s/\..*$//")
    echo "Create new movie for for $movie_name [Y/n]"
    if [ $(confirm) ]; then
        # The name of the new movie
        target_movie_name=$(echo $movie_name | sed -e "s/\b\(.\)/\u\1/g")
        # Ask if this name is correct and if it needs to be changed
        echo $target_movie_name
        echo "Change name for $target_movie_name? [y/N]"

        # If the serie name needs to be changed prompt for new name
        if [ $(confirm n) ];then
            read -ei $target_movie_name target_movie_name
        fi

        echo "Making directory $mov_target_location$target_movie_name/"
        basenam=$(basename $2)
        echo $basenam
        echo "Moving to $mov_target_location$target_movie_name/$1"
        echo "Confirm? [Y/n]"
        if [ $(confirm) ]; then
            mkdir $mov_target_location$target_movie_name/
            mv $2 $mov_target_location$target_movie_name/$1
        fi
    fi
}

## Make sure cleanup gets run if script is canceled
trap cleanup INT
if [ ! $# -gt 0 ]; then
    echo "Usage ./cleanup DIR_TO_CATEGORIZE"
    exit 1
fi

##Read the database
viddb="cat $viddb_location"
seriedb="cat $seriedb_location"

## Generate database
echo -ne "Generating database...\r"
ls $vid_target_location > $seriedb_location
echo "Database generated..."

## Start looping over script parameters
for arg in "$@"; do

    ###If the argument is a directory call script recursively
    if [ -d "$arg" ]; then 
        find "$arg" -type f -exec $0 {} \;

        ## After each sctipt call cleanup is called so regen the db
        echo -ne "Regenerating database...\r"
        ls $vid_target_location > $seriedb_location
        echo "Database regenerated..."
        continue
    fi

    ###If the argument is not valid
    if [ ! -f "$arg" ]; then 
        echo "Parameter $arg is not a valid file."
        continue
    fi

    ##File name
    line=$(echo "$arg" | sed "s/.*\///")
    echo "Running for $line"

    ###Check extension
    valid_extensions=( avi mp4 mkv )
    extension=$(echo $line | sed 's/.*\.//')
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

    ## Find the S##E## in the file name
    season_ep=$(echo $line | sed 's/\.[^.]*$//' | sed 's/[^a-zA-Z0-9]/\n/g' | egrep -i 's|e' | sed 's/[^0-9]//g' | tr -d "\n")
    line_length=$(echo $season_ep | wc -L)

    ## Find the number of the line where the season is defined so all lines after that can be thrown away
    end_line_nr=$(echo $(echo $line | sed 's/[^a-zA-Z0-9]/\n/g'| egrep -in '(s|e)+.*[0-9]+' | cut -c1)-1|bc)

    ## If the found season is invalid try to detect it better
    if [ $line_length -gt 4 -o $line_length -lt 1 ]; then
        echo "Special season check running on $line"
        echo $season_ep
        season_ep=$(echo $line | sed 's/\.[^.]*$//' | sed 's/[^a-zA-Z0-9]/\n/g' | grep -vi '[^0-9]' | sed 's/[^0-9]//g' | tr -d "\n")
        line_length=$(echo $season_ep | wc -L)
        end_line_nr=$(echo $(echo $line | sed 's/[^a-zA-Z0-9]/\n/g'| egrep -in '^[0-9]+$' | sed 's/:.*$//')-1|bc)
        echo "Special season check over"
    fi

    ## If a season and ep is found then
    if [ $line_length -lt 5  -a $line_length -gt 0 ]; then

        ## Isolate season and episode number seperatly
        season=$(echo $season_ep | cut -c 1)
        episode=$(echo $season_ep | cut -c 2-3)
        if [ $line_length -eq 4 ]; then
            episode=$(echo $season_ep | cut -c 3-4)
            season=$(echo $season_ep | cut -c 1-2)
        fi

        ## Remove start 0's
        episode=$(echo $episode | sed 's/^0*//')
        season=$(echo $season | sed 's/^0*//')
        echo "Season: $season Episode: $episode"
        serie_name=$(echo $line | sed 's/[^a-zA-Z0-9]/\n/g'| head -$end_line_nr | tr "\n" " " | sed 's/ *$//')
        echo $serie_name

        ## Look is the serie exists already; write possible matches to file
        echo "$($seriedb | grep --ignore-case "$serie_name")" > "$tmp_location.found_ser"

        nr_matches=$(cat "$tmp_location.found_ser" | grep -vc '^$')
        if [[ $nr_matches == 0 ]]; then
            echo $serie_name |tr " " "\n" | sed  "s/the\|and//I" | sed "/ +$/d"| xargs -I "{}" grep -i "{}" $seriedb_location >> "$tmp_location.found_ser"
        fi

        ## Number of matches in the current vid target dir
        nr_matches=$(cat "$tmp_location.found_ser" | grep -vc '^$')

        ## If there are no matches in the current vid target dir
        if [[ $nr_matches == 0 ]]; then
            # Ask to create a new serie
            new_series $serie_name $season $line $arg
            if [ $? == 1 ]; then
                new_movie $line $arg
            fi
            continue
        fi
        echo "Found $nr_matches matches: "
        echo $serie_name

        # Display all possible matches numbered
        nl "$tmp_location.found_ser"
        # This is required in the while loop
        nr_chosen="0"

        # If there is more then one match
        if [ "$nr_matches" -gt 1 ]; then
            while [ "$nr_chosen" -lt 1 -o "$nr_chosen" -gt "$nr_matches" ]; do

                # Request to choose between possible matches
                echo "Enter 1 to $nr_matches:"
                read nr_chosen
                if [ "$nr_chosen"="" ]; then
                    nr_chosen="0"
                fi

            done
        else
            nr_chosen=1
        fi

        target_serie_name=$(cat $tmp_location.found_ser | sed -n $(($nr_chosen + 1))'p')
        folder="$vid_target_location$target_serie_name/Season $season/"
        echo "Moving to $folder$line"
        if [ ! -e "$folder" ];then
            echo "Making dir $folder"
        fi
        echo "Confirm? [Y/n]"
        if [ $(confirm) ];then
            if [ ! -e "$folder" ];then
                mkdir "$folder"
            fi
            mv "$arg" "$folder$line"
        else
            new_series "$serie_name" "$season" "$line" "$arg"
        fi
    else
        echo "No season detected for file $arg"
        new_movie "$line" "$arg"
    fi  
    echo "--------"
done
cleanup
