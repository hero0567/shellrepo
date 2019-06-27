#!/bin/bash

update_list=()
add_needed_upload_domain_list(){
    if check_with_artifactory $1; then
        echo "$1 already existed, will skip upload this time."
    else
        echo "$1 not found."
        update_list=(${update_list[@]} $1)
    fi
}

check_with_artifactory(){
    response=$(curl -X POST -k -H 'Content-Type: text/plain' -H 'Authorization: Basic Z2xvYmFsLXJlYWRlcjp2Uk4kMm5BaEZnZVpyRko9' -i 'https://artifactory-dmz.dev.nuancemobility.net:443/artifactory/api/search/aql' --data 'items.find(
                            {
                                "type": "file","repo":{"$eq":"mpdss-generic"},"name":{"$eq":"'$1'"}
                            }
                        )')
    echo $response | grep $1 || return 1;
    return 0
}

run_mpdss_import_date(){

    for name in ${update_list[@]};do
        name=${name%%.*}
        echo $name
        ENABLE_DOMAIN=$ENABLE_DOMAIN"-Dmpdss.${name}.enabled=true "
    done
    
    EVN_MPDSS_OPT_5="$ENABLE_DOMAIN"
    echo "Enabled domain:" $EVN_MPDSS_OPT_5    
    
    echo "Start mpdss application."
    echo "Remove image raw data, Do not need index to artifactory."
    rm -rf $USER_HOME/mpdss/mpdss-solr/target/mpdss-solr-*/mpdss-solr/etc/data/banma
    rm -rf $USER_HOME/mpdss/mpdss-solr/target/mpdss-solr-*/mpdss-solr/etc/data/banma_core
    rm -rf $USER_HOME/mpdss/mpdss-solr/target/mpdss-solr-*/mpdss-solr/etc/data/banma_media
    
    echo "Copy index raw data."
    /bin/cp -rf $USER_HOME/rawdata/* $USER_HOME/mpdss/mpdss-solr/target/mpdss-solr-*/mpdss-solr/etc/data/
           
    java -jar -Dlog4j.configuration=file:$MPDSS_LAUCHER_PATH/config/log4j.docker.properties -Dwatcher.enabled=false \
        ${EVN_MPDSS_OPT_3} ${EVN_MPDSS_OPT_4} ${EVN_MPDSS_OPT_5}\
        $MPDSS_LAUCHER_PATH/lib/mobility-launcher-2.0.jar -wd $MPDSS_LAUCHER_PATH http.alarm.sender.enabled=false stdout.alarm.sender.enabled=true snmp.alarm.sender.enabled=false watcher.alarm.sender.enabled=false &
        
    while ([ "$http_code"x != "200"x ]); do
        sleep 30;  
        http_code=`curl -I -m 10 -o /dev/null -s -w %{http_code} http://localhost:8665/rest/dcs/status/isReady`    
        echo "MPDSS check status $http_code"    
    done

    echo "Import task successful"   

}

tar_and_upload_to_artifactory(){
    echo "tar and upload to artifactory."
    pwd
    ls
    cd $USER_HOME/mpdss/mpdss-solr/target/mpdss-solr-*/mpdss-solr/etc/solr/data/
    echo "List all index folders."
    ls
    for name in ${update_list[@]};do
        folder_name=${name%%.*}    
        echo "tar czvf $name $folder_name"
        if [ $folder_name == "poicorrection" ]; then
            tar -czvf rawdata.tar.gz * --exclude=*-* --exclude=*.tar.gz
        elif [ $folder_name == "ctripHotel" ]; then
            tar czvf $name cmn-CHN
        else
            tar czvf $name $folder_name
        fi
        
        if [ $? -eq 0 ]; then
            echo "upload $name to artifactory"
            curl -u ${User_AzureUS2}:${Passwd_AzureUS2} $TARGET_ARTIFACTORY$name -T  $name
            #curl -u "promoter:c?F&-=aPjUSN#4F$" https://artifactory.test.mcs.chengdu.mob.nuance.com/artifactory/mpdss-generic/mpdsssolr/release/packs/packs/$name -T  $name
        else
            echo "Failed to compress folder."
            exit 1
        fi
    done
}

main(){
    #Step 1
    echo "##### 1.1 Read version and check #####"
    while read INDEX_FILE || [[ -n ${INDEX_FILE} ]]; do
        echo "Try to check with: " $INDEX_FILE
        add_needed_upload_domain_list $INDEX_FILE
    done < $VERSION_FILE

    echo "Found upload list ${update_list[@]}"
    echo "Run mpdss docker and import raw data to index."
    if [ ${#update_list[@]} -gt 0 ];then
        #Step 2
        echo "##### 2.1 Run mpdss and import raw data #####"
        run_mpdss_import_date
        #Step 3
        echo "##### 3.1 Tar index folder and upload to artifactory #####"
        tar_and_upload_to_artifactory
    else
        echo "Job finished. No data need to upload."
        exit 0;
    fi

    #End Step 4
    echo "##### 4.1 Job finished. Success upload index data. #####"
    
    exit 0;
}

echo "Start mpdss upload task."
main

