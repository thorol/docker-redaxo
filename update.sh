#!/bin/zsh
set -euo pipefail


# What is this update.sh?
# It's a helper script you run whenever you've updated the REDAXO version or modified the Docker setup.
# It generates all the Dockerfiles from templates and the post_push hooks containing image tags.
# Once you commit and push the changes, Docker Hub will trigger automated builds of new images.

# Usage:
# `./update.sh`
# As you can see in line 1, the script runs in zsh. This is the default shell in Mac OS since Catalina.
# You could run it in a bash shell as well (`#!/bin/bash`), but it requires at least bash 4.x to deal
# with associative arrays (hash tables). Check your version with `bash --version`.


# configuration ---------------------------------------------------------------

# define latest REDAXO release
# hint: we could curl the latest release from github instead but wouldn't receive the sha1 checksum.
# That's why we write it down here after we generate it like this:
# `curl -Ls https://github.com/redaxo/redaxo/releases/download/5.15.0/redaxo_5.15.0.zip | shasum`
latest=5.15.0
sha1=ffa10aaab01ffc39425ec31e15c00ec96d948db9

# declare PHP versions
phpVersions=( 8.2 8.1 )
defaultPhpVersion='8.1'

# declare image variants (like: apache, fpm, fpm-alpine)
variants=( apache fpm )
defaultVariant='apache'

# declare commands and image bases for given variants
declare -A cmds=(
    [apache]='apache2-foreground'
    [fpm]='php-fpm'
)
declare -A bases=(
    [apache]='debian'
    [fpm]='debian'
)
declare -A variantExtras=(
	[apache]="$(< templates/apache-extras)"
)

# -----------------------------------------------------------------------------

# get the tree of a given version string
# example: 5.8.1 returns as 5.8.1, 5.8 and 5.
getVersionTree () {
    # check for version format X, X.X or X.X.X
    # we skip any beta or other versions!
    if [[ $1 =~ ^(0|[1-9][0-9]*)(\\.(0|[1-9][0-9]*))?(\\.(0|[1-9][0-9]*))?$ ]]; then
        version=$1
        for (( i=1; i<=3; i++ )); do
            if [ $i -gt 1 ]; then
              versionTree+=($version)
            fi
            version="${version%\.*}"
        done
        echo $versionTree
    fi
}

# escape special chars to use with sed
sed_escape_rhs() {
	sed -e 's/[\/&]/\\&/g; $!a\'$'\n''\\n' <<<"$*" | tr -d '\n'
}

# bring out debug infos
echo "REDAXO $latest"

# loop through given PHP versions
for phpVersion in "${phpVersions[@]}"; do
    phpVersionDir="php$phpVersion"

    # loop through image variants
    for variant in "${variants[@]}"; do

        # declare and make directory for given PHP version and image variant
        dir="$phpVersionDir/$variant"
        mkdir -p "$dir"

        # declare cmd and base for current version
        cmd="${cmds[$variant]}"
        base="${bases[$variant]}"

        # declare extras for current variant
        extras="${variantExtras[$variant]:-}"

        # declare tags for current version and variant
        tags=()
        versions=( $(getVersionTree $latest) )
        for version in "${versions[@]}"; do

            # add specific version strings (like: `5.8.1-php7.2-apache`)
            tags+=("${version}-${phpVersionDir}-${variant}")

            # add generic tags for default variant and PHP version (like: `5.8.1`, `5.8`, `5`)
            if [[ $variant == $defaultVariant ]] && [[ $phpVersion == $defaultPhpVersion ]]; then
                tags+=("${version}")
            fi
        done

        # bring out debug infos
        echo "- Image: PHP $phpVersion $variant [base: $base] [cmd: $cmd]"
        echo "  Tags:"
        printf "  - %s\n" ${tags}

        # generate Dockerfile from template, replace placeholders
        sed -r \
            -e 's!%%REDAXO_VERSION%%!'"$latest"'!g' \
            -e 's!%%REDAXO_SHA1%%!'"$sha1"'!g' \
            -e 's!%%PHP_VERSION%%!'"$phpVersion"'!g' \
            -e 's!%%VARIANT%%!'"$variant"'!g' \
            -e 's!%%VARIANT_EXTRAS%%!'"$(sed_escape_rhs "$extras")"'!g' \
            -e 's!%%CMD%%!'"$cmd"'!g' \
            "templates/Dockerfile-${base}" > "$dir/Dockerfile"

        # Use placeholder for `sed -i` due to differences between GNU and BSD/Mac
        # https://stackoverflow.com/a/51060063
        # GNU
        sedi=(-i)
        case "$(uname)" in
          # macOS
          Darwin*) sedi=(-i "")
        esac

        # copy hook from template, replace placeholders
        mkdir -p "$dir/hooks"
        sed -r \
            -e 's!%%TAGS%%!'"$tags"'!g' \
            "templates/post_push.sh" > "$dir/hooks/post_push"

        # copy entrypoint file
        cp -a templates/docker-entrypoint.sh "$dir/docker-entrypoint.sh"
        chmod +x "$dir/docker-entrypoint.sh"

    done
done
