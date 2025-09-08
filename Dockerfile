# Base image matching your requirement for Python 3.10
FROM python:3.10-slim

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# [cite_start]Install system dependencies based on the install guide [cite: 102]
RUN apt-get update && apt-get install -y \
    build-essential \
    libxml2-dev \
    libxslt1-dev \
    libffi-dev \
    libpq-dev \
    libssl-dev \
    zlib1g-dev \
    nginx \
    && rm -rf /var/lib/apt/lists/*

# [cite_start]Set working directory [cite: 105]
WORKDIR /opt/status-page

# Copy all application code into the container
COPY . /opt/status-page/

# [cite_start]Install Python dependencies from requirements.txt [cite: 208]
RUN pip install --upgrade pip
RUN pip install -r requirements.txt
# Add gunicorn and psycopg2 for production use
RUN pip install gunicorn psycopg2-binary

# Make the entrypoint script executable
COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# This directory will be where static files are collected for the EFS volume
RUN mkdir -p /opt/status-page/static_files
RUN chown -R www-data:www-data /opt/status-page

# Expose the port Gunicorn will run on
EXPOSE 8000

# Run the entrypoint script
ENTRYPOINT ["/entrypoint.sh"]
