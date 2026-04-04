#!/bin/bash
# ============================================================
# destroy-aws.sh
# Safe teardown of SilverBank AWS infrastructure
# Disables deletion protection before terraform destroy
# ============================================================

set -e

cd "$(dirname "$0")"

echo "============================================"
echo "SilverBank AWS — Infrastructure Teardown"
echo "============================================"
echo ""
echo "⚠️  WARNING: This will destroy ALL AWS resources"
echo "⚠️  Costs stop immediately after completion"
echo ""
read -p "Are you sure you want to destroy? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

echo "Step 1 — Scaling down ASGs to 0 to prevent new instance launches..."
for ASG in silverbank-blue-asg-production silverbank-green-asg-production; do
  aws autoscaling update-auto-scaling-group \
    --auto-scaling-group-name ${ASG} \
    --min-size 0 --max-size 0 --desired-capacity 0 \
    --region eu-west-2 2>/dev/null && \
    echo "✅ ${ASG} scaled to 0" || \
    echo "⚠️  ${ASG} not found — skipping"
done

echo "Waiting 60s for instances to terminate..."
sleep 60

echo ""
echo "Step 2 — Disabling RDS deletion protection..."
RDS_ID=$(terraform output -raw rds_endpoint | cut -d'.' -f1 2>/dev/null || echo "")

if [ -n "$RDS_ID" ]; then
  aws rds modify-db-instance \
    --db-instance-identifier silverbank-db-production \
    --no-deletion-protection \
    --apply-immediately \
    --region eu-west-2
  echo "✅ RDS deletion protection disabled"

  echo "Waiting for RDS to apply changes..."
  aws rds wait db-instance-available \
    --db-instance-identifier silverbank-db-production \
    --region eu-west-2
  echo "✅ RDS ready"
else
  echo "⚠️  RDS not found — skipping"
fi

echo ""
echo "Step 3 — Disabling ALB deletion protection..."
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --names silverbank-alb-production \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text \
  --region eu-west-2 2>/dev/null || echo "")

if [ -n "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
  aws elbv2 modify-load-balancer-attributes \
    --load-balancer-arn $ALB_ARN \
    --attributes Key=deletion_protection.enabled,Value=false \
    --region eu-west-2
  echo "✅ ALB deletion protection disabled"
else
  echo "⚠️  ALB not found — skipping"
fi

echo ""
echo "Step 4 — Deleting ECR images before destroy..."
for REPO in silverbank-app-frontend silverbank-app-backend; do
  echo "Clearing ECR repository: ${REPO}..."
  IMAGE_IDS=$(aws ecr list-images \
    --repository-name ${REPO} \
    --region eu-west-2 \
    --query 'imageIds[*]' \
    --output json 2>/dev/null || echo "[]")

  if [ "$IMAGE_IDS" != "[]" ] && [ "$IMAGE_IDS" != "" ]; then
    aws ecr batch-delete-image \
      --repository-name ${REPO} \
      --image-ids "${IMAGE_IDS}" \
      --region eu-west-2 > /dev/null
    echo "✅ ECR ${REPO} cleared"
  else
    echo "⚠️  ECR ${REPO} already empty"
  fi
done

echo ""
echo "Step 5 — Running terraform destroy..."
terraform destroy -var-file="terraform-aws.tfvars" -auto-approve

echo ""
echo "============================================"
echo "✅ Infrastructure destroyed successfully"
echo "✅ Costs have stopped"
echo "============================================"
