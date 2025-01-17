if [ -z $1 ]; then
	TAG="latest"
else 
	TAG="$1"
fi

docker pull immauss/openvas:${TAG}
docker rm -f ${TAG}-test
docker run -d -p 8080:9392 --name "${TAG}-test" -e SKIPSYNC=true immauss/openvas:${TAG}
docker logs -f "${TAG}-test"
