.PHONY: help build test lint format clean install dev

help:
	@echo "Available targets:"
	@echo "  make install      - Install dependencies"
	@echo "  make dev          - Install dev dependencies"
	@echo "  make lint         - Run linters (ruff, mypy, pylint)"
	@echo "  make format       - Format code (black, isort)"
	@echo "  make test         - Run unit tests (pytest)"
	@echo "  make build        - Build Docker image"
	@echo "  make clean        - Clean build artifacts and cache"

install:
	pip install --no-cache-dir -r requirements.txt

dev:
	pip install --no-cache-dir -r requirements.txt -r requirements-dev.txt

lint:
	ruff check . --fix || true
	mypy . --ignore-missing-imports || true
	pylint **/*.py --exit-zero || true

format:
	black .
	isort .

test:
	pytest tests/ -v --cov=. --cov-report=term-missing --cov-report=html

build:
	docker build -t $(SERVICE_NAME):latest .

clean:
	find . -type d -name __pycache__ -exec rm -rf {} + || true
	find . -type f -name "*.pyc" -delete
	rm -rf .pytest_cache htmlcov .mypy_cache .ruff_cache
