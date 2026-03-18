FROM ultralytics/ultralytics:latest

# Install Flask for API server
RUN pip install --no-cache-dir flask

WORKDIR /app

# Copy the Python server script
COPY server.py /app/server.py

EXPOSE 8080

CMD ["python3", "/app/server.py"]
