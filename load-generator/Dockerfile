FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir \
    requests \
    numpy \
    pillow

COPY load-client.py .

CMD ["python", "load-client.py"]
