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

   b. copy and paste the command below and press enter:

   ```bash
   deactivate
   ```

## Setting Up Docker
At this point, you need Docker installed on your machine, if you don't have it, then head over to [https://docs.docker.com/get-started/get-docker/](https://docs.docker.com/get-started/get-docker/) to get it installed and continue with the following steps:

1. From this stage onwards, we don't need the virtual environment again, so let's go ahead and delete the .venv/ directory:

```bash
rm -r .venv
```

2. Let's create a Dockerfile:
```bash
touch Dockerfile
```
`Note for those who don't know what a Docker file is:` A [Dockerfile](https://docs.docker.com/reference/dockerfile/) is a text file that contains a set of instructions for building a Docker image. In simple terms, it acts like a recipe that tells Docker how to create an environment for our application.

3. At this point, you can choose to open your favorite IDE/text editor or open VSCode with the command:
```bash
code .
```

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

# Now that the database is ready, run the Django commands
echo "Running migrations..."
python manage.py migrate --noinput

echo "Collecting static files..."
python manage.py collectstatic --noinput
```

6. Let's go ahead and create `docker-compose.dev.yml`. A `docker-compose.yml` file is a configuration file used by Docker Compose, a tool that helps you define and manage multi-container Docker applications. In simple terms, it allows you to specify how different services (like databases, web servers, and application servers) should work together in a single application. Read more about `docker-compose.yml` at [https://docs.docker.com/compose/intro/compose-application-model/](https://docs.docker.com/compose/intro/compose-application-model/). You might be wondering why we are naming our `docker-compose.yml` `docker-compose.dev.yml`. We're doing this because we want to have one docker-compose.yml for development environment which will contain configuration for Flower and one for production environment which will contain configuration for Gunicorn and Nginx without configuration for Flower. So as the name clearly shows, `docker-compose.dev.yml` is for development environment. After populating this with code. We're going to create `docker-compose.prod.yml`.

   Use the command below to create docker-compose.dev.yml:
   ```bash
   touch docker-compose.dev.yml
   ```
   Populate it with the code below:
```yaml
   
services:
  # Django Web Application Service
  web:
    build: .
    command: /app/entrypoint.sh
    volumes:
      - .:/app
      - static_data:/app/static_cdn
    ports:
      - "8000:8000"
    # We use env_file to load the bulk of our settings like SECRET_KEY, DEBUG, etc.
    env_file:
      - .env
    environment:
      - REDIS_URL=redis://redis:6379/0
      - SITE_DOMAIN=localhost:8000
      - SITE_NAME=TTS_Project Dev
      - DJANGO_SETTINGS_MODULE=tts_project.settings.dev
    depends_on:
      - db
      - redis
    networks:
      - app_network

  # Celery Worker Service
  celery_worker:
    build: .
    command: celery -A core.settings.celery worker -l info
    volumes:
      - .:/app
      - media_data:/app/media
    env_file:
      - .env
    # Add the user directive
    user: "appuser:appgroup"
    depends_on:
      - web
      - redis
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
    image: mher/flower
    command: ["celery", "-A", "core.settings", "flower", "--port=5555"]
    ports:
      - "5555:5555"
    depends_on:
      - redis
      - celery_worker

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
  media_data:
  static_data:

# Define a custom bridge network for internal communication.
networks:
  app_network:
    driver: bridge
```
