#!/bin/bash
# =============================================================================
# EC2 User Data – Bootstrap Script
# Rendered by Terraform templatefile(); variables injected at plan time.
# =============================================================================
set -euo pipefail

AWS_REGION="${aws_region}"
SECRET_ARN="${secret_arn}"
DB_HOST="${db_host}"
DB_NAME="${db_name}"
S3_BUCKET="${s3_bucket}"
PROJECT="${project_name}"
ENV="${environment}"

# ── System Updates ────────────────────────────────────────────────────────────
yum update -y
yum install -y \
  amazon-cloudwatch-agent \
  amazon-ssm-agent \
  jq \
  curl \
  git \
  gcc \
  make \
  openssl \
  python3 \
  python3-pip \
  mysql

# ── Enable SSM Agent ─────────────────────────────────────────────────────────
systemctl enable amazon-ssm-agent
systemctl start  amazon-ssm-agent

# ── Fetch DB credentials from Secrets Manager ────────────────────────────────
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" \
  --region    "$AWS_REGION" \
  --query     SecretString \
  --output    text)

DB_USER=$(echo "$SECRET" | jq -r .username)
DB_PASS=$(echo "$SECRET" | jq -r .password)

# ── Install Node.js 20 (LTS) ─────────────────────────────────────────────────
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
yum install -y nodejs

# ── Deploy application from S3 ───────────────────────────────────────────────
mkdir -p /opt/app
aws s3 cp "s3://$S3_BUCKET/releases/latest/app.tar.gz" /tmp/app.tar.gz --region "$AWS_REGION" || true

if [[ -f /tmp/app.tar.gz ]]; then
  tar -xzf /tmp/app.tar.gz -C /opt/app
fi

# ── Write environment configuration ──────────────────────────────────────────
cat > /opt/app/.env <<EOF
NODE_ENV=$ENV
PORT=80
DB_HOST=$DB_HOST
DB_PORT=3306
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS
S3_BUCKET=$S3_BUCKET
AWS_REGION=$AWS_REGION
EOF
chmod 600 /opt/app/.env

# ── Install application dependencies and start ───────────────────────────────
if [[ -f /opt/app/package.json ]]; then
  cd /opt/app
  npm ci --production
  npm start &
fi

# ── CloudWatch Agent configuration ───────────────────────────────────────────
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWCONFIG'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/app/*.log",
            "log_group_name": "/aws/ec2/APP_LOG_GROUP",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%Y-%m-%dT%H:%M:%S"
          },
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/aws/ec2/APP_LOG_GROUP/system",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "DevOps/EC2",
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
        "metrics_collection_interval": 60
      },
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["disk_used_percent"],
        "resources": ["/"],
        "metrics_collection_interval": 60
      }
    }
  }
}
CWCONFIG

# Replace placeholder with actual log group name
sed -i "s|APP_LOG_GROUP|$PROJECT-$ENV|g" \
  /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s

systemctl enable amazon-cloudwatch-agent
systemctl start  amazon-cloudwatch-agent

# ── Simple health-check endpoint (fallback if app not deployed yet) ───────────
if ! ss -tlnp | grep -q ':80 '; then
  cat > /etc/systemd/system/healthcheck.service <<'UNIT'
[Unit]
Description=Minimal HTTP health-check server
After=network.target

[Service]
ExecStart=/usr/bin/python3 -m http.server 80
WorkingDirectory=/tmp
Restart=always

[Install]
WantedBy=multi-user.target
UNIT

  # Serve a valid /health response
  mkdir -p /tmp
  cat > /tmp/health <<'HTML'
{"status":"ok"}
HTML

  systemctl daemon-reload
  systemctl enable healthcheck
  systemctl start  healthcheck
fi

echo "Bootstrap complete – $(date)" >> /var/log/user-data.log
