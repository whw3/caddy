#!/bin/bash
clear
BASEDIR=$(cd "$( dirname "$0" )" && pwd)
cd "$BASEDIR"
datadir="$BASEDIR/data/srv"
rootfs="$BASEDIR/rootfs"
dataExists=0
function check_prereqs()
{ ### check pre-requisittes
    if  [[ -z "$(which jq)" ]]; then
        whiptail --title "Missing Required Application" --yesno "jq is required for this script to function.\nShould I install it for you?" 8 48 3>&1 1>&2 2>&3 || exit 1
        apt-get update
        apt-get install -y jq
    fi
    if  [[ -z "$(which docker-compose)" ]]; then
        whiptail --title "Missing Required Application" --yesno "docker-compose is required for this script to function.\nShould I install it for you?" 8 48 3>&1 1>&2 2>&3 || exit 1;
        apt-get -y install python-pip
        pip install pip --upgrade
        apt-get -y remove python-pip
        pip install docker-compose
        pip install -U requests==2.11.1
    fi
}
function check_data()
{
    if [ ! -d "$datadir" ]; then #create
        mkdir -p "$datadir"/{caddy,services.d,htdocs}
        cd "$datadir"
        cp -a "$rootfs"/etc/services.d/* "$datadir"/services.d/
        cat << EOF > init.sh
#!/bin/bash
find /srv/services.d/ -type f -exec chmod +x {} \;
cp -a /srv/services.d/* /etc/services.d/
chown -R root:www-data /srv
chmod g+s /srv
if [[ ! -z "\$PHP_INI_DIR"]]
    TZ=''
    [[ -r /etc/timezone ]] && TZ=\$(</etc/timezone)
    [[ ! -z "\$TZ" ]] && echo "date.timezone = \"\$TZ\"" > "\$PHP_INI_DIR"/php-fpm.d/timezone.conf
fi
EOF
        cat << EOF > setPerms.sh
#/bin/bash
cd /srv/htdocs
chown -R root:www-data /srv/htdocs/*
find -type d -exec chmod 0750 {} \;
find -type f -exec chmod 0640 {} \;
EOF
        chmod a+x init.sh setPerms.sh
        cp "$rootfs"/etc/Caddyfile "$datadir"/caddy/
        cp "$BASEDIR"/index.html "$datadir"/htdocs/
    else #look for updated files
        export dataExists=1
        cp -u "$rootfs"/etc/Caddyfile "$datadir"/caddy/
        cp -u "$BASEDIR"/index.html "$datadir"/htdocs/
        cp -u -a "$rootfs"/etc/services.d/* "$datadir"/services.d/
    fi
    cd "$BASEDIR"
}
function update_baseimages()
{
    docker pull whw3/alpine:latest
    docker pull whw3/php:fpm-alpine
}
function reset_json()
{
    echo "["
    awk -F' ' '{ print "{\"name\":\"" $1 "\",\"import\":\"" $2 "\",\"status\":\"off\"},"}' plugins.txt| sort | sed '$s/,$//'
    echo "]"
}
function check_json()
{
    if [ ! -r plugins.json ]; then
        reset=1
    elif [[ "$(jq -e '.[]' plugins.json > /dev/null 2>&1 )" ]]; then
        reset=1
    elif [[ -z "$(jq '.[]' plugins.json )" ]]; then
        reset=1
    else
        reset=0
    fi
    if [ "$reset" = "1" ]; then
        reset_json > plugins.json
    fi    
}
function select_plugins()
{
    local _plugList=( $(jq -r '.[]|"\(.name) \(.status)"' plugins.json) )
    local _plugins=$(whiptail --title "Select Plugins" --clear --checklist --noitem --separate-output "" 30 38 22 "${_plugList[@]}" 3>&1 1>&2 2>&3)||exit 1
    echo "$_plugins"
}
function update_plugins()
{
    local _plugin
    local _index=0
    printf "export plugins=\""
    for _plugin in "${plugins[@]}"
    do
        printf "%s" "$_plugin"
        [[ "$_index" -lt "${#plugins[@]}" ]] && printf " "
        ((++_index))
    done
    printf "\"\n"
}
### MAIN ###
check_prereqs
check_data
update_baseimages
check_json
plugins=($(select_plugins))
if [[ -z "${plugins[@]}" ]]; then
    if (whiptail --title "Confirm No plugins selected" --yesno "Should I really write an empty import file?" 8 78) then
        update_plugins > plugins
    else
        if [[ -e plugins ]]; then
            echo "Leaving plugins.go unmodified"
        fi
    fi
else
    update_plugins > plugins
fi
if [[ ! -e plugins ]]; then
    clean="$BASEDIR/clean.sh"
    if [[ "$dataExist" = "0" ]]; then
        clean+=" -p data"
    fi
    $clean
    echo "Terminated in an unconfigured state."
    exit 1
fi
exit 0
