#!/bin/sh
set -e
cd /opt/status-page/statuspage/

# [cite_start]Create the configuration.py file from secrets/environment variables [cite: 123, 143, 168, 193]
echo "
ALLOWED_HOSTS = ['*']

DATABASE = {
    'NAME': '${DATABASE_NAME}',
    'USER': '${DATABASE_USER}',
    'PASSWORD': '${DATABASE_PASSWORD}',
    'HOST': '${DATABASE_HOST}',
    'PORT': '5432',
    'CONN_MAX_AGE': 300,
}

REDIS = {
    'tasks': { 'HOST': '${REDIS_HOST}', 'PORT': 6379, 'PASSWORD': '', 'DATABASE': 0, 'SSL': False },
    'caching': { 'HOST': '${REDIS_HOST}', 'PORT': 6379, 'PASSWORD': '', 'DATABASE': 1, 'SSL': False }
}

SECRET_KEY = '${SECRET_KEY}'
" > ./statuspage/configuration.py

echo "Configuration file created."

# [cite_start]Apply database migrations [cite: 215]
python3 manage.py migrate --noinput
echo "Database migrations complete."

# [cite_start]Collect static files [cite: 216]
python3 manage.py collectstatic --noinput --clear --outputpath /opt/status-page/static_files
echo "Static files collected."

exec "$@"
