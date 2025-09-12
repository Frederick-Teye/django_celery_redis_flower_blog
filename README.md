Welcome to this tutorial project! In this guide, we will learn how to set up a powerful web application using Django, Celery, Redis, and Flower, all orchestrated with Docker. Our goal is to create a web crawler that efficiently gathers data from the web.

We'll start from scratch, ensuring that even those new to these technologies can follow along. Throughout the tutorial, I will strive to keep the information clear and engaging while providing the necessary details to understand each component.

Here’s what you can expect:

- Setting up your development environment with Docker.

- Building a Django application from the ground up.

- Integrating Celery for asynchronous task management.

- Using Redis as our message broker.
  Monitoring tasks with Flower.

- Simple configuration of Nginx and Gunicorn in order to deploy the app to AWS and access it over the DNS of the EC2 instance on which it will be hosted. I'm broke, so that is why we won't be able to see how to do a full configuration with Let's Encrypt and a Domain name.

## Downloading and installing Django

Open the terminal and follow the following steps:

1. Create directory named django_celery_redis_tutorial:

```bash
mkdir django_celery_redis_tutorial
```

2. Navigate into that directory:

```bash
cd django_celery_redis_tutorial
```

3. Create a virtual environment:

```bash
python3 -m venv .venv
```

4. Activate virtual environment:

```bash
source .venv/bin/activate
```

5. Install Django:

```bash
pip install django
```

6. Create django project named core:

```bash
django-admin startproject core .
```

7. Run django

```bash
python manage.py runserver
```

8. Copy this url and paste in your browser:

```bash
http://localhost:8000
```

9. Stop the server and deactivate the virtual environment:

   a. press `Crtl + Z`

   b. Create a requirements.txt file with django version installed in it:

   ```bash
   echo $(django-admin --version) > requirements.txt
   ```

   c. copy and paste the command below and press enter:

   ```bash
   deactivate
   ```

   d. Create static/ directory:

   ```bash
   mkdir static
   ```

10. Populate the requirements.txt file:

```bash
echo -e "celery==5.5.3
beautifulsoup4==4.13.4
python-decouple==3.8
redis==5.3.0
requests==2.32.5
psycopg2-binary
flower" >> requirements.txt
```

## Setting Up Docker

At this point, you need Docker installed on your machine, if you don't have it, then head over to [https://docs.docker.com/get-started/get-docker/](https://docs.docker.com/get-started/get-docker/) to get it installed and continue with the following steps:

1. From this stage onwards, we don't need the virtual environment again, so let's go ahead and delete the .venv/ directory:

```bash
rm -r .venv
```

---

2. Let's create a Dockerfile:

```bash
touch Dockerfile
```

