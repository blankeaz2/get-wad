#!/bin/bash
#
# This script offers a simple search interface for downloading wads/mods from the idgames archive
#
# Example:
# $ bash ./get-wad.sh
# $ bash ./get-wad.sh neis
#
which jq > /dev/null || { echo 'Could not find jq'; exit 2; }
which fzf > /dev/null || { echo 'Could not find fzf'; exit 2; }

export download_dir="${GET_WAD_DOWNLOAD_DIR:-$HOME/get-wad}"
export api_url='https://www.doomworld.com/idgames/api/api.php'
export mirrors=$'https://youfailit.net/pub/idgames\nhttps://www.quaddicted.com/files/idgames\nhttps://ftpmirror1.infania.net/pub/idgames'

initial() {
	response=$(curl -N -s $api_url'?action=latestfiles' \
		--data 'limit=20' \
		--data 'out=json' \
	)
	[ $(echo $response | jq 'has("content")') = true ] || return

	while IFS= read -r id; do
		curl -N -s "$api_url?action=get" \
			--data-urlencode "id=${id:1:${#id}-2}" \
			--data 'out=json' \
		| jq '.content | "\(.dir)\(.filename)"'
	done <<< $(echo $response | jq '.content.file | if type=="array" then .[] else . end | "\(.id)"')
}
export -f initial

search() {
	local query=$(echo "$1" | sed -e 's/^["'\'']//' -e 's/["'\'']$//') # remove quotes from fzf

	if [ ${#query} -lt 3 ]; # not enough characters to search yet
	then
		initial
	else
		while IFS= read -r type; do
			local response=$(curl -N -s $api_url'?action=search' \
				--data-urlencode "query=$query" \
				--data "type=$type" \
				--data 'sort=date' \
				--data 'dir=desc' \
				--data 'out=json' \
			)
			[ $(echo $response | jq 'has("content")') = true ] || continue

			local parsed_response=$(echo $response \
				| jq '.content.file 
						| if type=="array" then .[] else . end 
						| "\(.dir)\(.filename)|title: \(.title)<br>filename: \(.filename)<br>author: \(.author)"
						| gsub( "`"; "\\\\`")
						| gsub( "'\''"; "\\'\''")')
			local remote_filepaths=$(echo -e "$parsed_response" | cut -d '|' -f 1 | cut -c2-)
			local best_matches=$(echo -e "$parsed_response" \
				| cut -d '|' -f 2- \
				| rev | cut -c2- | rev \
				| xargs -n1 -I {} bash -c 'echo "{}" | awk "$1" | grep -m 1 "$0"' "^$type:" 'BEGIN {IGNORECASE=1; RS="<br>"} { print $0 }')

			paste -d '|' <( printf "$remote_filepaths" ) <( printf "$best_matches" )
		done < <(printf "title\nfilename\nauthor\n")
	fi
}
export -f search

preview() {
	local path=$(echo "$1" | sed -e 's/^["'\'']//' -e 's/["'\'']$//' | cut -d '|' -f 1) # remove quotes from fzf and truncate match
	echo "[$path]"

	response=$(curl -N -s "$api_url?action=get" \
		--data-urlencode "file=$path" \
		--data 'out=json' \
	)
	[ $(echo $response | jq 'has("content")') = true ] || return

	echo $response | jq '.content.textfile' | sed -e 's/^["'\'']//' -e 's/["'\'']$//' -e 's/\\\"/\"/g' | xargs --null -I {} printf "{}"
}
export -f preview

download() {
	local path=$(echo "$1" | sed -e 's/^["'\'']//' -e 's/["'\'']$//' | cut -d '|' -f 1) # remove quotes from fzf and truncate match
	local file="$(basename $path)"
	# add a hash at the end to handle the same filename in different dirs
	local extract_dir="${file%.*}-$(echo $path | sha1sum | head -c 5)"

	if [ ! -d "$download_dir/$extract_dir/" ];
	then
		if [ ! -f "$download_dir/$file" ];
		then
			while IFS= read -r mirror; do
				[ ! -f "$download_dir/$file" ] && wget -P "$download_dir" "$mirror/$path"
			done <<< "$mirrors"
		fi

		if [ -f "$download_dir/$file" ];
		then
			unzip "$download_dir/$file" -d "$download_dir/$extract_dir/" && rm "$download_dir/$file"
		else
			echo "Failed to download: $path"
		fi
	else
		echo "Already exists: $download_dir/$extract_dir/"
	fi
}
export -f download

# have a slight delay to allow for the next keystroke
FZF_DEFAULT_COMMAND="search '$@'" fzf --bind 'change:reload(sleep 2e-1; search "{q}")' --bind 'enter:execute(download "{}")+abort' --preview 'preview {}' --ansi --query="$*"
