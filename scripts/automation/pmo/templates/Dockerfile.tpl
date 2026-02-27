FROM python:3.11-slim
WORKDIR /app
COPY . /app
RUN pip install --no-cache-dir -r requirements.txt || true
CMD ["bash", "-c", "echo 'No start command provided for this service.' && sleep infinity"]