`Note for those who don't know what a Docker file is:` A [Dockerfile](https://docs.docker.com/reference/dockerfile/) is a text file that contains a set of instructions for building a Docker image. In simple terms, it acts like a recipe that tells Docker how to create an environment for our application.

---

3. At this point, you can choose to open your favorite IDE/text editor or open VSCode with the command:

```bash
code .
```

---

4. Open the Dockerfile and paste the code below into it:

```dockerfile
# --- Builder Stage ---
# This stage installs dependencies and builds the application
FROM python:3.11-slim-bookworm AS builder

# Set the working directory
WORKDIR /app

# Install system dependencies required for building Python packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    gettext \
    && rm -rf /var/lib/apt/lists/*

# Copy the requirements file and install Python dependencies
COPY requirements.txt .
RUN pip install --default-timeout=260 --no-cache-dir -r requirements.txt \
    -i https://pypi.org/simple

# --- Final Stage ---
# This stage creates the final, lean image for production
FROM python:3.11-slim-bookworm

# Set the working directory
WORKDIR /app

# Create a non-root user and group
RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser

# Copy installed packages from the builder stage
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy the application code
COPY . .

RUN mkdir -p /app/staticfiles && \
    chown -R appuser:appgroup /app/staticfiles

# Change ownership of the application directory to the new user
RUN chown -R appuser:appgroup /app

# Switch to the non-root user
USER appuser

# Expose the port the app runs on
EXPOSE 8000

# Run the entrypoint script
CMD ["/app/entrypoint.sh"]
```

Each instruction has been commented, so you should read through it and if you don't understand anything check [Dockerfile](https://docs.docker.com/reference/dockerfile/), or ask an AI to walk you through it. Our main focus is going to be on the celery worker, redis and Flower.

---

5. Let's go ahead and create `entrypoint.sh` script. This script waits for the database to be ready and then runs the main application command. Go ahead and run the command:

```bash
touch entrypoint.sh
```

Copy the code below and paste it into `entrypoint.sh`

```bash
#!/bin/sh

# The host and port for the database are read from environment variables.
DB_HOST=${DB_HOST:-db}
DB_PORT=${DB_PORT:-5432}
REDIS_HOST=${REDIS_HOST:-redis}
REDIS_PORT=${REDIS_PORT:-6379}

echo "Waiting for database at $DB_HOST:$DB_PORT..."

# Use Python to check port availability
while ! python -c "import socket; s = socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.settimeout(1); result = s.connect_ex(('$DB_HOST', $DB_PORT)); s.close(); exit(result)"; do
  sleep 0.1
done

echo "Database started"

# Wait for Redis
echo "Waiting for Redis at $REDIS_HOST:$REDIS_PORT..."
while ! python -c "import socket; s = socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.settimeout(1); result = s.connect_ex(('$REDIS_HOST', $REDIS_PORT)); s.close(); exit(result)"; do
  sleep 0.1
done
echo "Redis started"

# hand over control to whatever command was passed (from docker-compose.yml)
exec "$@"
```

Run the command below to give you permission to execute it when we run docker-compose.dev.yml in the future:

```sh
chmod +x ./entrypoint.sh
```

---

6. Let's go ahead and create `docker-compose.dev.yml`. A `docker-compose.yml` file is a configuration file used by Docker Compose, a tool that helps you define and manage multi-container Docker applications. In simple terms, it allows you to specify how different services (like databases, web servers, and application servers) should work together in a single application. Read more about `docker-compose.yml` at [https://docs.docker.com/compose/intro/compose-application-model/](https://docs.docker.com/compose/intro/compose-application-model/). You might be wondering why we are naming our `docker-compose.yml` `docker-compose.dev.yml`. We're doing this because we want to have one docker-compose.yml for development environment which will contain configuration for Flower and one for production environment which will contain configuration for Gunicorn and Nginx without configuration for Flower. So as the name clearly shows, `docker-compose.dev.yml` is for development environment. After populating this with code. We're going to create `docker-compose.prod.yml`.

   Use the command below to create docker-compose.dev.yml:

   ```bash
   touch docker-compose.dev.yml
   ```

   Populate it with the code below:

```yaml
version: "3.8"
services:
  # Django Web Application Service
  web:
    build: .
    command: >
      sh -c "python manage.py collectstatic --noinput &&
             python manage.py migrate &&
             python manage.py runserver 0.0.0.0:8000"
    volumes:
      - .:/app
      - static_data:/app/staticfiles
    user: appuser
    ports:
      - "8000:8000"
    # We use env_file to load the bulk of our settings like SECRET_KEY, DEBUG, etc.
    env_file:
      - .env
    environment:
      - SITE_DOMAIN=localhost:8000
      - SITE_NAME=SCRAPPER_Project
      - DJANGO_SETTINGS_MODULE=core.settings
    depends_on:
      - db
      - redis
    restart: on-failure
    networks:
      - app_network

  # Celery Worker Service
  celery_worker:
    build: .
    command: celery -A core worker -l info
    volumes:
      - .:/app
    env_file:
      - .env
    environment:
      CELERY_BROKER_URL: ${REDIS_URL}
      CELERY_RESULT_BACKEND: ${REDIS_URL}
    user: "appuser:appgroup"
    depends_on:
      - web
      - redis
    restart: on-failure
    networks:
      - app_network

  # Redis Service
  redis:
    image: redis:7-alpine
    restart: unless-stopped
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5
    networks:
      - app_network

  # Flower Service
  flower:
    build: .
    command: celery -A core flower --broker=${CELERY_BROKER_URL} --port=5555
    volumes:
      - .:/app
    env_file:
      - .env
    ports:
      - "5555:5555"
    depends_on:
      - redis
      - celery_worker
    networks:
      - app_network

  # PostgreSQL Database Service
  db:
    image: postgres:15-alpine
    volumes:
      - pg_data:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: ${DB_NAME}
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    ports:
      - "5432:5432"
    networks:
      - app_network

# Define named volumes for persistent data storage.
volumes:
  pg_data:
  redis_data:
  static_data:

# Define a custom bridge network for internal communication.
networks:
  app_network:
    driver: bridge
```

### Docker Compose Configuration Explanation

#### Services

##### web

- **build**: Specifies the build context for the Docker image, using the current directory (`.`).
- **command**: Supplies the development server process that the image’s ENTRYPOINT will exec (e.g. ["python","manage.py","runserver","0.0.0.0:8000"]).
- **volumes**:
  - Mounts the current directory to `/app` in the container.
  - Mounts a named volume `static_data` to `/app/static_cdn` for static files.
- **ports**: Maps port 8000 on the host to port 8000 in the container.
- **env_file**: Loads environment variables from a `.env` file.
- **environment**: Sets additional environment variables, including Redis URL, site domain, site name, and Django settings module.
- **depends_on**: Specifies dependencies on the `db` and `redis` services, ensuring they start before this service.
- **networks**: Connects the service to the `app_network`.

##### celery_worker

- **build**: Uses the same build context as the `web` service.
- **command**: Runs the Celery worker with the specified settings.
- **volumes**:
  - Mounts the current directory to `/app`.
  - Mounts a named volume `media_data` to `/app/media` for media files.
- **env_file**: Loads environment variables from the same `.env` file.
- **user**: Runs the container as a specific user and group (`appuser:appgroup`).
- **depends_on**: Ensures that the `web` and `redis` services are started before this service.
- **networks**: Connects to the `app_network`.

##### redis

- **image**: Uses the official Redis image (`redis:7-alpine`).
- **restart**: Configures the container to restart unless stopped manually.
- **ports**: Maps port 6379 on the host to port 6379 in the container.
- **volumes**: Mounts a named volume `redis_data` to `/data` for persistent storage.
- **healthcheck**: Defines a health check command to ensure Redis is running, with specified intervals and retries.
- **networks**: Connects to the `app_network`.

##### flower

- **image**: Uses the Flower image for monitoring Celery tasks (`mher/flower`).
- **command**: Runs Flower on port 5555.
- **ports**: Maps port 5555 on the host to port 5555 in the container.
- **depends_on**: Ensures that `redis` and `celery_worker` services are started before this service.

##### db

- **image**: Uses the official PostgreSQL image (`postgres:15-alpine`).
- **volumes**: Mounts a named volume `pg_data` to `/var/lib/postgresql/data` for database storage.
- **environment**: Sets environment variables for the database name, user, and password using values from the `.env` file.
- **ports**: Maps port 5432 on the host to port 5432 in the container.
- **networks**: Connects to the `app_network`.

#### Volumes

- **pg_data**: Named volume for PostgreSQL data.
- **redis_data**: Named volume for Redis data.
- **media_data**: Named volume for media files.
- **static_data**: Named volume for static files.

#### Networks

- **app_network**: A custom bridge network for internal communication between services.

---

7. Let continue with the creation of `docker-compose.prod.yml`. Please create the file by running the command below:

```bash
touch docker-compose.prod.yml
```

Now copy the code below and paste it in the `docker-compose.prod.yml` file:

```yaml
services:
  web:
    build: .
    user: appuser
    command: >
      sh -c "python manage.py collectstatic --noinput &&
             python manage.py migrate &&
             gunicorn core.wsgi:application --bind 0.0.0.0:8000"
    restart: unless-stopped
    mem_limit: 192m
    cpus: 0.4
    depends_on:
      - db
      - redis
    networks:
      - app_network

  celery_worker:
    build: .
    command: celery -A core.celery worker -l info
    restart: unless-stopped
    mem_limit: 192m
    cpus: 0.4
    depends_on:
      - redis
    networks:
      - app_network

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    mem_limit: 128m
    cpus: 0.2
    networks:
      - app_network

  db:
    image: postgres:15-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${DB_NAME}
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - db_data:/var/lib/postgresql/data
    mem_limit: 192m
    cpus: 0.3
    networks:
      - app_network

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    mem_limit: 128m
    cpus: 0.2
    networks:
      - app_network

networks:
  app_network:
    driver: bridge

volumes:
  db_data:
```

### Docker Compose Production Configuration Explanation

#### Services

##### web

- **build**: Specifies the build context for the Docker image, using the current directory (`.`).
- **command**: Supplies the production WSGI server process that the image’s ENTRYPOINT will exec (e.g. ["gunicorn","core.wsgi:application","--bind","0.0.0.0:8000"]).
- **restart**: Configures the container to restart unless stopped manually.
- **mem_limit**: Limits the memory usage to **192 MB**.
- **cpus**: Allocates **0.4 CPU** units for this service.
- **depends_on**: Ensures that the `db` and `redis` services are started before this service.
- **networks**: Connects the service to the `app_network`.

##### celery_worker

- **build**: Uses the same build context as the `web` service.
- **command**: Runs the Celery worker with the specified settings.
- **restart**: Configures the container to restart unless stopped manually.
- **mem_limit**: Limits the memory usage to **192 MB**.
- **cpus**: Allocates **0.4 CPU** units for this service.
- **depends_on**: Ensures that the `redis` service is started before this service.
- **networks**: Connects to the `app_network`.

##### redis

- **image**: Uses the official Redis image (`redis:7-alpine`).
- **restart**: Configures the container to restart unless stopped manually.
- **mem_limit**: Limits the memory usage to **128 MB**.
- **cpus**: Allocates **0.2 CPU** units for this service.
- **networks**: Connects to the `app_network`.

##### db

- **image**: Uses the official PostgreSQL image (`postgres:15-alpine`).
- **restart**: Configures the container to restart unless stopped manually.
- **environment**: Sets environment variables for the database name, user, and password using values from the `.env` file.
- **volumes**: Mounts a named volume `db_data` to `/var/lib/postgresql/data` for database storage.
- **mem_limit**: Limits the memory usage to **192 MB**.
- **cpus**: Allocates **0.3 CPU** units for this service.
- **networks**: Connects to the `app_network`.

##### nginx

- **image**: Uses the official Nginx image (`nginx:alpine`).
- **restart**: Configures the container to restart unless stopped manually.
- **mem_limit**: Limits the memory usage to **128 MB**.
- **cpus**: Allocates **0.2 CPU** units for this service.
- **networks**: Connects to the `app_network`.

#### Networks

- **app_network**: A custom bridge network for internal communication between services.

#### Volumes

- **db_data**: Named volume for PostgreSQL data.

## Why the Allocation of Memory Limits and CPU?

I will be hosting the project on a very small EC2 instance, and so, I want to prevent any single service from consuming too many resources. It is the same reason why I configured all the resources to start unless they're stopped.

---

## Environment Variables

We're almost close to running our app again. Now, let's create development environment variables file `.env`. Copy the code below into the .env file.

```ini
# Django Settings
DJANGO_SECRET_KEY='<very strong secret>'
DJANGO_SETTINGS_MODULE='core.settings'

# Database Settings (for local Dockerized PostgreSQL)
DB_NAME="scrapper_db"
DB_USER="scrapper"
DB_PASSWORD="<strong password>"
DB_HOST=db # This is the service name of your PostgreSQL container in docker-compose.yml
DB_PORT=5432

# Redis Settings (for Celery and Caching)
REDIS_HOST=redis # This is the service name of your Redis container in docker-compose.yml
REDIS_PORT=6379
REDIS_DB=0 # Redis database number
REDIS_URL = 'redis://redis:6379/0'

DEBUG=True
```

## Create .gitignore and .dockerignore Files

Run the command below:

```bash
touch .gitignore .dockerignore
```

Copy the code below and paste into the `.gitignore` file:

```shell
# Python
__pycache__/
*.pyc
*.pyd
*.pyo
.Python
env/
venv/
.venv/ # Common for venv created by VS Code or newer pip versions
*.env # Crucial: do NOT commit your actual environment variables!
.python-version # For pyenv
.env

# Django
*.sqlite3
/media/ # Directory for user-uploaded files (these should be stored on S3 in production)
/static_cdn/ # Directory for collected static files (these will also be on S3 in production)
migrations/

# Operating System Files
.DS_Store # macOS
.envrc # direnv config
Thumbs.db # Windows
ehthumbs.db # Windows
.directory # Linux (KDE)

# IDEs
.idea/
.vscode/ # VS Code
*.iml # IntelliJ modules
.project # Eclipse
.settings/ # Eclipse

# Docker
*.log # General log files
.dockerignore # We keep this in git, but sometimes people exclude it
docker-compose.yml # We will keep this in git as it defines the environment
Dockerfile # We will keep this in git

# Celery
celerybeat-schedule # Celery Beat scheduler file
celeryd.pid # Celery worker PID file
```

Copy the code below and paste into the `.dockerignore` file:

```shell
# Ignore Git-related files

.git
.gitignore

# Ignore Python-specific files and directories

**pycache**/
_.pyc
_.pyd
_.pyo
.Python
env/
venv/
.venv/
_.env # Crucial: Your actual .env file should NOT be in the Docker image!
.python-version

# Ignore Django-specific files

\*.sqlite3
/media/ # User-uploaded files (will be on S3 in production)
/static_cdn/ # Collected static files (will be served via WhiteNoise/S3 in production)

# Ignore IDE/Editor specific files

.idea/
.vscode/
\*.iml
.project
.settings/

# Ignore general log files

\*.log

# Celery specific files

celerybeat-schedule # Celery Beat scheduler file
celeryd.pid # Celery worker PID file

# Docker build files themselves (no need to copy them into the image being built)

Dockerfile
docker-compose.yml
```
---


## Let's Change Some Settings in setting.py

1. Let's import config from decouple. Copy the text below and paste at the top of your settings file:

```python
from decouple import config
```

2. Set the value of `SECRET_KEY` to `config("DJANGO_SECRET_KEY")` in settings.py.

3. Set `DEBUG` to `config('DEBUG', default=False, cast=bool)`

4. Copy and paste the code below in place of `DATABASES` in settings.py:

```python
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": config("DB_NAME"),
        "USER": config("DB_USER"),
        "PASSWORD": config("DB_PASSWORD"),
        "HOST": config("DB_HOST"),
        "PORT": config("DB_PORT", default=5432),
    }
}
```

5. Set the following static variables to the following values:

```python
STATIC_URL = "static/"

STATIC_ROOT = BASE_DIR / "staticfiles"

STATICFILES_DIRS = [BASE_DIR / "static"]
```

6. Add the following celery settings at the bottom of the settings.py file:

```python
# Celery Settings
CELERY_BROKER_URL = config("REDIS_URL", default="redis://redis:6379/0")
CELERY_RESULT_BACKEND = config("REDIS_URL", default="redis://redis:6379/0")

CELERY_ACCEPT_CONTENT = ["json"]
CELERY_TASK_SERIALIZER = "json"
CELERY_RESULT_SERIALIZER = "json"
CELERY_TIMEZONE = "Africa/Accra"
CELERY_TASK_TRACK_STARTED = True
CELERY_TASK_TIME_LIMIT = 5 * 60
```

### Celery Settings Explanation

#### CELERY_BROKER_URL

- **Value**: `config("REDIS_URL", default="redis://redis:6379/0")`
- **Description**: Specifies the URL of the message broker that Celery will use to send and receive messages. Defaults to a Redis server running on `localhost` at port `6379`, using database `0`.

#### CELERY_RESULT_BACKEND

- **Value**: `config("REDIS_URL", default="redis://redis:6379/0")`
- **Description**: Defines where Celery will store the results of tasks. By default, it uses the same Redis URL as the broker.

#### CELERY_ACCEPT_CONTENT

- **Value**: `["json"]`
- **Description**: Indicates the content types that Celery will accept for tasks. In this case, it is set to accept only JSON.

#### CELERY_TASK_SERIALIZER

- **Value**: `"json"`
- **Description**: Specifies the serialization format for tasks when they are sent to the broker. Tasks will be serialized in JSON format.

#### CELERY_RESULT_SERIALIZER

- **Value**: `"json"`
- **Description**: Defines the serialization format for the results of tasks. It is also set to JSON.

#### CELERY_TIMEZONE

- **Value**: `"Africa/Accra"`
- **Description**: Sets the timezone for the Celery worker. It is configured to use the timezone of Accra, Ghana.

#### CELERY_TASK_TRACK_STARTED

- **Value**: `True`
- **Description**: Enables tracking of task states, allowing you to see when a task has started.

#### CELERY_TASK_TIME_LIMIT

- **Value**: `5 * 60`
- **Description**: Sets a time limit for tasks, in seconds. Here, it is set to 5 minutes (5 \* 60 seconds). If a task exceeds this time limit, it will be terminated.

## Create celery.py in the core directory.

After creating celery.py, the file tree of the project should look like this:

```tree
django_celery_redis_tutorial
├── core/
│   ├──__init__.py
│   ├── celery.py
│   ├── asgi.py
│   ├── settings.py
│   ├── urls.py
│   └── wsgi.py
│
├── .dockerignore
├── .env
├── .gitignore
├── docker-compose.dev.yml
├── docker-compose.prod.yml
├── Dockerfile
├── entrypoint.sh
├── manage.py
└── requirements.txt
```

Copy and paste the code below into `celery.py:

```python
from __future__ import absolute_import, unicode_literals
import os
from celery import Celery

# Set the default Django settings module
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "tts_project.settings")

