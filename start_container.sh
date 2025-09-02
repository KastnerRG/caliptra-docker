export HOSTNAME_VAR=${USER:2:3}
export UID=$(id -u)
export GID=$(id -g)

xhost +Local:docker
docker compose up -d --remove-orphans
# docker compose build --no-cache
docker exec -it caliptra-${USER} bash