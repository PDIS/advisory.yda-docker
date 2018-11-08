#!/bin/bash
export YDA_SESSION=$(printf "%02d" $1)
export YDA_SESSION_NAME=yda-$YDA_ALIAS_$YDA_SESSION
export YDA_ROOT=/usr/local/yda
export YDA_DIR=$YDA_ROOT/session
export YDA_ALIAS_DIR=$YDA_DIR/$YDA_SESSION_NAME
export RND_PASS=$(pwgen -s 20)
export YDA_NGINX_PATH=$YDA_ROOT/nginx
export YDA_NGINX_CONF_PATH=$YDA_NGINX_PATH/conf.d
export YDA_NGINX_SESSION_CONF=$YDA_NGINX_CONF_PATH/yda/$YDA_SESSION_NAME.conf
export RUN_DIR=$(pwd)

if [ $YDA_SESSION == "00" ]; then
    echo "Session Number must greater than 1"
    exit 1
fi

if [ -d $YDA_ALIAS_DIR ]; then
    echo "docker volume $YDA_ALIAS_DIR exist abort create action"
    exit 1
fi

if [ ! -f env.template ]; then
    echo "env.template file not found. please follow README.md to deploy"
    exit 1
fi

docker network ls | grep host > /dev/null
if [ $? -eq 1 ]; then
    echo "docker network nginx not exist. please create first"
    exit 1
fi


echo "Perpare persistent folders"
mkdir -p $YDA_ALIAS_DIR
mkdir -p $YDA_ALIAS_DIR/storage
mkdir -p $YDA_ALIAS_DIR/storage/app
mkdir -p $YDA_ALIAS_DIR/storage/logs

echo "Perpare persistent files"
touch $YDA_ALIAS_DIR/storage/database.sqlite
cp env.template $YDA_ALIAS_DIR/.env
cp docker-compose.yml $YDA_ALIAS_DIR/docker-compose.yml

cd $YDA_ALIAS_DIR
echo "adjust compose variable"
sed -i "s/SQL_PASSWORD/$RND_PASS/g" .env
sed -i "s/^\(APP_KEY=\).*/\1$(pwgen -s 32)/" .env

echo "build dockers"
docker-compose build
docker-compose up -d

echo "Waiting 15 second for MySQL Service is Active...."
sleep 15

echo "run post command"
echo "docker-compose post work"
docker-compose exec web mkdir -p /var/www/html/storage/app/media
docker-compose exec web touch -d '1 Jan 2018 00:00' /var/www/html/storage/app/media/gpvip.csv
docker-compose exec web php artisan october:up
docker-compose exec web php artisan theme:use responsiv-flat-test
docker-compose exec web php artisan key:generate
docker-compose exec web php artisan config:clear
docker-compose exec web php artisan config:cache
docker-compose exec web php artisan cache:clear
docker-compose exec web chown -R www-data:www-data /var/www/html/storage

echo "add web to nginx network"
docker network connect nginx $YDA_SESSION_NAME-web

echo "modify web configs"
docker cp $YDA_SESSION_NAME-web:/var/www/html/.htaccess /tmp/.htaccess
sed -i "s/# RewriteBase \//RewriteBase \/$YDA_SESSION/g" /tmp/.htaccess
docker cp /tmp/.htaccess $YDA_SESSION_NAME-web:/var/www/html/.htaccess
rm -f /tmp/.htaccess
docker cp $YDA_SESSION_NAME-web:/etc/apache2/sites-available/000-default.conf /tmp/000-default.conf
sed -i "1a\ \ \ \ \ \ \ \ Alias \"\/$YDA_SESSION\" \"\/var\/www\/html\"" /tmp/000-default.conf
docker cp /tmp/000-default.conf $YDA_SESSION_NAME-web:/etc/apache2/sites-available/000-default.conf
rm -f /tmp/000-default.conf
docker exec $YDA_SESSION_NAME-web service apache2 reload

echo "deploy nginx config"
cd $RUN_DIR
if [ ! -f $YDA_NGINX_CONF_PATH/yda-default.conf ]; then
    cp nginx-yda-default $YDA_NGINX_CONF_PATH/yda-default.conf
fi
mkdir -p $YDA_NGINX_CONF_PATH/yda

cp nginx-yda.template $YDA_NGINX_SESSION_CONF
sed -i "s/SESSION_NUMBER/$YDA_SESSION/g" $YDA_NGINX_SESSION_CONF
docker exec nginx-reverse_proxy service nginx reload