# Create a Celery instance named 'tts_project'
app = Celery("tts_project")

# Load configuration from Django settings
app.config_from_object("django.conf:settings", namespace="CELERY")

# Autodiscover tasks
app.autodiscover_tasks()
```
---

## Let's set up core/ to make sure that celery app is loaded when Django is started

Now, put the snippet:

```python
from .celery import app as celery_app

__all__ = ("celery_app",)
```

in your Django project’s `__init__.py` (`core/__init__.py`).

---

### What it does

1. **Imports the Celery app instance**

   * The `core/celery.py` file defines the Celery application:

     ```python
     from celery import Celery
     app = Celery("core")
     ```
   * By importing it in `__init__.py`, you make sure that whenever Django loads the project, the Celery app is also available.

2. **Registers it as a top-level attribute (`core.celery_app`)**

   * With `__all__ = ("celery_app",)`, you’re explicitly saying:

     > “When someone does `from core import *`, only expose `celery_app`.”
   * It’s a way of controlling what’s exported and making `celery_app` the official public symbol of your project.

3. **Enables Django auto-discovery of tasks**

   * Celery uses `celery_app.autodiscover_tasks()` in `celery.py` to automatically find `tasks.py` inside your Django apps.

   * By making `celery_app` importable from `core`, Celery workers can start with:

     ```sh
     celery -A core worker -l info
     ```

     because Celery will look for `celery_app` inside the `core` package.

   * If you didn’t have this, you’d need to run:

     ```sh
     celery -A core.celery worker -l info
     ```

     (longer and less standard).

---

### In short

Putting that in `__init__.py` makes:

* Your Celery app discoverable at the project level (`core.celery_app`).
* The command `celery -A core worker` work (instead of needing `core.celery`).
* Django + Celery integration smoother and consistent with the docs.

---

`Tip`: If you remove it, Celery won’t break — you’d just have to change your `-A` argument to `core.celery`.

---

## Let run the docker-compose to  see the state of our code so far

Copy and past the code below:
```bash
docker-compose -f docker-compose.dev.yml up --build
```
After eveything finish downloading and the containers and volumes are created, open http://localhost:8000 in the browser.
You should see the Django welcome page there.

## Let's create the web_scrapper app

First of all, let's give appuser permission to create apps in /app.
Open a new terminal and run the code below:

```bash
docker-compose -f docker-compose.dev.yml exec web id appuser
```
The command above just outputed the uid for appuser and gid for appgroup.
Run the command below to give appuser the permission:

```bash
sudo chown -R <uid>:<gid> .
```

Now, run the command below to create web_scrapper app:

```bash
docker-compose -f docker-compose.dev.yml exec web python manage.py startapp web_scrapper
```

We need to give your host user permission to be able to edit the files again. Run the command below:
```bash
sudo chown -R $USER:$USER .
```

The `django_celery_redis_tutorial` directory tree should look like this:
```tree
django_celery_redis_tutorial
├── core/
│   ├──__init__.py
│   ├── celery.py
│   ├── asgi.py
│   ├── settings.py
│   ├── urls.py
│   └── wsgi.py
│
├── media
├── static
├── staticfiles
│
├── web_scrapper/
│   ├──__init__.py
│   ├── admin.py
│   ├── apps.py
│   ├── models.py
│   ├── tests.py
│   └── views.py
│
├── .dockerignore
├── .env
├── .gitignore
├── docker-compose.dev.yml
├── docker-compose.prod.yml
├── Dockerfile
├── entrypoint.sh
├── manage.py
└── requirements.txt
```

Before we move on, let's create a `urls.py` file in `web_scrapper/` and update `core/settings.py` about web_scrapper app.
Run the command below in your terminal to create urls.py in web_scrapper:

```bash
touch web_scrapper/urls.py
```

Open core/settings.py and modify INSTALLED_APPS by appending INSTALLED_APPS with "web_scrapper.apps.WebScrapperConfig":

```python

INSTALLED_APPS = [
    ...,
    ...,
    "web_scrapper.apps.WebScrapperConfig",
]
```

