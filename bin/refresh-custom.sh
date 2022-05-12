#!/bin/bash
# This script will refresh the data in the openvas docker image on dockerhub
# It will include a new db dump and the contents of /data/var-lib
# This should run from a cron with a long enough sleep to make sure
# the gvmd has updated the DB before creating the archive and pushing
# to github. It's probably not going to be useful to anyone but me
# but the output will benefit all. 

# First, make sure there's enough storage avaialbe before doing anything.
#SPACE=$(df -h /var/lib/docker | awk /G/'{print $4}' | sed "s/G//")
#if [ -n $SPACE ]; then
	#echo "Check available storage"
	#exit
#elif [ $SPACE -le 4 ]; then
	#echo "only ${SPACE}G of space on /var/lib/docker ... bailing out."
	#exit
#fi

while ! [ -z "$1" ]; do
  case $1 in
        -t)
        shift
        TAG=$1
        shift
        ;;
	-b)
	shift 
	BUILD_BRANCH=$1
	shift
	;;
        -p)
        echo " Flushing build kit cache"
        docker buildx prune -af
        shift
        ;;
	*)
	echo -e " Unrecognized option $1"
	echo -e " -p\t\tFlush Build Kit cache"
	echo -e " -t <TAG>\tSet build tag.(default latest)"
	echo -e " -b <BRANCH>\tSet git branch to build from.(default master)"
	echo -e " -h\t\tThis text"
	exit
	;;

  esac
done
# Tag & branch to work with. Normally latest/master but might be using new tag during upgrades.
if [ -z $TAG ]; then
	TAG="latest"
fi
if [ -z $BUILD_BRANCH ]; then
	BUILD_BRANCH="master"
fi
# Make sure we are on the right branch before doing anything.
cd ~/Projects/openvas
BRANCH=$(git branch | awk /\*/'{print $2}')
if [ $BRANCH != "$BUILD_BRANCH" ]; then
	echo " NOT on branch $BUILD_BRANCH " 
	echo " NOT rebuilding !!"
	echo " Fix it and try again"
	exit
fi

# Temp working directory ... needs enough space to pull the entire feed and then compress it. ~2G
TWD="/var/lib/openvas"
STIME="40m" # time between resync and archiving.
# Force a pull of the latest image.
# docker pull immauss/openvas:$TAG
echo "Starting container for an update"
docker run -d --name updater openvas:21.4.4
if [ $? -ne 0 ];then
	echo " Failed to start ... ^^" 
	exit
fi
date
echo "Sleeping for $STIME to make sure the feeds are updated in the db"
sleep $STIME
CONTINUE=0
COUNTER=0
while  [ $CONTINUE -eq 0 ] && [ $COUNTER -le 20 ]; do
	if docker logs updater 2>&1 | grep -qs "update_nvt_cache_retry: rebuild successful"; then
		CONTINUE=1
		echo "looks like it's done"
	else
		echo "Not done yet."
	fi
	COUNTER=$( expr $COUNTER + 1)
	sleep 1m
done

if [ $COUNTER -gt 20 ]; then
	logger -t db-refresh "Waited for succes in logs for > 20m. This might fail"
fi

cd $TWD
echo "First copy the feeds from the container"
docker cp updater:/data/var-lib .
echo "Now dump the db from postgres"
docker exec -i updater su -c "/usr/lib/postgresql/12/bin/pg_dumpall" postgres > ./base.sql 

echo "Stopping update container"
docker stop updater
echo "Dumping container logs to /var/log/refresh.log"
date >> /var/log/refresh.log
docker logs updater >> /var/log/refresh.log
docker rm updater

echo "Compress and archive the data"
tar cJf var-lib.tar.xz --exclude=var-lib/gvm/gvmd/gnupg var-lib
xz -1 base.sql
SQL_SIZE=$( ls -l base.sql.xz | awk '{print $5}')
FEED_SIZE=$( ls -l var-lib.tar.xz | awk '{print $5'})
if [ $SQL_SIZE -le 2000 ] || [ $FEED_SIZE -le 2000 ]; then
	logger -t db-refresh "SQL_SIZE = $SQL_SIZE : FEED_SIZE = $FEED_SIZE: Failing out"
	exit
fi

# Need error checking here to prevent pushing a nil DB.
scp *.xz push@www.immauss.com:/var/www/html/drupal/openvas/
if [ $? -ne 0 ]; then
	logger -t db-refresh "SCP of new db failed $?"
	exit
fi


# Now rebuild the image
cd ~/Projects/openvas
echo "Pulling latest from github"
git pull
if [ $? -ne 0 ]; then
	echo "git pull failed. Rebuild image manually: $?"
	exit
fi
date > update.ts
git commit update.ts -m "Data update for $Date"
echo "And pushing to github"
git push 

#Build new image here
#docker build -t immauss/openvas:latest .
# docker buildx build -t openvas:21.4.4 --platform linux/arm64,linux/amd64 --push .
docker buildx build -t openvas:21.4.4 --platform linux/arm64,linux/amd64 .
if [ $? -ne 0 ]; then
	echo "Build failed."
	exit
fi

echo "Cleaning up"
cd $TWD
rm -rf *
echo "All done"


