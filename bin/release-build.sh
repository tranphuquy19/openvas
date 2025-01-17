#!/bin/bash
tag=$1
if [ -z $tag ] ; then
	tag="latest"
else
	tag="$tag"
fi
set -Eeuo pipefail
echo "Building with tag $tag"

docker buildx build --push --platform linux/amd64,linux/arm64 -f Dockerfile -t immauss/openvas:$tag .

docker rm -f $tag
docker pull immauss/openvas:$tag
docker run -d --name $tag immauss/openvas:$tag 
docker logs -f $tag

