#!/bin/bash
# ElevatedIQ Lambda Packager (Phase 9.2)
# Packages apps/cost-optimizer-lambda with local libs.

set -e

APP_DIR="apps/cost-optimizer-lambda"
PACKAGE_NAME="cost_optimizer_lambda.zip"
DIST_DIR="dist/lambdas"

echo "📦 Packaging Cost Optimizer Lambda..."

# 1. Create clean build dir
BUILD_DIR="temp_lambda_build"
rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR

# 2. Copy application code
cp $APP_DIR/cost_optimizer_lambda/handler.py $BUILD_DIR/

# 3. Copy required libs (maintaining structure)
mkdir -p $BUILD_DIR/libs/queue
cp libs/queue/cost_optimization_messages.py $BUILD_DIR/libs/queue/
touch $BUILD_DIR/libs/__init__.py
touch $BUILD_DIR/libs/queue/__init__.py

# 4. Install external dependencies (if needed, e.g. psycopg2)
# Note: For Lambda, we often need AWS-compatible binaries for psycopg2 (psycopg2-binary)
# pip install psycopg2-binary -t $BUILD_DIR

# 5. Create ZIP
mkdir -p $DIST_DIR
python3 -c "import shutil; shutil.make_archive('dist/lambdas/cost_optimizer_lambda', 'zip', '$BUILD_DIR')"

# 6. Copy to Terraform module directory for deployment
cp $DIST_DIR/$PACKAGE_NAME infra/terraform/modules/phase-9-2-aws-infra/

echo "✅ Lambda package created at infra/terraform/modules/phase-9-2-aws-infra/$PACKAGE_NAME"
rm -rf $BUILD_DIR
