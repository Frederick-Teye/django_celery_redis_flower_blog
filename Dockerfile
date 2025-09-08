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

# Ensure the staticfiles directory exists and has the correct permissions
RUN mkdir -p /app/staticfiles && chown -R appuser:appgroup /app/staticfiles

# Change ownership of the application directory to the new user
RUN chown -R appuser:appgroup /app

RUN chmod +x /app/entrypoint.sh

# Switch to the non-root user
USER appuser

# Expose the port the app runs on
EXPOSE 8000

# Run the entrypoint script
ENTRYPOINT ["/app/entrypoint.sh"]